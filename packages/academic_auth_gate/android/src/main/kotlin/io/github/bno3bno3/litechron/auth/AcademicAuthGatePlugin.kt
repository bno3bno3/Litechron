package io.github.bno3bno3.litechron.auth

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.UUID

/** All participants run in the default app process, including background Flutter engines.
 * A lease is released on engine detach or in finally; process death clears the gate.
 * Unlike timestamp flags, admission is atomic and never expires during a live request. */
object AcademicAuthGate {
    private var owner: String? = null
    @Synchronized fun tryAcquire(): String? {
        if (owner != null) return null
        return UUID.randomUUID().toString().also { owner = it }
    }
    @Synchronized fun release(token: String) {
        if (owner == token) owner = null
    }
    suspend fun acquire(timeoutMillis: Long = 45_000): String? {
        var token: String? = null
        try {
            val result = withTimeoutOrNull(timeoutMillis) {
                token = tryAcquire()
                while (token == null) {
                    delay(100)
                    token = tryAcquire()
                }
                token
            }
            if (result == null) token?.let(::release)
            return result
        } catch (error: CancellationException) {
            token?.let(::release)
            throw error
        }
    }
}

class AcademicAuthGatePlugin : FlutterPlugin {
    private lateinit var channel: MethodChannel
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val leases = mutableSetOf<String>()
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        channel = MethodChannel(binding.binaryMessenger, "io.github.bno3bno3.litechron/authGate")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> scope.launch {
                    try {
                        val token = AcademicAuthGate.acquire()
                        if (token == null) result.error("busy", "请稍后重试", null)
                        else {
                            leases.add(token)
                            result.success(token)
                        }
                    } catch (_: CancellationException) {
                        result.error("cancelled", "请求已取消", null)
                    }
                }
                "release" -> {
                    val token = call.arguments as? String
                    if (token != null && leases.remove(token)) AcademicAuthGate.release(token)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        leases.forEach(AcademicAuthGate::release)
        leases.clear()
    }
}
