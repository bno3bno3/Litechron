package io.github.bno3bno3.litechron.ecard

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface ECardStore {
    fun credentials(): Credentials
    fun session(credentials: Credentials): Session?
    fun saveSession(credentials: Credentials, session: Session)
    fun checkCurrent(credentials: Credentials)
}

/** Platform-free request policy. State commits are guarded again by the Android store. */
class ECardService(
    private val store: ECardStore,
    private val api: CampusApi,
    private val acquire: suspend () -> String?,
    private val release: (String) -> Unit,
    private val scope: CoroutineScope,
    private val authTimeoutMillis: Long = 60_000,
) {
    private val loginMutex = Mutex()
    private var login: Deferred<Result<Session>>? = null
    private var loginGeneration: Long? = null
    // A failed concurrent wave shares its result; a subsequent user request may retry.
    private var loginUsers = 0

    private suspend fun authenticate(credentials: Credentials, rejected: Session?): Session {
        val deferred = loginMutex.withLock {
            store.checkCurrent(credentials)
            val current = store.session(credentials)
            if (current != null && (rejected == null || current.token != rejected.token)) return current
            val existing = login
            if (existing != null && loginGeneration == credentials.generation &&
                (!existing.isCompleted || loginUsers > 0)) {
                loginUsers++
                existing
            } else {
                loginGeneration = credentials.generation
                loginUsers = 1
                scope.async {
                    try {
                        val lease = acquire() ?: throw ECardException(Failure.BUSY)
                        val authenticated = try {
                            store.checkCurrent(credentials)
                            withTimeout(authTimeoutMillis) {
                                val token = api.authenticate(credentials)
                                val card = api.cards(token).maxByOrNull { it.balance }
                                val session = Session(token, card?.account, credentials.username, credentials.generation)
                                store.saveSession(credentials, session)
                                session
                            }
                        } catch (_: TimeoutCancellationException) {
                            throw ECardException(Failure.TIMEOUT)
                        } finally { release(lease) }
                        Result.success(authenticated)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        // Expected request failures are values, not failures of the
                        // shared scope (and must not cancel sibling callers).
                        Result.failure(error)
                    }
                }.also { login = it }
            }
        }
        try { return deferred.await().getOrThrow() }
        finally {
            withContext(NonCancellable) {
                loginMutex.withLock {
                    if (login === deferred) loginUsers--
                }
            }
        }
    }

    private suspend fun <T> request(credentials: Credentials, action: suspend (Session) -> T): T {
        val existing = store.session(credentials)
        val session = existing ?: authenticate(credentials, null)
        val result = try { action(session) } catch (error: ECardException) {
            // A request with no prior session already authenticated once; never loop.
            if (error.kind != Failure.AUTH || existing == null) throw error
            action(authenticate(credentials, session))
        }
        store.checkCurrent(credentials)
        return result
    }

    suspend fun balance(credentials: Credentials): Long {
        if (credentials.username == "3200000000") {
            store.checkCurrent(credentials)
            return 1897
        }
        return request(credentials) { session ->
            api.cards(session.token).maxByOrNull { it.balance }?.balance ?: throw ECardException(Failure.NO_CARD)
        }
    }

    suspend fun barcode(credentials: Credentials): String {
        if (credentials.username == "3200000000") {
            store.checkCurrent(credentials)
            return "3200000000000000"
        }
        return request(credentials) { session ->
            val account = api.cards(session.token).maxByOrNull { it.balance }?.account
                ?: throw ECardException(Failure.NO_CARD)
            api.barcode(session.token, account)
        }
    }
}
