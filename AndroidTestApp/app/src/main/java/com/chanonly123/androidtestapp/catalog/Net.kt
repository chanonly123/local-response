package com.chanonly123.androidtestapp.catalog

import com.chanonly123.androidtestapp.NetworkModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/** Endpoints the samples call. Mirrors `Endpoints` in the iOS test app. */
object Endpoints {
    const val HTTPBIN = "https://httpbin.org"
    const val JSON_PLACEHOLDER = "https://jsonplaceholder.typicode.com"
    const val POSTMAN_ECHO = "https://postman-echo.com"
    const val WEB_SOCKET_ECHO = "wss://ws.postman-echo.com/raw"

    /// Static json files in matched sizes, pretty and minified — see the
    /// "Large payloads" group.
    const val JSON_DUMMY = "https://microsoftedge.github.io/Demos/json-dummy-data"
}

/**
 * Everything a sample call reports back to the UI. The mapper app is the real
 * output; this is only here so it is obvious the call actually left the device.
 */
data class CallOutcome(val ok: Boolean, val text: String) {
    companion object {
        fun success(text: String) = CallOutcome(true, text)
        fun failure(text: String) = CallOutcome(false, text)
    }
}

object Net {

    /// Every sample goes through the app's client, so every sample is seen by
    /// `LocalResponseInterceptor` — which is the entire point of this app.
    val client: OkHttpClient get() = NetworkModule.okHttpClient

    fun request(
        method: String,
        url: String,
        headers: Map<String, String> = emptyMap(),
        body: RequestBody? = null
    ): Request {
        val builder = Request.Builder().url(url)
        headers.forEach { (key, value) -> builder.header(key, value) }
        // OkHttp rejects a body on GET and demands one on POST, so only name the
        // method explicitly when there is something to say.
        builder.method(method, body)
        return builder.build()
    }

    /**
     * Runs [request] and summarises the reply.
     *
     * [timeoutSec] stands in for `URLRequest.timeoutInterval`: OkHttp keeps
     * timeouts on the client rather than the request, so a sample that wants a
     * different one gets a client sharing this one's connection pool.
     */
    suspend fun send(
        request: Request,
        client: OkHttpClient = this.client,
        note: String? = null,
        timeoutSec: Long? = null
    ): CallOutcome = withContext(Dispatchers.IO) {
        val effective = timeoutSec?.let {
            client.newBuilder().callTimeout(it, TimeUnit.SECONDS).build()
        } ?: client
        try {
            effective.newCall(request).execute().use { response ->
                summary(response, note)
            }
        } catch (e: Exception) {
            CallOutcome.failure(describe(e))
        }
    }

    /** The async path — OkHttp's answer to `dataTask(with:completionHandler:)`. */
    suspend fun enqueue(request: Request, note: String? = null): CallOutcome =
        suspendCoroutine { continuation ->
            client.newCall(request).enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resume(CallOutcome.failure(describe(e)))
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use { continuation.resume(summary(it, note)) }
                }
            })
        }

    /// Reads the body, so the caller must not have consumed it already.
    fun summary(response: Response, note: String? = null): CallOutcome {
        val bytes = try {
            response.body.bytes()
        } catch (e: Exception) {
            ByteArray(0)
        }
        val parts = mutableListOf("HTTP ${response.code}")
        response.body.contentType()?.let { parts.add("${it.type}/${it.subtype}") }
        parts.add(readableBytes(bytes.size.toLong()))
        note?.let { parts.add(it) }

        var line = parts.joinToString(" · ")
        val preview = String(bytes.take(160).toByteArray(), Charsets.UTF_8)
        if (preview.isNotEmpty()) {
            line += "\n" + preview.replace("\n", " ")
        }
        return CallOutcome.success(line)
    }

    fun describe(e: Throwable): String = "${e.javaClass.simpleName}: ${e.message ?: "no message"}"

    fun readableBytes(count: Long): String {
        if (count < 1024) return "$count bytes"
        val units = listOf("KB", "MB", "GB")
        var value = count.toDouble() / 1024
        var unit = 0
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit++
        }
        return String.format(Locale.US, "%.1f %s", value, units[unit])
    }

    fun json(build: JSONObject.() -> Unit): RequestBody =
        JSONObject().apply(build).toString().toRequestBody("application/json".toMediaType())

    fun jsonArray(items: List<Any>): JSONArray = JSONArray().apply { items.forEach { put(it) } }

    fun boundary(): String = "Boundary-${UUID.randomUUID()}"

    /**
     * Built by hand rather than with `MultipartBody` so the bytes match what the
     * iOS sample sends — the mapper shows the raw body, and the two apps should
     * look alike there.
     */
    fun multipartBody(
        boundary: String,
        fields: Map<String, String>,
        fileName: String,
        fileData: ByteArray
    ): ByteArray {
        val head = StringBuilder()
        fields.forEach { (key, value) ->
            head.append("--$boundary\r\n")
            head.append("Content-Disposition: form-data; name=\"$key\"\r\n\r\n")
            head.append("$value\r\n")
        }
        head.append("--$boundary\r\n")
        head.append("Content-Disposition: form-data; name=\"file\"; filename=\"$fileName\"\r\n")
        head.append("Content-Type: application/octet-stream\r\n\r\n")
        return head.toString().toByteArray(Charsets.UTF_8) +
            fileData +
            "\r\n--$boundary--\r\n".toByteArray(Charsets.UTF_8)
    }
}
