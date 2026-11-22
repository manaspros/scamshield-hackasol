package com.hackasol.scamshield.core

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/** ZIP of card.json + events.json + manifest.json; the manifest lists the SHA-256 (hex) of the other two. */
object EvidenceZip {
    const val CARD = "card.json"
    const val EVENTS = "events.json"
    const val MANIFEST = "manifest.json"

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    fun eventsJson(events: List<VerdictEvent>): String = events.joinToString(",", "[", "]") { e ->
        "{\"id\":${e.id},\"ts_ms\":${e.tsMs},\"source\":${jsonQuote(e.source.name)},\"label\":${jsonQuote(e.label.name)}," +
            "\"confidence\":${e.confidence},\"scam_type\":${e.scamType?.let { jsonQuote(it.name) } ?: "null"}," +
            "\"triggers\":[${e.triggers.joinToString(",") { jsonQuote(it) }}],\"engine\":${jsonQuote(e.engine)}}"
    }

    fun build(card: CaseCard, events: List<VerdictEvent>): ByteArray {
        val files = linkedMapOf(
            CARD to card.toJson().toByteArray(Charsets.UTF_8),
            EVENTS to eventsJson(events).toByteArray(Charsets.UTF_8),
        )
        val manifest = files.entries.joinToString(",", "{\"sha256\":{", "}}") { "${jsonQuote(it.key)}:\"${sha256Hex(it.value)}\"" }
        files[MANIFEST] = manifest.toByteArray(Charsets.UTF_8)
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            for ((name, bytes) in files) {
                zip.putNextEntry(ZipEntry(name).apply { time = 0L }) // fixed time keeps the ZIP reproducible
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return out.toByteArray()
    }

    /** True only if manifest.json exists, lists exactly the other entries, and every hash recomputes. Corrupt ZIP -> false. */
    fun verify(zipBytes: ByteArray): Boolean = try {
        val entries = HashMap<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zin ->
            while (true) {
                val e = zin.nextEntry ?: break
                if (entries.put(e.name, zin.readBytes()) != null) return false // duplicate entry names
            }
        }
        val manifest = entries[MANIFEST]?.toString(Charsets.UTF_8)
        if (manifest == null) false else {
            val listed = Regex("\"([^\"]+)\":\"([0-9a-f]{64})\"").findAll(manifest).associate { it.groupValues[1] to it.groupValues[2] }
            val others = entries.keys - MANIFEST
            listed.isNotEmpty() && listed.keys == others && listed.all { (name, hash) -> sha256Hex(entries.getValue(name)) == hash }
        }
    } catch (e: java.io.IOException) {
        false
    }
}
