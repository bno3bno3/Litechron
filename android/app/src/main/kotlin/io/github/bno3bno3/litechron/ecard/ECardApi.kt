package io.github.bno3bno3.litechron.ecard

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.delay
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.io.IOException
import java.math.BigInteger
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

enum class Failure { AUTH, NETWORK, TIMEOUT, RATE_LIMIT, SERVER, FORMAT, NO_CARD, BUSY, LOGGED_OUT, STALE, STORAGE }
class ECardException(val kind: Failure) : Exception(kind.name)
enum class RequestStage { CAS_PAGE, CAS_KEY, CAS_LOGIN, OAUTH, CARDS, BARCODE }
data class ECardDiagnostic(val stage: RequestStage, val http: Int? = null,
                           val business: Int? = null, val failure: Failure? = null)
class Credentials(val username: String, val password: String, val generation: Long)
class Session(val token: String, val account: String?, val owner: String, val generation: Long)
data class Card(val account: String, val balance: Long)

interface CampusApi {
    suspend fun authenticate(credentials: Credentials): String
    suspend fun cards(token: String): List<Card>
    suspend fun barcode(token: String, account: String): String
}

/** A separate cookie jar per login attempt; cookies are never copied between hosts. */
internal class CampusCookies : CookieJar {
    private val cookies = mutableListOf<Cookie>()
    @Synchronized override fun saveFromResponse(url: HttpUrl, incoming: List<Cookie>) {
        incoming.forEach { cookie ->
            cookies.removeAll { it.name == cookie.name && it.domain == cookie.domain && it.path == cookie.path }
            if (cookie.expiresAt > System.currentTimeMillis()) cookies.add(cookie)
        }
    }
    @Synchronized override fun loadForRequest(url: HttpUrl): List<Cookie> {
        cookies.removeAll { it.expiresAt <= System.currentTimeMillis() }
        return cookies.filter { it.matches(url) }
    }
    @Synchronized fun hasSso() = cookies.any { it.name == "iPlanetDirectoryPro" }
}

