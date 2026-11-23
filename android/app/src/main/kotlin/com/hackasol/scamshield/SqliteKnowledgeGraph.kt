package com.hackasol.scamshield

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import com.hackasol.scamshield.core.graph.AlertRef
import com.hackasol.scamshield.core.graph.EntityKind
import com.hackasol.scamshield.core.graph.EventType
import com.hackasol.scamshield.core.graph.TrustRecord
import com.hackasol.scamshield.core.graph.TrustStatus
import com.hackasol.scamshield.core.graph.GraphEvent
import com.hackasol.scamshield.core.graph.GraphSnapshot
import com.hackasol.scamshield.core.graph.GraphStore
import com.hackasol.scamshield.core.graph.IngestDelta
import com.hackasol.scamshield.core.graph.SenderRecord

/**
 * Pure entity <-> row mapping (JVM-testable). Row keys are the SQL column names.
 * Only extracted entities appear here; there is no column that could hold raw message text.
 */
object GraphRowMapper {
    fun eventToRow(e: GraphEvent): Map<String, Any?> =
        mapOf("brand" to e.brand, "type" to e.type.name, "ts_ms" to e.tsMs, "sender" to e.sender, "amount" to e.amountRupees)

    /** Null if the row is unusable (unknown type, missing brand/ts). A missing or null amount stays null. */
    fun eventFromRow(r: Map<String, Any?>): GraphEvent? {
        val type = EventType.values().firstOrNull { it.name == r["type"] } ?: return null
        return GraphEvent(
            brand = r["brand"] as? String ?: return null,
            type = type,
            tsMs = (r["ts_ms"] as? Number)?.toLong() ?: return null,
            sender = (r["sender"] as? String).orEmpty(),
            amountRupees = (r["amount"] as? Number)?.toDouble(),
        )
    }

    fun senderToRow(s: SenderRecord): Map<String, Any?> = mapOf(
        "sender" to s.sender, "first_seen" to s.firstSeenMs, "last_seen" to s.lastSeenMs,
        "count" to s.count.toLong(), "is_dlt" to if (s.isDlt) 1L else 0L,
    )

    fun senderFromRow(r: Map<String, Any?>): SenderRecord? = SenderRecord(
        sender = r["sender"] as? String ?: return null,
        firstSeenMs = (r["first_seen"] as? Number)?.toLong() ?: return null,
        lastSeenMs = (r["last_seen"] as? Number)?.toLong() ?: return null,
        count = (r["count"] as? Number)?.toInt() ?: 0,
        isDlt = ((r["is_dlt"] as? Number)?.toInt() ?: 0) != 0,
    )

    fun numberToRow(n: String): Map<String, Any?> = mapOf("number" to n)
    fun numberFromRow(r: Map<String, Any?>): String? = r["number"] as? String
    fun upiToRow(id: String): Map<String, Any?> = mapOf("upi_id" to id)
    fun upiFromRow(r: Map<String, Any?>): String? = r["upi_id"] as? String
    /** Last-seen of a numbers / upi_ids row; 0 (the column default) means "unknown". */
    fun lastSeenFromRow(r: Map<String, Any?>): Long? = (r["last_seen"] as? Number)?.toLong()?.takeIf { it > 0 }

    fun trustToRow(t: TrustRecord): Map<String, Any?> =
        mapOf("kind" to t.kind.name, "key" to t.key, "status" to t.status.name, "ts_ms" to t.tsMs)

    fun trustFromRow(r: Map<String, Any?>): TrustRecord? = TrustRecord(
        kind = EntityKind.values().firstOrNull { it.name == r["kind"] } ?: return null,
        key = r["key"] as? String ?: return null,
        status = TrustStatus.values().firstOrNull { it.name == r["status"] } ?: return null,
        tsMs = (r["ts_ms"] as? Number)?.toLong() ?: return null,
    )

    /** Entities only, comma-joined: a phone number or UPI id never contains a comma. No message text column exists. */
    fun alertRefToRow(r: AlertRef): Map<String, Any?> = mapOf(
        "ts_ms" to r.tsMs, "sender" to r.sender, "numbers" to r.numbers.joinToString(","), "upi_ids" to r.upiIds.joinToString(","),
    )

    fun alertRefFromRow(r: Map<String, Any?>): AlertRef? = AlertRef(
        tsMs = (r["ts_ms"] as? Number)?.toLong() ?: return null,
        sender = (r["sender"] as? String).orEmpty(),
        numbers = split(r["numbers"] as? String),
        upiIds = split(r["upi_ids"] as? String),
    )

    private fun split(s: String?): List<String> = s.orEmpty().split(',').filter { it.isNotBlank() }
}

