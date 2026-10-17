package io.github.bno3bno3.litechron.upcoming

import android.app.Application
import androidx.work.Configuration
import androidx.work.testing.WorkManagerTestInitHelper
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class)
class UpcomingRuntimeTest {
    @Test fun switchRejectsLateOldAccountAndInvalidDataPreservesValidCache() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        WorkManagerTestInitHelper.initializeTestWorkManager(context, Configuration.Builder().build())
        val first = """{"version":1,"generation":1,"from":0,"until":1000,"items":[]}"""
        val second = first.replace("\"generation\":1", "\"generation\":2")
        UpcomingRuntime.invalidate(context, 1)
        UpcomingRuntime.publish(context, first)
        assertEquals(first, UpcomingRuntime.raw(context))
        UpcomingRuntime.invalidate(context, 2)
        assertNull(UpcomingRuntime.raw(context))
        assertTrue(runCatching { UpcomingRuntime.publish(context, first) }.isFailure)
        assertNull(UpcomingRuntime.raw(context))
        UpcomingRuntime.publish(context, second)
        UpcomingRuntime.invalidate(context, 1)
        assertEquals(second, UpcomingRuntime.raw(context))
        assertTrue(runCatching { UpcomingRuntime.publish(context, "{}") }.isFailure)
        assertEquals(second, UpcomingRuntime.raw(context))
    }
}
