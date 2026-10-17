package io.github.bno3bno3.litechron.ecard

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import io.github.bno3bno3.litechron.ECardWidget
import io.github.bno3bno3.litechron.ECardWidgetReceiver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/** Uses Android's installed instances, never Glance's persisted provider class names. */
internal class ECardWidgetPublisher(
    private val context: Context,
    private val render: suspend (Context, GlanceId) -> Unit = { ctx, id -> ECardWidget().update(ctx, id) },
) {
    internal fun installedIds(): IntArray = AppWidgetManager.getInstance(context)
        .getAppWidgetIds(ComponentName(context, ECardWidgetReceiver::class.java))

    suspend fun publish(snapshot: Map<String, *>) {
        val ids = try {
            installedIds()
        } catch (_: Exception) {
            Log.w("LitechronECard", "stage=WIDGET_DISCOVERY failure=DISCOVERY")
            return
        }
        Log.i("LitechronECard", "stage=WIDGET_PUBLISH count=${ids.size}")
        for (appWidgetId in ids) {
            coroutineContext.ensureActive()
            try {
                val id = GlanceAppWidgetManager(context).getGlanceIdBy(appWidgetId)
                updateAppWidgetState(context, id) {
                    it.clear()
                    (snapshot["balance"] as? Long)?.let { value -> it[ECardState.balance] = value }
                    (snapshot["updated"] as? Long)?.let { value -> it[ECardState.updated] = value }
                    it[ECardState.status] = snapshot["status"] as? String ?: "pending"
                    (snapshot["failure"] as? String)?.let { value -> it[ECardState.failure] = value }
                }
                render(context, id)
                Log.i("LitechronECard", "stage=WIDGET_PUBLISH result=SUCCESS")
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                // A removed/broken instance must not abort balance fetching or other instances.
                Log.w("LitechronECard", "stage=WIDGET_PUBLISH failure=PUBLISH type=${error.javaClass.simpleName}")
            }
        }
    }
}
