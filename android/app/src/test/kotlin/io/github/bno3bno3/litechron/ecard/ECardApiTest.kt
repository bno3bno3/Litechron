package io.github.bno3bno3.litechron.ecard

import kotlinx.coroutines.runBlocking
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class ECardApiTest {
    @Test fun responseClassification() = runBlocking {
        MockWebServer().use { server ->
            val api = ECardApi(campus = server.url("/").toString().trimEnd('/'))
            val cases = listOf(
                Triple(401, "not json", Failure.AUTH),
                Triple(200, """{"code":401}""", Failure.AUTH),
                Triple(429, "{}", Failure.RATE_LIMIT),
                Triple(500, """{"code":401}""", Failure.SERVER),
                Triple(200, "bad json", Failure.FORMAT),
                Triple(200, """{"data":{"card":[{"account":"a"}]}}""", Failure.FORMAT),
            )
            for ((status, body, expected) in cases) {
                server.enqueue(MockResponse().setResponseCode(status).setBody(body))
                try { api.cards("fixture"); fail("Expected $expected") }
                catch (e: ECardException) { assertEquals(expected, e.kind) }
            }
            server.enqueue(MockResponse().setBody("""{"data":{"card":[]}}"""))
            assertTrue(api.cards("fixture").isEmpty())
            server.enqueue(MockResponse().setBody("""{"data":{"card":[{"account":"a","db_balance":0},{"account":"b","db_balance":"12"}]}}"""))
            assertEquals(listOf(Card("a", 0), Card("b", 12)), api.cards("fixture"))
        }
    }
    @Test fun networkTimeout() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val client = OkHttpClient.Builder().callTimeout(100, TimeUnit.MILLISECONDS).build()
            val api = ECardApi(campus = server.url("/").toString().trimEnd('/'), client = client)
            try { api.cards("fixture"); fail("Expected timeout") }
            catch (e: ECardException) { assertEquals(Failure.TIMEOUT, e.kind) }
        }
    }
    @Test fun firstColdConnectionFailureRecoversWithinSameRefresh() = runBlocking {
        for (policy in listOf(SocketPolicy.DISCONNECT_AT_START, SocketPolicy.NO_RESPONSE)) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setSocketPolicy(policy))
                server.enqueue(MockResponse().setBody("""{"data":{"card":[{"account":"fixture","db_balance":17}]}}"""))
                val events = mutableListOf<ECardDiagnostic>()
                val client = OkHttpClient.Builder().callTimeout(300, TimeUnit.MILLISECONDS)
                    .retryOnConnectionFailure(false).build()
                val api = ECardApi(campus = server.url("/").toString().trimEnd('/'), client = client,
                    diagnostic = { events.add(it) })
                assertEquals(listOf(Card("fixture", 17)), api.cards("fixture-token"))
                assertEquals(2, server.requestCount)
                assertTrue(events.any { it.failure == Failure.NETWORK || it.failure == Failure.TIMEOUT })
                assertTrue(events.all { it.stage == RequestStage.CARDS })
            }
        }
    }
    @Test fun transportRecoveryStopsAfterOneRetry() = runBlocking {
        MockWebServer().use { server ->
            repeat(2) { server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START)) }
            server.enqueue(MockResponse().setBody("""{"data":{"card":[]}}"""))
            val client = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
            val api = ECardApi(campus = server.url("/").toString().trimEnd('/'), client = client)
            try { api.cards("fixture"); fail("Expected network error") }
            catch (e: ECardException) { assertEquals(Failure.NETWORK, e.kind) }
            assertEquals(2, server.requestCount)
        }
    }
    @Test fun neverReplaysHttpErrorsMalformedJsonOrBarcodeIssuance() = runBlocking {
        for ((status, body, failure) in listOf(
            Triple(401, "{}", Failure.AUTH), Triple(429, "{}", Failure.RATE_LIMIT),
            Triple(500, "{}", Failure.SERVER), Triple(200, "broken", Failure.FORMAT))) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setResponseCode(status).setBody(body))
                val api = ECardApi(campus = server.url("/").toString().trimEnd('/'))
                try { api.cards("fixture"); fail("Expected $failure") }
                catch (e: ECardException) { assertEquals(failure, e.kind) }
                assertEquals(1, server.requestCount)
            }
        }
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
            val client = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
            val api = ECardApi(campus = server.url("/").toString().trimEnd('/'), client = client)
            try { api.barcode("fixture", "card"); fail("Expected network error") }
            catch (e: ECardException) { assertEquals(Failure.NETWORK, e.kind) }
            assertEquals(1, server.requestCount)
        }
    }
    @Test fun cookiesRespectDomainPathAndSecure() {
        val jar = CampusCookies()
        val cas = "https://zjuam.zju.edu.cn/cas/login".toHttpUrl()
        jar.saveFromResponse(cas, listOf(Cookie.parse(cas, "session=fixture; Path=/cas; Secure")!!))
        assertEquals(1, jar.loadForRequest(cas).size)
        assertTrue(jar.loadForRequest("https://elife.zju.edu.cn/cas/login".toHttpUrl()).isEmpty())
        assertTrue(jar.loadForRequest("https://zjuam.zju.edu.cn/other".toHttpUrl()).isEmpty())
        assertTrue(jar.loadForRequest("http://zjuam.zju.edu.cn/cas/login".toHttpUrl()).isEmpty())
    }
    @Test fun casRsaAndRelativeOAuthRedirect() = runBlocking {
        assertEquals("ae6".padStart(128, '0'), ECardApi.encryptPassword("A", "ca1", "11"))
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("<input value='fixture-execution' name='execution'>"))
            server.enqueue(MockResponse().setBody("""{"modulus":"ca1","exponent":"11"}"""))
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Set-Cookie", "iPlanetDirectoryPro=fixture; Path=/"))
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "/next"))
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "/done?synjones-auth=fixture%2Btoken"))
            val base = server.url("/").toString().trimEnd('/')
            assertEquals("fixture+token", ECardApi(cas = base, campus = base).authenticate(Credentials("fixture", "A", 1)))
            assertEquals(5, server.requestCount)
        }
    }
}
