package io.github.bno3bno3.litechron.ecard

import android.content.Context
import android.util.Log
import androidx.datastore.preferences.core.*
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.appwidget.updateAll
import androidx.work.*
import com.it_nomads.fluttersecurestorage.FlutterSecureStorage
import io.github.bno3bno3.litechron.ECardWidget
import io.github.bno3bno3.litechron.auth.AcademicAuthGate
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.util.concurrent.TimeUnit

object ECardState {
    val balance = longPreferencesKey("balance")
    val updated = longPreferencesKey("updated")
    val status = stringPreferencesKey("status")
    val failure = stringPreferencesKey("failure")
}

/** One instance in the default Android process. No Activity or Flutter engine is required. */
class ECardRuntime private constructor(private val context: Context) : ECardStore {
    private val storage = FlutterSecureStorage(context, HashMap())
    private val prefs = context.getSharedPreferences("ecard_state", Context.MODE_PRIVATE)
    private val guard = Any()
    private val publication = Mutex()
    private var changing = false
    private val authScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val service = ECardService(this, ECardApi(diagnostic = {
        // Only enums and numeric status codes; never URLs, exception text or bodies.
        Log.i("LitechronECard", "stage=${it.stage} http=${it.http} business=${it.business} failure=${it.failure}")
    }), { AcademicAuthGate.acquire() }, AcademicAuthGate::release, authScope)

    init {
        // A process killed during a request cannot leave a permanent spinner.
        if (prefs.getString("status", null) == "refreshing") {
            prefs.edit().putString("status", "failed").putString("failure", "NETWORK").commit()
        }
    }

    private fun read(key: String) = storage.read(storage.addPrefixToKey(key))
    private fun write(key: String, value: String) = storage.write(storage.addPrefixToKey(key), value)
    private fun delete(key: String) = storage.delete(storage.addPrefixToKey(key))
    private fun generation() = prefs.getLong("generation", 0)

    override fun credentials(): Credentials = synchronized(guard) {
        if (changing) throw ECardException(Failure.BUSY)
        // accountList is a single encrypted value and the account-switch commit point.
        // Legacy fields are used only before account-list migration.
        val raw = read("accountList")
        val username: String?
        val password: String?
        if (raw != null) {
            val accounts = try { Json.parseToJsonElement(raw).jsonArray }
                catch (_: Exception) { throw ECardException(Failure.STORAGE) }
            val first = accounts.firstOrNull() as? JsonObject
            username = (first?.get("username") as? JsonPrimitive)?.contentOrNull
            password = (first?.get("password") as? JsonPrimitive)?.contentOrNull
        } else {
            username = read("username")
            password = read("password")
        }
        if (username.isNullOrEmpty() || password.isNullOrEmpty()) throw ECardException(Failure.LOGGED_OUT)
        Credentials(username, password, generation())
    }

    override fun checkCurrent(credentials: Credentials) = synchronized(guard) {
        val now = credentials()
        if (now.generation != credentials.generation || now.username != credentials.username ||
            now.password != credentials.password) throw ECardException(Failure.STALE)
    }

    override fun session(credentials: Credentials): Session? = synchronized(guard) {
        checkCurrent(credentials)
        val raw = read("ecardSession") ?: return null // Unowned legacy tokens are never adopted.
        try {
            val json = Json.parseToJsonElement(raw).jsonObject
            if (json["owner"]!!.jsonPrimitive.content != credentials.username ||
                json["generation"]!!.jsonPrimitive.long != credentials.generation) return null
            Session(json["token"]!!.jsonPrimitive.content,
                json["account"]?.jsonPrimitive?.contentOrNull, credentials.username, credentials.generation)
        } catch (_: Exception) { null }
    }

    override fun saveSession(credentials: Credentials, session: Session) = synchronized(guard) {
        checkCurrent(credentials)
        write("ecardSession", buildJsonObject {
            put("owner", credentials.username)
            put("generation", credentials.generation)
            put("token", session.token)
            session.account?.let { put("account", it) }
        }.toString())
    }

