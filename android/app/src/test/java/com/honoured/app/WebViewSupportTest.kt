package com.honoured.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WebViewSupportTest {
    @Test
    fun parsesTheMajorVersion() {
        assertEquals(124, WebViewSupport.parseMajor("124.0.6367.219"))
        assertEquals(58, WebViewSupport.parseMajor("58.0.3029.125"))
        assertEquals(136, WebViewSupport.parseMajor(" 136.0.7103.60 beta"))
        assertNull(WebViewSupport.parseMajor(null))
        assertNull(WebViewSupport.parseMajor(""))
        assertNull(WebViewSupport.parseMajor("dev-build"))
        assertNull(WebViewSupport.parseMajor("99999999999.1"))
    }

    @Test
    fun theWebAppsBuildTargetIsTheFloor() {
        assertFalse(WebViewSupport.isSupported(58))
        assertFalse(WebViewSupport.isSupported(110))
        assertTrue(WebViewSupport.isSupported(111))
        assertTrue(WebViewSupport.isSupported(124))
        // An unreadable version is not a reason to lock someone out.
        assertTrue(WebViewSupport.isSupported(null))
    }
}
