package io.github.bno3bno3.litechron.ecard

import io.github.bno3bno3.litechron.auth.AcademicAuthGate
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AcademicAuthGateTest {
    @Test fun nativeAndFlutterParticipantsWaitForEachOther() = runTest {
        val academic = AcademicAuthGate.tryAcquire()!!
        try {
            val ecard = async { AcademicAuthGate.acquire(45_000) }
            runCurrent()
            assertFalse(ecard.isCompleted)
            AcademicAuthGate.release("wrong-owner")
            assertNull(AcademicAuthGate.tryAcquire())
            AcademicAuthGate.release(academic)
            val acquired = ecard.await()!!
            assertNull(AcademicAuthGate.tryAcquire())
            AcademicAuthGate.release(acquired)
        } finally { AcademicAuthGate.release(academic) }
    }
    @Test fun busyDeadlineDoesNotReleaseAnotherOwnersLease() = runTest {
        val academic = AcademicAuthGate.tryAcquire()!!
        try {
            assertNull(AcademicAuthGate.acquire(45_000))
            assertEquals(45_000, testScheduler.currentTime)
            assertNull(AcademicAuthGate.tryAcquire())
        } finally { AcademicAuthGate.release(academic) }
    }
}
