package com.chanonly123.local_response

import com.chanonly123.local_response.LocalResponseConfig
import com.google.gson.Gson
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
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

    private val gson = Gson()

    fun sendToLocalServerData(obj: URLTaskModelBegin) {
        sendHttpData(config.endpointRecordBeginUrl, obj)
    }

    fun sendToLocalServerData(obj: URLTaskModelEnd) {
        sendHttpData(config.endpointRecordEndUrl, obj)
    }

    fun checkIfLocalMapResponseAvailable(data: MapCheckRequest): String? {
        val id = sendHttpData(config.endpointCheckMapResponse, data)
        return id
    }

    fun updateRequest(id: String, request: Request.Builder) {
        val comps = config.endpointOverriddenRequest.split(" ")
        val method = comps.first()
        val url = config.serverUrl + comps.last() + "?id=$id"
        request.url(url)
        request.method(method, body = null)
        request.headers(Headers.EMPTY)
    }

    private fun sendHttpData(endpoint: String, obj: Any): String? {
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

            val response = httpClient.newCall(request).execute()

            if (config.isDebugEnabled) {
                println("LocalResponse: Sent data to server, response: ${response.code}")
            }

            if (response.isSuccessful) {
                return response.body.string()
            }

            response.close()
        } catch (e: Exception) {
            if (config.isDebugEnabled) {
                e.printStackTrace()
            }
        }

        return null;
    }
}