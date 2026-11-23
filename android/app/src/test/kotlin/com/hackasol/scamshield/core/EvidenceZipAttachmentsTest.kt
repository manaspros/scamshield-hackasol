package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class EvidenceZipAttachmentsTest {
    private val now = 1_700_000_000_000L
    private val card = CaseCard.fromLog(InMemoryVerdictLog(), startMs = now, nowMs = now)

    private fun entries(zip: ByteArray): Map<String, ByteArray> {
        val m = linkedMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(zip)).use { z -> while (true) { val e = z.nextEntry ?: break; m[e.name] = z.readBytes() } }
        return m
    }

    @Test fun attachmentsAreZippedAndHashed() {
        val shot = byteArrayOf(1, 2, 3, 4)
        val name = EvidenceZip.attachmentName(0, "Screenshot_2026-11-23.png")
        val zip = EvidenceZip.build(card, emptyList(), mapOf(name to shot))
        assertTrue(EvidenceZip.verify(zip))
        val e = entries(zip)
        assertEquals(setOf("card.json", "events.json", "manifest.json", "attachments/1-Screenshot_2026-11-23.png"), e.keys)
        assertTrue(String(e.getValue("manifest.json")).contains(EvidenceZip.sha256Hex(shot)))
    }

    @Test fun swappedAttachmentFailsVerify() {
        val name = EvidenceZip.attachmentName(0, "a.png")
        val e = entries(EvidenceZip.build(card, emptyList(), mapOf(name to byteArrayOf(9))))
        e as MutableMap
        e[name] = byteArrayOf(8)
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z -> e.forEach { (n, b) -> z.putNextEntry(ZipEntry(n)); z.write(b); z.closeEntry() } }
        assertFalse(EvidenceZip.verify(out.toByteArray()))
    }

    @Test fun namesAreFlatAsciiAndUnique() {
        assertEquals("attachments/2-evil.png", EvidenceZip.attachmentName(1, "../../evil.png"))
        assertTrue(Regex("""attachments/1-_+\.jpg""").matches(EvidenceZip.attachmentName(0, "फ़ोटो.jpg")))
        assertEquals("attachments/3-file", EvidenceZip.attachmentName(2, "///"))
        assertThrows(IllegalArgumentException::class.java) {
            EvidenceZip.build(card, emptyList(), mapOf("../x" to byteArrayOf(1)))
        }
    }
}