/** SQLite-backed [GraphStore] (platform API only). All SQL is parameterised. Call off the main thread; never throws. */
class SqliteKnowledgeGraph(ctx: Context) : GraphStore {
    private val helper = object : SQLiteOpenHelper(ctx.applicationContext, "graph.db", null, 2) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, brand TEXT NOT NULL, " +
                "type TEXT NOT NULL, ts_ms INTEGER NOT NULL, sender TEXT NOT NULL, amount REAL)")
            db.execSQL("CREATE INDEX idx_events_brand ON events(brand)")
            db.execSQL("CREATE UNIQUE INDEX idx_events_uniq ON events(brand, type, sender, ts_ms)")
            db.execSQL("CREATE TABLE senders(sender TEXT PRIMARY KEY, first_seen INTEGER NOT NULL, " +
                "last_seen INTEGER NOT NULL, count INTEGER NOT NULL, is_dlt INTEGER NOT NULL)")
            db.execSQL("CREATE TABLE numbers(number TEXT PRIMARY KEY, last_seen INTEGER NOT NULL DEFAULT 0)")
            db.execSQL("CREATE TABLE upi_ids(upi_id TEXT PRIMARY KEY, last_seen INTEGER NOT NULL DEFAULT 0)")
            // Messages ingested so far: keeps "cold start" correct after a restart even if no entity was extracted.
            db.execSQL("CREATE TABLE meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
            createV2Tables(db)
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 2) {
                val now = System.currentTimeMillis()
                db.execSQL("ALTER TABLE events ADD COLUMN amount REAL")
                db.execSQL("ALTER TABLE numbers ADD COLUMN last_seen INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE upi_ids ADD COLUMN last_seen INTEGER NOT NULL DEFAULT 0")
                // Existing rows get "seen now" so the first prune does not wipe them.
                db.execSQL("UPDATE numbers SET last_seen = ?", arrayOf<Any>(now))
                db.execSQL("UPDATE upi_ids SET last_seen = ?", arrayOf<Any>(now))
                db.execSQL("DELETE FROM events WHERE id NOT IN (SELECT MIN(id) FROM events GROUP BY brand, type, sender, ts_ms)")
                db.execSQL("CREATE UNIQUE INDEX idx_events_uniq ON events(brand, type, sender, ts_ms)")
                createV2Tables(db)
            }
        }

        private fun createV2Tables(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE trust(kind TEXT NOT NULL, key TEXT NOT NULL, status TEXT NOT NULL, ts_ms INTEGER NOT NULL, PRIMARY KEY(kind, key))")
            db.execSQL("CREATE TABLE alert_refs(ts_ms INTEGER PRIMARY KEY, sender TEXT NOT NULL, numbers TEXT NOT NULL, upi_ids TEXT NOT NULL)")
        }
    }

    override fun load(): GraphSnapshot = try {
        val db = helper.writableDatabase
        val numberRows = rows(db, "numbers", listOf("number", "last_seen"))
        val upiRows = rows(db, "upi_ids", listOf("upi_id", "last_seen"))
        GraphSnapshot(
            ingested = db.rawQuery("SELECT value FROM meta WHERE key = ?", arrayOf(INGESTED)).use { if (it.moveToFirst()) it.getInt(0) else 0 },
            senders = rows(db, "senders", listOf("sender", "first_seen", "last_seen", "count", "is_dlt")).mapNotNull(GraphRowMapper::senderFromRow),
            numbers = numberRows.mapNotNull(GraphRowMapper::numberFromRow),
            upiIds = upiRows.mapNotNull(GraphRowMapper::upiFromRow),
            events = rows(db, "events", listOf("brand", "type", "ts_ms", "sender", "amount")).mapNotNull(GraphRowMapper::eventFromRow),
            numberLastSeen = numberRows.mapNotNull { r -> GraphRowMapper.numberFromRow(r)?.let { n -> GraphRowMapper.lastSeenFromRow(r)?.let { n to it } } }.toMap(),
            upiLastSeen = upiRows.mapNotNull { r -> GraphRowMapper.upiFromRow(r)?.let { u -> GraphRowMapper.lastSeenFromRow(r)?.let { u to it } } }.toMap(),
            trust = rows(db, "trust", listOf("kind", "key", "status", "ts_ms")).mapNotNull(GraphRowMapper::trustFromRow),
        )
    } catch (t: Throwable) {
        Log.e(TAG, "graph load failed", t)
        GraphSnapshot.EMPTY
    }

    override fun apply(delta: IngestDelta) {
        try {
            val db = helper.writableDatabase
            db.beginTransaction()
            try {
                db.execSQL("INSERT OR IGNORE INTO meta(key, value) VALUES(?, 0)", arrayOf<Any>(INGESTED))
                db.execSQL("UPDATE meta SET value = value + 1 WHERE key = ?", arrayOf<Any>(INGESTED))
                if (delta.sender.isNotEmpty()) {
                    // INSERT OR IGNORE + UPDATE instead of UPSERT: minSdk 26 ships SQLite older than 3.24.
                    db.execSQL("INSERT OR IGNORE INTO senders(sender, first_seen, last_seen, count, is_dlt) VALUES(?, ?, ?, 0, ?)",
                        arrayOf<Any>(delta.sender, delta.tsMs, delta.tsMs, if (delta.isDlt) 1L else 0L))
                    db.execSQL("UPDATE senders SET last_seen = MAX(last_seen, ?), count = count + 1 WHERE sender = ?",
                        arrayOf<Any>(delta.tsMs, delta.sender))
                }
                delta.numbers.forEach { touch(db, "numbers", "number", it, delta.tsMs) }
                delta.upiIds.forEach { touch(db, "upi_ids", "upi_id", it, delta.tsMs) }
                delta.events.forEach { e ->
                    val cv = ContentValues()
                    for ((k, v) in GraphRowMapper.eventToRow(e)) when (v) {
                        null -> cv.putNull(k)
                        is Long -> cv.put(k, v)
                        is Double -> cv.put(k, v)
                        else -> cv.put(k, v.toString())
                    }
                    db.insertWithOnConflict("events", null, cv, SQLiteDatabase.CONFLICT_IGNORE)   // unique (brand, type, sender, ts_ms)
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "graph apply failed", t)
        }
    }

    // table / col are fixed literals from this file, never input; the entity value is bound.
    private fun touch(db: SQLiteDatabase, table: String, col: String, value: String, tsMs: Long) {
        db.execSQL("INSERT OR IGNORE INTO $table($col, last_seen) VALUES(?, ?)", arrayOf<Any>(value, tsMs))
        db.execSQL("UPDATE $table SET last_seen = MAX(last_seen, ?) WHERE $col = ?", arrayOf<Any>(tsMs, value))
    }

    override fun prune(cutoffMs: Long) = safe("prune") { db ->
        val a = arrayOf<Any>(cutoffMs)
        db.execSQL("DELETE FROM events WHERE ts_ms < ?", a)
        db.execSQL("DELETE FROM senders WHERE last_seen < ?", a)
        db.execSQL("DELETE FROM numbers WHERE last_seen < ?", a)
        db.execSQL("DELETE FROM upi_ids WHERE last_seen < ?", a)
        db.execSQL("DELETE FROM alert_refs WHERE ts_ms < ?", a)
    }

    override fun clear(): Boolean = try {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            listOf("events", "senders", "numbers", "upi_ids", "meta", "trust", "alert_refs").forEach { db.delete(it, null, null) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        true
    } catch (t: Throwable) {
        Log.e(TAG, "graph clear failed", t)
        false
    }

    override fun mark(kind: EntityKind, key: String, status: TrustStatus, tsMs: Long) = safe("mark") { db ->
        db.execSQL("INSERT OR REPLACE INTO trust(kind, key, status, ts_ms) VALUES(?, ?, ?, ?)", arrayOf<Any>(kind.name, key, status.name, tsMs))
    }

    override fun putAlertRef(r: AlertRef) = safe("putAlertRef") { db ->
        val row = GraphRowMapper.alertRefToRow(r)
        db.execSQL("INSERT OR REPLACE INTO alert_refs(ts_ms, sender, numbers, upi_ids) VALUES(?, ?, ?, ?)",
            arrayOf<Any>(r.tsMs, row["sender"] as String, row["numbers"] as String, row["upi_ids"] as String))
    }

    override fun alertRef(tsMs: Long): AlertRef? = try {
        val db = helper.readableDatabase
        db.query("alert_refs", arrayOf("ts_ms", "sender", "numbers", "upi_ids"), "ts_ms = ?", arrayOf(tsMs.toString()), null, null, null).use { c ->
            if (!c.moveToFirst()) null
            else GraphRowMapper.alertRefFromRow(mapOf("ts_ms" to c.getLong(0), "sender" to c.getString(1), "numbers" to c.getString(2), "upi_ids" to c.getString(3)))
        }
    } catch (t: Throwable) {
        Log.e(TAG, "alertRef failed", t)
        null
    }

    private inline fun safe(what: String, block: (SQLiteDatabase) -> Unit) {
        try { block(helper.writableDatabase) } catch (t: Throwable) { Log.e(TAG, "graph $what failed", t) }
    }

    private fun rows(db: SQLiteDatabase, table: String, cols: List<String>): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        db.query(table, cols.toTypedArray(), null, null, null, null, null).use { c ->
            while (c.moveToNext()) {
                out += cols.mapIndexed { i, name ->
                    name to when (c.getType(i)) {
                        Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
                        Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
                        Cursor.FIELD_TYPE_NULL -> null
                        else -> c.getString(i)
                    }
                }.toMap()
            }
        }
        return out
    }

    private companion object {
        const val TAG = "ScamShield/GraphDb"
        const val INGESTED = "ingested"
    }
}
