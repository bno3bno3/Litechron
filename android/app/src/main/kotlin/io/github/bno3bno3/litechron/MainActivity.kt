package io.github.bno3bno3.litechron

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.github.bno3bno3.litechron.ecard.*
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val channelScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var ecardChannel: MethodChannel? = null
    private var upcomingChannel: MethodChannel? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = 0
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        upcomingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.bno3bno3.litechron/upcomingWidget")
        upcomingChannel!!.setMethodCallHandler { call, result ->
            channelScope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        when (call.method) {
                            "publishSnapshot" -> io.github.bno3bno3.litechron.upcoming.UpcomingRuntime.publish(applicationContext, call.arguments as String)
                            "invalidateSnapshot" -> io.github.bno3bno3.litechron.upcoming.UpcomingRuntime.invalidate(applicationContext, (call.arguments as Number).toLong())
                            else -> throw IllegalArgumentException("Unsupported method")
                        }
                    }
                    result.success(null)
                } catch (_: Exception) { result.error("UPCOMING_UPDATE", "无法更新本地安排", null) }
            }
        }
        ecardChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.bno3bno3.litechron/ecardWidget")
        ecardChannel!!.setMethodCallHandler(ECardMethodHandler(channelScope) { method, result ->
            val runtime = withContext(Dispatchers.IO) { ECardRuntime.get(applicationContext) }
            if (method == "getBarcode") {
                val (credentials, barcode) = withContext(Dispatchers.IO) {
                    val credentials = runtime.credentials()
                    credentials to runtime.service.barcode(credentials)
                }
                runtime.deliver(credentials) { result.success(barcode) }
            } else {
                val response = withContext(Dispatchers.IO) {
                    when (method) {
                        "update" -> { runtime.publish(); runtime.enqueue() }
                        "logout" -> { runtime.invalidate(logout = true); null }
                        "invalidateSession" -> { runtime.invalidate(); null }
                        "credentialsCommitted" -> { runtime.credentialsCommitted(); null }
                        else -> null
                    }
                }
                result.success(response)
            }
        })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        upcomingChannel?.setMethodCallHandler(null)
        ecardChannel?.setMethodCallHandler(null)
        channelScope.cancel()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
