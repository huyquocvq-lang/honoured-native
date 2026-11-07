package com.honoured.app.deeplink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ContractDeepLinkTest {
    private fun parse(raw: String?) = ContractDeepLink.parse(raw)

    @Test
    fun parsesIdAndDay() {
        val t = parse("honoured://contract/7f0c2a1e-1b2c-4d5e-8f90-123456789abc?day=2026-11-05")
        assertEquals("7f0c2a1e-1b2c-4d5e-8f90-123456789abc", t?.contractId)
        assertEquals("2026-11-05", t?.healthDay)
    }

    @Test
    fun dayIsOptional() {
        val t = parse("honoured://contract/abc")
        assertEquals("abc", t?.contractId)
        assertNull(t?.healthDay)
    }

    @Test
    fun acceptsTheIosLinkWithAnOccurrenceToken() {
        val t = parse("honoured://contract/abc?day=2026-11-05&occurrence=0E3A4B1C-2D3E-4F50-8A9B-0C1D2E3F4A5B")
        assertEquals("abc", t?.contractId)
        assertEquals("2026-11-05", t?.healthDay)
    }

    @Test
    fun schemeAndHostAreCaseInsensitive() {
        assertEquals("abc", parse("HONOURED://Contract/abc")?.contractId)
    }

    @Test
    fun decodesThePercentEncodedId() {
        assertEquals("a b/c+d", parse("honoured://contract/a%20b%2Fc+d")?.contractId)
        assertEquals("café", parse("honoured://contract/caf%C3%A9")?.contractId)
    }

    @Test
    fun rejectsOtherSchemesHostsAndShapes() {
        listOf(
            null,
            "",
            "https://contract/abc",
            "honoured://motion-probe",
            "honoured://contract",
            "honoured://contract/",
            "honoured://contract/a/b",
            "honoured://user@contract/abc",
            "honoured://contract:80/abc",
            "honoured://contract/abc#frag",
            "honoured:contract/abc",
            "honoured://contract/abc def",
        ).forEach { assertNull(it, parse(it)) }
    }

    @Test
    fun rejectsBadIds() {
        assertNull(parse("honoured://contract/%20%20"))
        assertNull(parse("honoured://contract/a%0Ab"))
        assertNull(parse("honoured://contract/%E2%28%A1")) // invalid UTF-8
        assertNull(parse("honoured://contract/%zz"))
        assertNull(parse("honoured://contract/abc%2"))
        assertNull(parse("honoured://contract/" + "x".repeat(ContractDeepLink.MAX_ID_LENGTH + 1)))
        assertEquals(
            ContractDeepLink.MAX_ID_LENGTH,
            parse("honoured://contract/" + "x".repeat(ContractDeepLink.MAX_ID_LENGTH))?.contractId?.length,
        )
    }

    @Test
    fun rejectsBadQueries() {
        listOf(
            "honoured://contract/abc?",
            "honoured://contract/abc?day",
            "honoured://contract/abc?day=",
            "honoured://contract/abc?day=2026-02-30",
            "honoured://contract/abc?day=2026-2-3",
            "honoured://contract/abc?day=2026-11-05&day=2026-11-06",
            "honoured://contract/abc?day=2026-11-05&token=x",
            "honoured://contract/abc?occurrence=not-a-uuid",
            "honoured://contract/abc?access_token=x",
        ).forEach { assertNull(it, parse(it)) }
    }

    @Test
    fun healthDayIsARealDate() {
        assertTrue(ContractDeepLink.isValidHealthDay("2028-02-29"))
        assertFalse(ContractDeepLink.isValidHealthDay("2026-02-29"))
        assertFalse(ContractDeepLink.isValidHealthDay("2026-13-01"))
        assertFalse(ContractDeepLink.isValidHealthDay("２０２６-11-05"))
    }

    @Test
    fun eventPayloadCarriesOnlyNavigationFields() {
        val p = ContractDeepLink.eventPayload(ContractDeepLink.Target("abc", "2026-11-05"), "e-1")
        assertEquals(setOf("eventId", "contractId", "healthDay"), p.keys().asSequence().toSet())
        assertEquals("e-1", p.getString("eventId"))
        val noDay = ContractDeepLink.eventPayload(ContractDeepLink.Target("abc", null), "e-2")
        assertEquals(setOf("eventId", "contractId"), noDay.keys().asSequence().toSet())
    }
}