    suspend fun invalidate(logout: Boolean = false) = publication.withLock {
        synchronized(guard) {
            changing = !logout
            val next = generation() + 1
            prefs.edit().clear().putLong("generation", next)
                .putString("status", if (logout) "loggedOut" else "pending").commit()
            delete("ecardSession")
            delete("synjonesAuth")
            delete("eCardAccount")
            authScope.coroutineContext.cancelChildren()
        }
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME).result.get()
        publishLocked()
    }

    suspend fun credentialsCommitted() = publication.withLock {
        synchronized(guard) {
            if (!changing) return@withLock
            changing = false
            val loggedIn = try { credentials(); true } catch (_: ECardException) { false }
            prefs.edit().putString("status", if (loggedIn) "pending" else "loggedOut").commit()
        }
        publishLocked()
    }

    suspend fun enqueue(): Boolean = publication.withLock {
        val epoch = synchronized(guard) {
            if (changing) return@withLock false
            generation()
        }
        val work = OneTimeWorkRequestBuilder<ECardBalanceWorker>()
            .setInputData(workDataOf("generation" to epoch))
            .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.SECONDS).build()
        // KEEP merges clicks while queued, running, or backing off. The next idle click
        // always creates a fresh request. No cache-age shortcut is used.
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, work).result.get()
        true
    }

    suspend fun state(credentials: Credentials?, status: String, balance: Long? = null, failure: Failure? = null,
                      expectedGeneration: Long? = null) = publication.withLock {
        synchronized(guard) {
            if (expectedGeneration != null && expectedGeneration != generation()) throw ECardException(Failure.STALE)
            if (credentials != null) checkCurrent(credentials)
            if (changing) throw ECardException(Failure.STALE)
            val edit = prefs.edit().putString("status", status)
            if (balance != null) edit.putLong("balance", balance).putLong("updated", System.currentTimeMillis())
            if (failure == null) edit.remove("failure") else edit.putString("failure", failure.name)
            edit.commit()
        }
        publishLocked()
    }

    suspend fun publish() = publication.withLock { publishLocked() }

    private suspend fun publishLocked() {
        val snapshot = synchronized(guard) { prefs.all.toMap() }
        val ids = GlanceAppWidgetManager(context).getGlanceIds(ECardWidget::class.java)
        ids.forEach { id ->
            updateAppWidgetState(context, id) {
                it.clear()
                (snapshot["balance"] as? Long)?.let { value -> it[ECardState.balance] = value }
                (snapshot["updated"] as? Long)?.let { value -> it[ECardState.updated] = value }
                it[ECardState.status] = snapshot["status"] as? String ?: "pending"
                (snapshot["failure"] as? String)?.let { value -> it[ECardState.failure] = value }
            }
        }
        ECardWidget().updateAll(context)
    }

    /** Keep channel delivery in the same critical section as account invalidation. */
    fun deliver(credentials: Credentials, action: () -> Unit) = synchronized(guard) {
        checkCurrent(credentials)
        action()
    }

    companion object {
        const val WORK_NAME = "litechron.ecard.balance"
        @Volatile private var instance: ECardRuntime? = null
        fun get(context: Context): ECardRuntime = instance ?: synchronized(this) {
            instance ?: ECardRuntime(context.applicationContext).also { instance = it }
        }
    }
}

class ECardBalanceWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val runtime = ECardRuntime.get(applicationContext)
        val epoch = inputData.getLong("generation", -1)
        var credentials: Credentials? = null
        try {
            credentials = runtime.credentials()
            if (credentials.generation != epoch) return@withContext Result.success()
            runtime.state(credentials, "refreshing")
            val balance = runtime.service.balance(credentials)
            ensureActive()
            runtime.state(credentials, "success", balance)
            Result.success()
        } catch (error: CancellationException) {
            withContext(NonCancellable) {
                try { runtime.state(credentials, "failed", failure = Failure.NETWORK, expectedGeneration = epoch) }
                catch (_: Exception) { /* An account change already cleared this generation. */ }
            }
            throw error
        } catch (error: Exception) {
            val kind = (error as? ECardException)?.kind ?: Failure.STORAGE
            Log.i("LitechronECard", "stage=BALANCE failure=$kind")
            if (kind == Failure.STALE) return@withContext Result.success()
            try {
                runtime.state(credentials, if (kind == Failure.LOGGED_OUT) "loggedOut" else "failed",
                    failure = kind, expectedGeneration = epoch)
            } catch (_: Exception) { return@withContext Result.success() }
            // Three total attempts, at least 30 seconds between busy retries.
            if (kind == Failure.BUSY && runAttemptCount < 2) Result.retry() else Result.failure()
        }
    }
}
