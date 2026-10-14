package io.github.bno3bno3.litechron.ecard

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ECardMethodHandlerTest {
    private class Reply : MethodChannel.Result {
        var completions = 0
        var error: String? = null
        var unknown = false
        override fun success(result: Any?) { completions++ }
        override fun error(code: String, message: String?, details: Any?) { completions++; error = code }
        override fun notImplemented() { completions++; unknown = true }
    }
    @Test fun allSupportedMethodsFinishOnce() = runTest {
        val handler = ECardMethodHandler(this) { _, result -> result.success(null) }
        for (method in listOf("update", "logout", "invalidateSession", "credentialsCommitted", "getBarcode")) {
            val reply = Reply()
            handler.onMethodCall(MethodCall(method, null), reply)
            runCurrent()
            assertEquals(1, reply.completions)
        }
        val unknown = Reply()
        handler.onMethodCall(MethodCall("unknown", null), unknown)
        assertTrue(unknown.unknown)
    }
    @Test fun failureAndLifecycleCancellationFinishOnce() = runTest {
        val error = Reply()
        ECardMethodHandler(this) { _, _ -> throw ECardException(Failure.BUSY) }
            .onMethodCall(MethodCall("getBarcode", null), error)
        runCurrent()
        assertEquals("busy", error.error)
        assertEquals(1, error.completions)
        val pending = Reply()
        val job = SupervisorJob()
        val scope = CoroutineScope(coroutineContext + job)
        ECardMethodHandler(scope) { _, _ -> awaitCancellation() }
            .onMethodCall(MethodCall("getBarcode", null), pending)
        job.cancel()
        runCurrent()
        assertEquals("cancelled", pending.error)
        assertEquals(1, pending.completions)
    }
}
