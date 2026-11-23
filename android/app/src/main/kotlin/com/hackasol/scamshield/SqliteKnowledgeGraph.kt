package com.hackasol.scamshield

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import com.hackasol.scamshield.core.graph.EventType
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
        mapOf("brand" to e.brand, "type" to e.type.name, "ts_ms" to e.tsMs, "sender" to e.sender)

    /** Null if the row is unusable (unknown type, missing brand/ts). */
    fun eventFromRow(r: Map<String, Any?>): GraphEvent? {
        val type = EventType.values().firstOrNull { it.name == r["type"] } ?: return null
        return GraphEvent(
            brand = r["brand"] as? String ?: return null,
            type = type,
            tsMs = (r["ts_ms"] as? Number)?.toLong() ?: return null,
            sender = (r["sender"] as? String).orEmpty(),
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
}

/** SQLite-backed [GraphStore] (platform API only). All SQL is parameterised. Call off the main thread; never throws. */
class SqliteKnowledgeGraph(ctx: Context) : GraphStore {
    private val helper = object : SQLiteOpenHelper(ctx.applicationContext, "graph.db", null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, brand TEXT NOT NULL, " +
                "type TEXT NOT NULL, ts_ms INTEGER NOT NULL, sender TEXT NOT NULL)")
            db.execSQL("CREATE INDEX idx_events_brand ON events(brand)")
            db.execSQL("CREATE TABLE senders(sender TEXT PRIMARY KEY, first_seen INTEGER NOT NULL, " +
                "last_seen INTEGER NOT NULL, count INTEGER NOT NULL, is_dlt INTEGER NOT NULL)")
            db.execSQL("CREATE TABLE numbers(number TEXT PRIMARY KEY)")
            db.execSQL("CREATE TABLE upi_ids(upi_id TEXT PRIMARY KEY)")
            // Messages ingested so far: keeps "cold start" correct after a restart even if no entity was extracted.
            db.execSQL("CREATE TABLE meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}
    }

    override fun load(): GraphSnapshot = try {
        val db = helper.writableDatabase
        db.delete("events", "ts_ms < ?", arrayOf((System.currentTimeMillis() - GraphStore.EVENT_RETENTION_MS).toString()))
        GraphSnapshot(
            ingested = db.rawQuery("SELECT value FROM meta WHERE key = ?", arrayOf(INGESTED)).use { if (it.moveToFirst()) it.getInt(0) else 0 },
            senders = rows(db, "senders", listOf("sender", "first_seen", "last_seen", "count", "is_dlt")).mapNotNull(GraphRowMapper::senderFromRow),
            numbers = rows(db, "numbers", listOf("number")).mapNotNull(GraphRowMapper::numberFromRow),
            upiIds = rows(db, "upi_ids", listOf("upi_id")).mapNotNull(GraphRowMapper::upiFromRow),
            events = rows(db, "events", listOf("brand", "type", "ts_ms", "sender")).mapNotNull(GraphRowMapper::eventFromRow),
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
                delta.numbers.forEach { db.execSQL("INSERT OR IGNORE INTO numbers(number) VALUES(?)", arrayOf<Any>(it)) }
                delta.upiIds.forEach { db.execSQL("INSERT OR IGNORE INTO upi_ids(upi_id) VALUES(?)", arrayOf<Any>(it)) }
                delta.events.forEach { e ->
                    val cv = ContentValues()
                    for ((k, v) in GraphRowMapper.eventToRow(e)) when (v) {
                        is Long -> cv.put(k, v)
                        else -> cv.put(k, v.toString())
                    }
                    db.insert("events", null, cv)
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "graph apply failed", t)
        }
    }

    private fun rows(db: SQLiteDatabase, table: String, cols: List<String>): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        db.query(table, cols.toTypedArray(), null, null, null, null, null).use { c ->
            while (c.moveToNext()) {
                out += cols.mapIndexed { i, name ->
                    name to when (c.getType(i)) {
                        Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
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
