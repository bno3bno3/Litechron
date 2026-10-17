package io.github.bno3bno3.litechron

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.appwidget.AppWidgetManager
import android.util.Log
import androidx.datastore.preferences.core.Preferences
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.clickable
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.*
import androidx.glance.preview.ExperimentalGlancePreviewApi
import androidx.glance.preview.Preview
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import kotlinx.coroutines.*
import io.github.bno3bno3.litechron.ecard.ECardRuntime
import io.github.bno3bno3.litechron.ecard.ECardState
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class ECardWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ECardWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        Log.i("LitechronECard", "stage=WIDGET_INIT count=${appWidgetIds.size}")
        try {
            // Only enqueue here: no credentials, network, or waiting on WorkManager.
            ECardRuntime.enqueueFromReceiver(context)
        } catch (_: Exception) {
            Log.w("LitechronECard", "stage=WIDGET_ENQUEUE failure=ENQUEUE")
        } finally {
            // Glance owns goAsync(), repairs its receiver mapping, and renders the
            // supplied IDs even when an older release persisted a different class name.
            super.onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }
}

class RefreshECardAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        withContext(Dispatchers.IO) { ECardRuntime.get(context).enqueue() }
    }
}

class ECardWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {

        provideContent {
            GlanceTheme {
                val state = currentState<Preferences>()
                val status = state[ECardState.status] ?: "pending"
                val updated = state[ECardState.updated]?.let {
                    Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("HH:mm"))
                }
                val message = when (status) {
                    "refreshing" -> "刷新中"
                    "loggedOut" -> "请先登录"
                    "failed" -> "刷新失败" + (updated?.let { " · $it" } ?: "")
                    "success" -> "更新时间：${updated.orEmpty()}"
                    else -> "待刷新"
                }
                val empty = when {
                    status == "loggedOut" -> "请先登录"
                    state[ECardState.failure] == "NO_CARD" -> "未找到校园卡"
                    state[ECardState.failure] == "AUTH" -> "认证失败"
                    state[ECardState.failure] == "FORMAT" -> "响应异常"
                    else -> "待刷新"
                }
                content(context, id, state[ECardState.balance], message, empty)
            }
        }
    }

    @Composable
    private fun content(context: Context?, id: GlanceId?, balance: Long?, message: String = "待刷新", empty: String = "待刷新") {
        Column(
            modifier = GlanceModifier.background(GlanceTheme.colors.background).fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp).cornerRadius(16.dp).clickable(actionRunCallback<RefreshECardAction>()),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                Image(
                    provider = ImageProvider(
                        resId = R.drawable.credit_card_24px
                    ),
                    contentDescription = "Credit Card Icon",
                    modifier = GlanceModifier.size(20.dp),
                    colorFilter = ColorFilter.tint(GlanceTheme.colors.onBackground)
                )
                Spacer(modifier = GlanceModifier.width(4.dp))
                Text(
                    text = "校园卡余额", maxLines = 1, style = TextStyle(
                        color = GlanceTheme.colors.onBackground,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Image(
                    provider = ImageProvider(
                        resId = R.drawable.sync_24px
                    ),
                    contentDescription = "Sync Icon",
                    modifier = GlanceModifier.size(20.dp).clickable(actionRunCallback<RefreshECardAction>()),
                    colorFilter = ColorFilter.tint(GlanceTheme.colors.onBackground)
                )
            }

            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Column {
                    Text(
                        text = balance?.let(::formatBalance) ?: empty,
                        maxLines = 1,
                        style = TextStyle(
                            color = GlanceTheme.colors.primary,
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.SansSerif
                        )
                    )
                    Text(
                        text = message,
                        maxLines = 1,
                        style = TextStyle(
                            color = GlanceTheme.colors.onBackground,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    )

                }
                Spacer(modifier = GlanceModifier.defaultWeight())
                Column(horizontalAlignment = Alignment.End) {
                    Image(
                        provider = ImageProvider(
                            resId = R.drawable.qr_code_24px
                        ),
                        contentDescription = "QR Code Icon",
                        modifier = GlanceModifier.size(32.dp).clickable {
                            context?.let {
                                val scheme = it.getString(R.string.app_link_scheme)
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("$scheme://ecardpaypage"))
                                intent.setPackage(it.packageName)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                it.startActivity(intent)
                            }
                        },
                        colorFilter = ColorFilter.tint(GlanceTheme.colors.primary)
                    )
                }
            }
        }
    }

    // If debugging the AppWidget, you can use the following preview
    // composable to see how the AppWidget will look like.
    @OptIn(ExperimentalGlancePreviewApi::class)
    @Preview(widthDp = 180, heightDp = 102)
    @Composable
    fun preview() {
        content(null, null, 1897)
    }

    private fun formatBalance(balance: Long): String {
        // Variable balance is 100 times larger than the actual value
        // For example, if the actual balance is ¥18.97, then variable balance is 18.97 * 100 = 1897
        // If variable balance is less than 10000, display it directly. For example, 1897 -> ¥ 18.97
        // If variable balance is greater than 10000, clip to 4 significant figures. For example, 18973 -> ¥ 189.7
        return if (balance < 0) {
            "待刷新"
        } else if (balance < 10000) {
            // Remember to pad zero before the decimal point
            "¥ ${balance / 100}.${balance % 100 / 10}${balance % 10}"
        } else {
            // Clip to 4 significant figures
            "¥ ${balance / 100}.${balance % 100 / 10}"
        }
    }

}
