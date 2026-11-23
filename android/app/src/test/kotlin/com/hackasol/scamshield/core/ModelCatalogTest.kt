package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCatalogTest {
    @Test fun defaultIsTheHostedOneB() {
        val d = ModelCatalog.byId(ModelCatalog.DEFAULT_ID)!!
        assertEquals(ModelConfig.FILENAME, d.file)
        assertEquals(ModelConfig.URL, d.url)
    }

    @Test fun recommendsLargestHostedThatFits() {
        // 3n-E2B is not hosted yet, so every phone that can run the 1B gets it.
        assertEquals(ModelCatalog.DEFAULT_ID, ModelCatalog.recommend(12_000, 50_000).id)
        assertEquals(ModelCatalog.DEFAULT_ID, ModelCatalog.recommend(6_000, 20_000).id)
    }

    @Test fun lowRamPhoneGetsThe270M() {
        assertEquals("gemma3-270m", ModelCatalog.recommend(3_500, 20_000).id)
    }

    @Test fun fallsBackToSmallestHostedWhenNothingFits() {
        assertEquals(ModelCatalog.all.first { it.url != null }.id, ModelCatalog.recommend(2_000, 100).id)
    }

    @Test fun unknownRamDoesNotHideTheDefault() {
        assertEquals(ModelCatalog.DEFAULT_ID, ModelCatalog.recommend(0, 0).id)
    }

    @Test fun scamShieldLlmIsListedAndHostedButNotTheDefault() {
        val s = ModelCatalog.byId(ModelCatalog.SCAMSHIELD_LLM_ID)!!
        assertEquals("scamshield-llm-v1.task", s.file)
        assertTrue(s.url!!.contains("/ScamShieldLLM-v1/"))
        assertEquals(s, ModelCatalog.byFile("scamshield-llm-v1.task"))
        // Listed before the 1B, so a phone that fits both is still recommended Gemma 3 1B.
        assertTrue(ModelCatalog.all.indexOf(s) < ModelCatalog.all.indexOfFirst { it.id == ModelCatalog.DEFAULT_ID })
        assertEquals(ModelCatalog.DEFAULT_ID, ModelCatalog.recommend(8_000, 20_000).id)
    }

    @Test fun fitsChecksRamAndStorage() {
        val oneB = ModelCatalog.byId(ModelCatalog.DEFAULT_ID)!!
        assertTrue(ModelCatalog.fits(oneB, 4_000, 800))
        assertFalse(ModelCatalog.fits(oneB, 3_000, 800))
        assertFalse(ModelCatalog.fits(oneB, 8_000, 600))
    }
}
