package io.github.bno3bno3.litechron.ecard

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ECardServiceTest {
    private class Store : ECardStore {
        var current = Credentials("fixture", "fake", 1)
        var saved: Session? = Session("valid", "card", "fixture", 1)
        override fun credentials() = current
        override fun checkCurrent(credentials: Credentials) {
            if (current.generation != credentials.generation || current.username != credentials.username)
                throw ECardException(Failure.STALE)
        }
        override fun session(credentials: Credentials): Session? { checkCurrent(credentials); return saved }
        override fun saveSession(credentials: Credentials, session: Session) { checkCurrent(credentials); saved = session }
    }
    private class Api : CampusApi {
        var logins = 0
        var queries = 0
        var barcodeAccount: String? = null
        var authenticate: suspend () -> String = { "renewed" }
        var fetch: suspend (String) -> List<Card> = { listOf(Card("card", 0)) }
        override suspend fun authenticate(credentials: Credentials): String { logins++; return authenticate() }
        override suspend fun cards(token: String): List<Card> { queries++; return fetch(token) }
        override suspend fun barcode(token: String, account: String): String { barcodeAccount = account; return "fixture-code" }
    }
    private suspend fun failure(expected: Failure, action: suspend () -> Unit) {
        try { action(); fail("Expected $expected") } catch (e: ECardException) { assertEquals(expected, e.kind) }
    }

    @Test fun validTokenAndZeroBalance() = runTest {
        val store = Store(); val api = Api()
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        assertEquals(0L, service.balance(store.current))
        assertEquals(0, api.logins)
        service.balance(store.current)
        assertEquals(2, api.queries) // Every idle refresh issues a real request.
    }
    @Test fun expiredTokenAuthenticatesOnceAndRetries() = runTest {
        val store = Store(); val api = Api()
        api.fetch = { if (it == "valid") throw ECardException(Failure.AUTH) else listOf(Card("card", 23)) }
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        assertEquals(23L, service.balance(store.current))
        assertEquals(1, api.logins)
        assertEquals("renewed", store.saved?.token)
    }
    @Test fun retry401NeverLoops() = runTest {
        val store = Store(); val api = Api()
        api.fetch = {
            if (api.queries != 2) throw ECardException(Failure.AUTH)
            listOf(Card("card", 23)) // Validation succeeds, retry fails.
        }
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        failure(Failure.AUTH) { service.balance(store.current) }
        assertEquals(1, api.logins)
        assertEquals(3, api.queries)
    }
    @Test fun nonAuthErrorsNeverLogin() = runTest {
        for (kind in listOf(Failure.TIMEOUT, Failure.NETWORK, Failure.SERVER, Failure.RATE_LIMIT, Failure.FORMAT)) {
            val store = Store(); val api = Api()
            api.fetch = { throw ECardException(kind) }
            val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
            failure(kind) { service.balance(store.current) }
            assertEquals(0, api.logins)
            assertEquals("valid", store.saved?.token)
        }
    }
    @Test fun noCardAndMultiCardSelection() = runTest {
        val store = Store(); val api = Api()
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        api.fetch = { emptyList() }
        failure(Failure.NO_CARD) { service.balance(store.current) }
        assertEquals(0, api.logins)
        api.fetch = { listOf(Card("low", 2), Card("high", 99)) }
        assertEquals(99L, service.balance(store.current))
        service.barcode(store.current)
        assertEquals("high", api.barcodeAccount)
    }
    @Test fun concurrentBalanceAndBarcodeShareLogin() = runTest {
        val store = Store(); val api = Api()
        val ready = CompletableDeferred<Unit>()
        api.authenticate = { ready.await(); "renewed" }
        api.fetch = { if (it == "valid") throw ECardException(Failure.AUTH) else listOf(Card("card", 0)) }
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        val balance = async { service.balance(store.current) }
        val barcode = async { service.barcode(store.current) }
        runCurrent()
        assertEquals(1, api.logins)
        ready.complete(Unit)
        assertEquals(0L, balance.await())
        assertEquals("fixture-code", barcode.await())
        assertEquals(1, api.logins)
    }
    @Test fun concurrentFailureKeepsOldSession() = runTest {
        val store = Store(); val api = Api()
        api.fetch = { throw ECardException(Failure.AUTH) }
        api.authenticate = { delay(100); throw ECardException(Failure.NETWORK) }
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        val requests = List(2) { async { failure(Failure.NETWORK) { service.balance(store.current) } } }
        requests.awaitAll()
        assertEquals(1, api.logins)
        assertEquals("valid", store.saved?.token)
    }
    @Test fun waitsForAcademicGateAndRespectsBusy() = runTest {
        val store = Store().also { it.saved = null }; val api = Api()
        val gate = CompletableDeferred<String?>()
        val service = ECardService(store, api, { gate.await() }, {}, backgroundScope)
        val request = async { failure(Failure.BUSY) { service.balance(store.current) } }
        runCurrent()
        assertEquals(0, api.logins)
        gate.complete(null)
        request.await()
    }
    @Test fun authenticationDeadlineReleasesGate() = runTest {
        val store = Store().also { it.saved = null }; val api = Api()
        var released = false
        api.authenticate = { delay(61_000); "too-late" }
        val service = ECardService(store, api, { "lease" }, { released = true }, backgroundScope)
        failure(Failure.TIMEOUT) { service.balance(store.current) }
        assertTrue(released)
        assertNull(store.saved)
    }
    @Test fun accountSwitchDiscardsLateSessionAndBalance() = runTest {
        val store = Store(); val api = Api()
        api.fetch = {
            store.current = Credentials("other-fixture", "fake", 2)
            listOf(Card("card", 99))
        }
        val service = ECardService(store, api, { "lease" }, {}, backgroundScope)
        failure(Failure.STALE) { service.balance(store.current) }
        store.saved = null
        val old = store.current
        api.fetch = { listOf(Card("card", 99)) }
        api.authenticate = { store.current = Credentials("third-fixture", "fake", 3); "late" }
        failure(Failure.STALE) { service.balance(old) }
        assertNull(store.saved)
    }
    @Test fun demoNeverCallsCampus() = runTest {
        val store = Store().also { it.current = Credentials("3200000000", "demo", 1) }; val api = Api()
        val service = ECardService(store, api, { error("must not acquire") }, {}, backgroundScope)
        assertEquals(1897L, service.balance(store.current))
        assertEquals("3200000000000000", service.barcode(store.current))
        assertEquals(0, api.queries)
        assertEquals(0, api.logins)
    }
}
