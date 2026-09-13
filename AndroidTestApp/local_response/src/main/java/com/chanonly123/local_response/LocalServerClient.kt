package com.chanonly123.local_response

import com.google.gson.Gson
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Headers
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class LocalServerClient(private val config: LocalResponseConfig) {

    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(config.timeoutMs, TimeUnit.MILLISECONDS)
            .writeTimeout(config.timeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(config.timeoutMs, TimeUnit.MILLISECONDS)
            .build()
    }

    /// The rule lookup blocks the app's request and the mapper deliberately
    /// holds the answer for its configured delay, so it cannot share the record
    /// calls' short timeout. Connection pool and dispatcher are shared with
    /// `httpClient`; only the timeouts differ.
    private val mapCheckClient: OkHttpClient by lazy {
        httpClient.newBuilder()
            .connectTimeout(config.mapCheckTimeoutMs, TimeUnit.MILLISECONDS)
            .writeTimeout(config.mapCheckTimeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(config.mapCheckTimeoutMs, TimeUnit.MILLISECONDS)
            .build()
    }

    private val gson = Gson()

    fun sendToLocalServerData(obj: URLTaskModelBegin) {
        sendHttpData(config.endpointRecordBeginUrl, obj)
    }

    fun sendToLocalServerData(obj: URLTaskModelUpdate) {
        sendHttpData(config.endpointRecordUpdateUrl, obj)
    }

    fun sendToLocalServerData(obj: URLTaskModelEnd) {
        sendHttpData(config.endpointRecordEndUrl, obj)
    }

    /**
     * Asks the mapper what applies to this request: request edits, a canned
     * response, or both. `null` means no rule matched — the mapper answers
     * `204 No Content`, so an empty body is the ordinary case, not a failure.
     */
    fun checkIfLocalMapResponseAvailable(data: MapCheckRequest): MapCheckResponse? {
        val json = sendHttpData(config.endpointCheckMapResponse, data, mapCheckClient)
        if (json.isNullOrBlank()) {
            return null
        }
        return try {
            gson.fromJson(json, MapCheckResponse::class.java)?.takeIf { !it.isEmpty }
        } catch (e: Exception) {
            if (config.isDebugEnabled) {
                e.printStackTrace()
            }
            null
        }
    }

    /**
     * Points the request at the mapper's canned response for [id].
     *
     * The method and body are carried over from the request the app built: the
     * mapper answers every method on this path and ignores the body, while
     * OkHttp refuses a POST with no body and a GET with one. Headers are
     * dropped — the app's `Authorization` or `Content-Type` mean nothing to a
     * response that is already decided.
     */
    fun overriddenRequest(id: String, request: Request): Request {
        val url = (config.serverUrl + config.endpointOverriddenRequest).toHttpUrlOrNull()
            ?: return request
        return request.newBuilder()
            .url(url.newBuilder().setQueryParameter("id", id).build())
            .method(request.method, request.body)
            .headers(Headers.headersOf())
            .build()
    }

    private fun sendHttpData(
        endpoint: String,
        obj: Any,
        client: OkHttpClient = httpClient
    ): String? {
        try {

            val json: String = gson.toJson(obj)
            val requestBody = json.toRequestBody("application/json".toMediaType())

            val comps = endpoint.split(" ")
            val method = comps.first()
            val url = config.serverUrl + comps.last()

            val request = Request.Builder()
                .url(url)
                .method(method, requestBody)
                .addHeader("Content-Type", "application/json")
                .build()

            // `use` rather than a close on one branch: the body has to be
            // released whatever the status, or the connection is held until the
            // pool evicts it.
            client.newCall(request).execute().use { response ->
                if (config.isDebugEnabled) {
                    println("LocalResponse: Sent data to server, response: ${response.code}")
                }

                if (response.isSuccessful) {
                    return response.body.string()
                }
            }
        } catch (e: Exception) {
            if (config.isDebugEnabled) {
                e.printStackTrace()
            }
        }

        return null
    }
}