class ECardApi(
    private val cas: String = "https://zjuam.zju.edu.cn",
    private val campus: String = "https://elife.zju.edu.cn",
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS).readTimeout(8, TimeUnit.SECONDS)
        .writeTimeout(8, TimeUnit.SECONDS).callTimeout(8, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build(),
    private val diagnostic: (ECardDiagnostic) -> Unit = {},
) : CampusApi {
    private data class Reply(val status: Int, val body: String, val location: String?, val stage: RequestStage)

    private suspend fun request(client: OkHttpClient, request: Request, stage: RequestStage): Reply =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    val kind = if (e is SocketTimeoutException || e is java.io.InterruptedIOException) Failure.TIMEOUT else Failure.NETWORK
                    if (continuation.isActive) {
                        diagnostic(ECardDiagnostic(stage, failure = kind))
                        continuation.resumeWithException(ECardException(kind))
                    }
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        response.use {
                            diagnostic(ECardDiagnostic(stage, http = it.code))
                            val reply = Reply(it.code, it.body?.string().orEmpty(), it.header("Location"), stage)
                            if (continuation.isActive) continuation.resume(reply)
                        }
                    } catch (error: IOException) {
                        val kind = if (error is java.io.InterruptedIOException) Failure.TIMEOUT else Failure.NETWORK
                        if (continuation.isActive) {
                            diagnostic(ECardDiagnostic(stage, failure = kind))
                            continuation.resumeWithException(ECardException(kind))
                        }
                    }
                }
            })
        }

    private fun request(url: String) = Request.Builder().url(url).header(
        "User-Agent", "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)")

    private fun checkHttp(reply: Reply) {
        when {
            reply.status == 401 -> throw ECardException(Failure.AUTH)
            reply.status == 429 -> throw ECardException(Failure.RATE_LIMIT)
            reply.status !in 200..299 -> throw ECardException(Failure.SERVER)
        }
    }

    private fun json(reply: Reply): JsonObject {
        checkHttp(reply)
        val root = try { Json.parseToJsonElement(reply.body).jsonObject }
            catch (_: Exception) { throw ECardException(Failure.FORMAT) }
        val rawCode = root["code"]
        if (rawCode != null) {
            val code = (rawCode as? JsonPrimitive)?.intOrNull ?: throw ECardException(Failure.FORMAT)
            diagnostic(ECardDiagnostic(reply.stage, http = reply.status, business = code))
            when (code) {
                401 -> throw ECardException(Failure.AUTH)
                429 -> throw ECardException(Failure.RATE_LIMIT)
                0, 200 -> Unit
                else -> throw ECardException(Failure.SERVER)
            }
        }
        return root
    }

    override suspend fun authenticate(credentials: Credentials): String {
        val jar = CampusCookies()
        val authClient = client.newBuilder().cookieJar(jar).build()
        val page = request(authClient, request("$cas/cas/login").build(), RequestStage.CAS_PAGE)
        checkHttp(page)
        val input = Regex("<input\\b[^>]*\\bname=[\"']execution[\"'][^>]*>", RegexOption.IGNORE_CASE)
            .find(page.body)?.value ?: throw ECardException(Failure.FORMAT)
        val execution = Regex("\\bvalue=[\"']([^\"']*)[\"']").find(input)?.groupValues?.get(1)
            ?: throw ECardException(Failure.FORMAT)
        val key = json(request(authClient, request("$cas/cas/v2/getPubKey").build(), RequestStage.CAS_KEY))
        val encrypted = try {
            encryptPassword(credentials.password, key["modulus"]!!.jsonPrimitive.content, key["exponent"]!!.jsonPrimitive.content)
        } catch (_: Exception) { throw ECardException(Failure.FORMAT) }
        val form = FormBody.Builder().add("username", credentials.username).add("password", encrypted)
            .add("execution", execution).add("_eventId", "submit").add("rememberMe", "true").build()
        val login = request(authClient, request("$cas/cas/login").post(form).build(), RequestStage.CAS_LOGIN)
        if (login.status !in 200..399) checkHttp(login)
        if (!jar.hasSso()) throw ECardException(Failure.AUTH)
        var url = "$campus/berserker-auth/cas/oauth2".toHttpUrl().newBuilder()
            .addQueryParameter("resultUrl", "$campus/plat-pc").build()
        repeat(10) {
            val response = request(authClient, request(url.toString()).build(), RequestStage.OAUTH)
            if (response.status !in listOf(301, 302, 303, 307, 308)) {
                checkHttp(response)
                throw ECardException(Failure.AUTH)
            }
            val target = response.location?.let(url::resolve) ?: throw ECardException(Failure.FORMAT)
            // Production authentication must not follow a downgrade or leave university hosts.
            if (campus.startsWith("https://") &&
                (!target.isHttps || !target.host.endsWith(".zju.edu.cn"))) throw ECardException(Failure.AUTH)
            target.queryParameter("synjones-auth")?.takeIf { it.isNotBlank() }?.let { return it }
            url = target
        }
        throw ECardException(Failure.AUTH)
    }

    private suspend fun data(path: String, token: String, stage: RequestStage): JsonObject {
        val query = request("$campus$path").header("Synjones-Auth", "Bearer $token").build()
        val reply = try {
            request(client, query, stage)
        } catch (error: ECardException) {
            // Only this read-only endpoint may be replayed after transport failure.
            // Never replay CAS login, ticket exchange or barcode issuance here.
            if (stage != RequestStage.CARDS || error.kind !in listOf(Failure.NETWORK, Failure.TIMEOUT)) throw error
            delay(400)
            val pool = ConnectionPool()
            val fresh = client.newBuilder().connectionPool(pool).retryOnConnectionFailure(false).build()
            try { request(fresh, query, stage) }
            finally { pool.evictAll() }
        }
        return json(reply)["data"] as? JsonObject ?: throw ECardException(Failure.FORMAT)
    }
    override suspend fun cards(token: String): List<Card> {
        val cards = data("/berserker-app/ykt/tsm/getCampusCards", token, RequestStage.CARDS)["card"] as? JsonArray
            ?: throw ECardException(Failure.FORMAT)
        return cards.map {
            val item = it as? JsonObject ?: throw ECardException(Failure.FORMAT)
            val account = (item["account"] as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
                ?: throw ECardException(Failure.FORMAT)
            val balance = (item["db_balance"] as? JsonPrimitive)?.longOrNull
                ?: throw ECardException(Failure.FORMAT)
            Card(account, balance)
        }
    }
    override suspend fun barcode(token: String, account: String): String {
        val path = "/berserker-app/ykt/tsm/batchGetBarCodeGet"
        val url = "$campus$path".toHttpUrl().newBuilder().addQueryParameter("account", account)
            .addQueryParameter("payacc", "###").addQueryParameter("paytype", "1")
            .addQueryParameter("synAccessSource", "app").build()
        val values = data(url.encodedPath + "?" + url.encodedQuery, token, RequestStage.BARCODE)["barcode"] as? JsonArray
            ?: throw ECardException(Failure.FORMAT)
        return (values.firstOrNull() as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
            ?: throw ECardException(Failure.FORMAT)
    }
    companion object {
        /** CAS uses unsigned UTF-8 modular exponentiation, not PKCS#1 padding. */
        internal fun encryptPassword(password: String, modulus: String, exponent: String): String =
            BigInteger(1, password.toByteArray(Charsets.UTF_8)).modPow(BigInteger(exponent, 16), BigInteger(modulus, 16))
                .toString(16).padStart(128, '0')
    }
}
