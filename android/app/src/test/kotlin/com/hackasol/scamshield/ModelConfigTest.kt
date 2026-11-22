package com.hackasol.scamshield

import com.hackasol.scamshield.core.ModelConfig
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelConfigTest {
    @Test fun T1_15_urlFromConstant() {
        // const vals are inlined, so this reads ModelDownloader's effective values without loading Android classes
        assertEquals(ModelConfig.URL, ModelDownloader.DEFAULT_URL)
        assertEquals(ModelConfig.FILENAME, ModelDownloader.FILE_NAME)
        assertEquals("https://github.com/AB527/open-model/releases/download/v1/gemma3-1b-it-int4.task", ModelConfig.URL)
        assertEquals("gemma3-1b-it-int4.task", ModelConfig.FILENAME)
    }
}
