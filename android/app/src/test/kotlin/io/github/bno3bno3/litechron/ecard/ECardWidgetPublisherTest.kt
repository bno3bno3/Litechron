package io.github.bno3bno3.litechron.ecard

import android.app.Application
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Looper
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.work.*
import androidx.work.testing.WorkManagerTestInitHelper
import io.github.bno3bno3.litechron.ECardWidget
import io.github.bno3bno3.litechron.ECardWidgetReceiver
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class)
class ECardWidgetPublisherTest {
    @Before fun captureDiagnostics() {
        org.robolectric.shadows.ShadowLog.stream = System.out
    }

    @After fun closeGlanceStores() = runBlocking {
        // Robolectric creates a new Context per test, but Glance keeps process-wide
        // stores. Close them so no later test uses a deleted earlier fixture directory.
        val managerClass = GlanceAppWidgetManager::class.java
        val delegate = ReflectionHelpers.getStaticField<Any>(managerClass, "appManagerDataStore\$delegate")
        val scopes = listOfNotNull(
            ReflectionHelpers.getField<CoroutineScope>(delegate, "scope"),
            ReflectionHelpers.getStaticField<CoroutineScope?>(PreferencesGlanceStateDefinition::class.java, "coroutineScope"),
        )
        for (scope in scopes) {
            scope.coroutineContext[Job]?.children?.toList()?.forEach { it.cancelAndJoin() }
        }
        ReflectionHelpers.setField(delegate, "INSTANCE", null)
        ReflectionHelpers.setStaticField(managerClass, "dataStoreSingleton", null)
        ReflectionHelpers.getStaticField<MutableMap<String, *>>(
            Class.forName("androidx.glance.state.GlanceState"), "dataStores").clear()
    }
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val manager get() = GlanceAppWidgetManager(context)

    private fun bind(id: Int) {
        shadowOf(AppWidgetManager.getInstance(context)).addBoundWidget(id, AppWidgetProviderInfo().apply {
            provider = ComponentName(context, ECardWidgetReceiver::class.java)
        })
    }

    // Deliberately reproduce Glance 1.1.1's on-disk mapping from an older obfuscated APK.
    // Use its own DataStore instance to avoid opening two stores for the same file.
    private suspend fun seedOldMapping() {
        val store = ReflectionHelpers.callInstanceMethod<DataStore<Preferences>>(manager, "getOrCreateDataStore")
        val receiver = ECardWidgetReceiver::class.java.canonicalName!!
        store.edit {
            it[stringSetPreferencesKey("list::Providers")] = setOf(receiver)
            it[stringPreferencesKey("provider:$receiver")] = "old.release.a"
        }
        assertTrue(manager.getGlanceIds(ECardWidget::class.java).isEmpty())
    }

    private suspend fun state(id: Int) = getAppWidgetState(
        context, PreferencesGlanceStateDefinition, manager.getGlanceIdBy(id))

    // AndroidX DataStore 1.0 uses File.renameTo to replace the old file. Windows
    // cannot replace an existing target this way. Keep the loaded DataStore value
    // (including the old account/mapping), but remove its host file before rewriting.
    private fun prepareRewrite(file: File) {
        if (System.getProperty("os.name").startsWith("Windows")) {
            assertTrue("Expected existing fixture file", file.isFile)
            assertTrue("Remove Windows rename target", file.delete())
        }
    }

    @Test fun upgradePublishesToAllSystemInstancesDespiteOldMapping() = runBlocking {
        bind(101); bind(102)
        seedOldMapping()
        val rendered = mutableSetOf<Int>()
        ECardWidgetPublisher(context) { _, id -> rendered.add(manager.getAppWidgetId(id)); Unit }
            .publish(mapOf("status" to "success", "balance" to 1897L, "updated" to 123L))
        assertEquals(setOf(101, 102), rendered)
        for (id in rendered) {
            assertEquals(1897L, state(id)[ECardState.balance])
            assertEquals("success", state(id)[ECardState.status])
        }
    }

