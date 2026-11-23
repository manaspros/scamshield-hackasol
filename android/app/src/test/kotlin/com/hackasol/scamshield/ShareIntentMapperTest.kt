package com.hackasol.scamshield

import com.hackasol.scamshield.core.ShareIntentMapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ShareIntentMapperTest {
    private val send = "android.intent.action.SEND"

    @Test fun T2_1_mapsTrimmedText() =
        assertEquals("share OTP now", ShareIntentMapper.map(send, "text/plain", "  share OTP now \n"))

    @Test fun T2_1_rejectsNonTextAndWrongAction() {
        assertNull(ShareIntentMapper.map(send, "image/png", "x"))
        assertNull(ShareIntentMapper.map("android.intent.action.VIEW", "text/plain", "x"))
        assertNull(ShareIntentMapper.map(null, null, "x"))
    }

    @Test fun T2_1_rejectsEmptyOrBlank() {
        assertNull(ShareIntentMapper.map(send, "text/plain", null))
        assertNull(ShareIntentMapper.map(send, "text/plain", "  \n\t"))
    }

    @Test fun T2_1_capsLength() =
        assertEquals(ShareIntentMapper.MAX_CHARS, ShareIntentMapper.map(send, "text/plain", "a".repeat(5000))!!.length)
}
