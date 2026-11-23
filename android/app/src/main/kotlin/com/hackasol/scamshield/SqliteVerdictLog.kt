package com.hackasol.scamshield

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.VerdictEvent
import com.hackasol.scamshield.core.VerdictLog
import com.hackasol.scamshield.core.jsonQuote

/**
 * Pure row <-> event mapping (no Android imports at runtime, so JVM-testable).
 * Triggers are stored as a JSON array of strings: unlike a delimiter join it cannot be broken by trigger content.
 * Row keys are the SQL column names; `id` is absent on insert (AUTOINCREMENT assigns it).
 */
object VerdictRowMapper {
    fun toRow(e: VerdictEvent): Map<String, Any?> = mapOf(
        "ts_ms" to e.tsMs,
        "source" to e.source.name,
        "label" to e.label.name,
        "confidence" to e.confidence,
        "scam_type" to e.scamType?.name,
        "triggers" to encodeTriggers(e.triggers),
        "engine" to e.engine,
    )

    /** Null if the row is unusable (unknown label); unknown source falls back like Source.parse. */
    fun fromRow(r: Map<String, Any?>): VerdictEvent? {
        val label = Label.parse(r["label"] as? String) ?: return null
        return VerdictEvent(
            id = (r["id"] as? Number)?.toLong() ?: 0L,
            tsMs = (r["ts_ms"] as? Number)?.toLong() ?: return null,
            source = Source.parse(r["source"] as? String),
            label = label,
            confidence = (r["confidence"] as? Number)?.toDouble() ?: 0.0,
            scamType = ScamType.parse(r["scam_type"] as? String),
            triggers = decodeTriggers(r["triggers"] as? String),
            engine = (r["engine"] as? String).orEmpty(),
        )
    }

    /** Shape sent over the Flutter channel (camelCase, like Verdict.toMap). */
    fun toChannelMap(e: VerdictEvent): Map<String, Any?> = mapOf(
        "id" to e.id,
        "tsMs" to e.tsMs,
        "source" to e.source.name.lowercase(),
        "label" to e.label.name,
        "confidence" to e.confidence,
        "scamType" to e.scamType?.name,
        "triggers" to e.triggers,
        "engine" to e.engine,
    )

    fun encodeTriggers(t: List<String>): String = t.joinToString(",", "[", "]") { jsonQuote(it) }

    /** Parses only what encodeTriggers writes; malformed input yields whatever parsed so far (never throws). */
    fun decodeTriggers(s: String?): List<String> {
        if (s.isNullOrEmpty()) return emptyList()
        val out = ArrayList<String>()
        var i = 0
        while (i < s.length) {
            if (s[i] != '"') { i++; continue }
            i++
            val sb = StringBuilder()
            while (i < s.length && s[i] != '"') {
                val c = s[i]
                if (c == '\\' && i + 1 < s.length) {
                    i++
                    when (val n = s[i]) {
                        'n' -> sb.append('\n'); 'r' -> sb.append('\r'); 't' -> sb.append('\t')
                        'u' -> {
                            val hex = s.substring(i + 1, minOf(i + 5, s.length))
                            val cp = hex.toIntOrNull(16)
                            if (hex.length == 4 && cp != null) { sb.append(cp.toChar()); i += 4 }
                            else return out
                        }
                        else -> sb.append(n)   // \" and \\
                    }
                } else sb.append(c)
                i++
            }
            if (i >= s.length) return out   // unterminated string
            out.add(sb.toString())
            i++
        }
        return out
    }
}

/** SQLite-backed VerdictLog (platform API only). All SQL is parameterised. Call off the main thread. */
class SqliteVerdictLog(ctx: Context) : VerdictLog {
    private val helper = object : SQLiteOpenHelper(ctx.applicationContext, "verdicts.db", null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE verdicts(id INTEGER PRIMARY KEY AUTOINCREMENT, ts_ms INTEGER NOT NULL, " +
                "source TEXT NOT NULL, label TEXT NOT NULL, confidence REAL NOT NULL, scam_type TEXT, " +
                "triggers TEXT NOT NULL, engine TEXT NOT NULL)")
            db.execSQL("CREATE INDEX idx_verdicts_ts ON verdicts(ts_ms)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}
    }

    override fun append(e: VerdictEvent) {
        val cv = ContentValues()
        for ((k, v) in VerdictRowMapper.toRow(e)) when (v) {
            null -> cv.putNull(k)
            is Long -> cv.put(k, v)
            is Double -> cv.put(k, v)
            else -> cv.put(k, v.toString())
        }
        helper.writableDatabase.insert("verdicts", null, cv)
    }

    override fun since(tsMs: Long): List<VerdictEvent> = query("ts_ms >= ?", arrayOf(tsMs.toString()), "ts_ms ASC, id ASC", null)

    override fun latest(): VerdictEvent? = query(null, null, "ts_ms DESC, id DESC", "1").firstOrNull()

    override fun clear() { helper.writableDatabase.delete("verdicts", null, null) }

    override fun countsByType(): Map<ScamType, Int> {
        val out = LinkedHashMap<ScamType, Int>()
        helper.readableDatabase.query("verdicts", arrayOf("scam_type", "COUNT(*)"), "scam_type IS NOT NULL",
            null, "scam_type", null, null).use { c ->
            while (c.moveToNext()) {
                val t = ScamType.parse(c.getString(0)) ?: continue
                out[t] = (out[t] ?: 0) + c.getInt(1)
            }
        }
        return out
    }

    private fun query(where: String?, args: Array<String>?, order: String, limit: String?): List<VerdictEvent> {
        val out = ArrayList<VerdictEvent>()
        helper.readableDatabase.query("verdicts", null, where, args, null, null, order, limit).use { c ->
            while (c.moveToNext()) {
                val row = mapOf(
                    "id" to c.getLong(c.getColumnIndexOrThrow("id")),
                    "ts_ms" to c.getLong(c.getColumnIndexOrThrow("ts_ms")),
                    "source" to c.getString(c.getColumnIndexOrThrow("source")),
                    "label" to c.getString(c.getColumnIndexOrThrow("label")),
                    "confidence" to c.getDouble(c.getColumnIndexOrThrow("confidence")),
                    "scam_type" to c.getString(c.getColumnIndexOrThrow("scam_type")),
                    "triggers" to c.getString(c.getColumnIndexOrThrow("triggers")),
                    "engine" to c.getString(c.getColumnIndexOrThrow("engine")),
                )
                VerdictRowMapper.fromRow(row)?.let { out.add(it) }
            }
        }
        return out
    }
}