    @Test fun newlyAddedInstanceIsDiscoveredWithoutRepairingOldMapping() = runBlocking {
        seedOldMapping()
        val rendered = mutableSetOf<Int>()
        val publisher = ECardWidgetPublisher(context) { _, id -> rendered.add(manager.getAppWidgetId(id)); Unit }
        publisher.publish(mapOf("status" to "pending"))
        assertTrue(rendered.isEmpty())
        bind(201)
        publisher.publish(mapOf("status" to "loggedOut"))
        assertEquals(setOf(201), rendered)
        assertEquals("loggedOut", state(201)[ECardState.status])
    }

    @Test fun removedAndReaddedWidgetUsesNewSystemId() = runBlocking {
        bind(211)
        seedOldMapping()
        val rendered = mutableSetOf<Int>()
        val publisher = ECardWidgetPublisher(context) { _, id -> rendered.add(manager.getAppWidgetId(id)); Unit }
        publisher.publish(mapOf("status" to "pending"))
        // Robolectric 4.14 has no public remove-widget helper; remove only the host entry.
        ReflectionHelpers.getField<MutableMap<Int, *>>(
            shadowOf(AppWidgetManager.getInstance(context)), "widgetInfos").remove(211)
        bind(212)
        rendered.clear()
        publisher.publish(mapOf("status" to "failed", "failure" to "NETWORK", "balance" to 1897L))
        assertEquals(setOf(212), rendered)
        assertEquals(1897L, state(212)[ECardState.balance])
        assertEquals("NETWORK", state(212)[ECardState.failure])
    }

    @Test fun renderingFailureDoesNotAbortOtherInstancesOrRetainPreviousAccount() = runBlocking {
        bind(301); bind(302)
        ECardWidgetPublisher(context) { _, _ -> }.publish(mapOf("status" to "success", "balance" to 1897L))
        for (id in listOf(301, 302)) {
            assertEquals(1897L, state(id)[ECardState.balance])
            prepareRewrite(PreferencesGlanceStateDefinition.getLocation(context, "appWidget-$id"))
        }
        var attempts = 0
        ECardWidgetPublisher(context) { _, _ ->
            if (++attempts == 1) throw IllegalStateException("fixture")
        }.publish(mapOf("status" to "loggedOut"))
        assertEquals(2, attempts)
        for (id in listOf(301, 302)) {
            assertNull(state(id)[ECardState.balance])
            assertEquals("loggedOut", state(id)[ECardState.status])
        }
    }

    @Test fun cancellationStopsPublication() = runBlocking {
        bind(401); bind(402)
        var attempts = 0
        try {
            ECardWidgetPublisher(context) { _, _ ->
                attempts++
                throw CancellationException("fixture")
            }.publish(mapOf("status" to "pending"))
            fail("Cancellation must propagate")
        } catch (_: CancellationException) {
            assertEquals(1, attempts)
        }
    }

    @Test fun receiverRepairsOldMapping() = runBlocking {
        bind(501)
        seedOldMapping()
        prepareRewrite(context.preferencesDataStoreFile("GlanceAppWidgetManager"))
        // Exercise the real receiver/Glance lifecycle, without running auth or a UI session.
        WorkManagerTestInitHelper.initializeTestWorkManager(context, Configuration.Builder()
            .setWorkerFactory(object : WorkerFactory() {
                override fun createWorker(context: Context, name: String, params: WorkerParameters) =
                    object : Worker(context, params) {
                        override fun doWork() = Result.success()
                    }
            }).build())
        val receiver = ECardWidgetReceiver()
        context.registerReceiver(receiver, IntentFilter(AppWidgetManager.ACTION_APPWIDGET_UPDATE))
        try {
            context.sendBroadcast(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(501))
            })
            shadowOf(Looper.getMainLooper()).idle()
            withTimeout(5_000) {
                while (true) {
                    shadowOf(Looper.getMainLooper()).idle()
                    val sessions = WorkManager.getInstance(context)
                        .getWorkInfosForUniqueWork("appWidget-501").get()
                    if (sessions.isNotEmpty() && sessions.all { it.state.isFinished } &&
                        manager.getGlanceIds(ECardWidget::class.java).isNotEmpty()) break
                    delay(10)
                }
            }
            assertEquals(501, manager.getAppWidgetId(manager.getGlanceIds(ECardWidget::class.java).single()))
        } finally {
            context.unregisterReceiver(receiver)
            WorkManager.getInstance(context).cancelAllWork().result.get()
            WorkManagerTestInitHelper.closeWorkDatabase()
        }
    }
}
