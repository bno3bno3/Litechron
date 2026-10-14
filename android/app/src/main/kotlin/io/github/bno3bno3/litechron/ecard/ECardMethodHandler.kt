package io.github.bno3bno3.litechron.ecard

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/** The activity supplies lifecycle-bound operations; every recognized call completes. */
class ECardMethodHandler(
    private val scope: CoroutineScope,
    private val execute: suspend (String, MethodChannel.Result) -> Unit,
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("update", "logout", "invalidateSession", "credentialsCommitted", "getBarcode")) {
            result.notImplemented()
            return
        }
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                execute(call.method, result)
            } catch (_: CancellationException) {
                result.error("cancelled", "请求已取消", null)
            } catch (error: Exception) {
                val kind = (error as? ECardException)?.kind ?: Failure.STORAGE
                val message = when (kind) {
                    Failure.BUSY -> "请稍后重试"
                    Failure.LOGGED_OUT -> "请先登录"
                    Failure.NO_CARD -> "未找到校园卡"
                    Failure.AUTH -> "认证失败，请检查账号密码后重试"
                    Failure.FORMAT -> "校园卡响应格式异常"
                    Failure.STALE -> "账号已切换，请重新打开付款码"
                    else -> "刷新失败，请重试"
                }
                result.error(kind.name.lowercase(), message, null)
            }
        }
    }
}
