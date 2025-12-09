package com.chanonly123.local_response

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import java.util.UUID


class LocalResponseInterceptor(
    private val config: LocalResponseConfig,
    private val serverClient: LocalServerClient = LocalServerClient(config)
) : Interceptor {

    private val coroutineScope = CoroutineScope(Dispatchers.IO)

    override fun intercept(chain: Interceptor.Chain): Response {
        val taskId = UUID.randomUUID().toString()

        val request = chain.request()
        val currentUrl = request.url
        val newUrl = currentUrl.newBuilder().build()
        val currentRequest = request.newBuilder()
        val newRequest = currentRequest.url(newUrl)

        val beginData = URLTaskModelBegin.init(
            taskId = taskId,
            request = request,
        )

        coroutineScope.launch {
            try {
                serverClient.sendToLocalServerData(obj = beginData)
                if (config.isDebugEnabled) {
                    println("LocalResponse: Request logged")
                }
            } catch (e: Exception) {
                if (config.isDebugEnabled) {
                    e.printStackTrace()
                }
            }
        }

        try {
            val map = MapCheckRequest(url = request.url.toString(), method = request.method)
            val id: String? = serverClient.checkIfLocalMapResponseAvailable(data = map)
            if (id?.isNotEmpty() ?: false) {
                serverClient.updateRequest(id, newRequest)
            }
        } catch (e: Exception) {
            if (config.isDebugEnabled) {
                e.printStackTrace()
            }
        }

        try {
            val response = chain.proceed(newRequest.build())
            val bytes: ByteArray = response.body.bytes()

            val endData = URLTaskModelEnd.init(
                taskId = taskId,
                response = response,
                bytes = bytes,
                err = null,
            )
            coroutineScope.launch {
                try {
                    serverClient.sendToLocalServerData( obj =endData)
                    if (config.isDebugEnabled) {
                        println("LocalResponse: Response logged")
                    }
                } catch (e: Exception) {
                    if (config.isDebugEnabled) {
                        e.printStackTrace()
                    }
                }
            }
            val newBody = bytes.toResponseBody(contentType = response.body.contentType())
            return response.newBuilder().body(newBody).build()
        } catch (e: Exception) {
            if (config.isDebugEnabled) {
                println("LocalResponse: Error: $e")
            }
            coroutineScope.launch {
                try {
                    val endData = URLTaskModelEnd.init(
                        taskId = taskId,
                        response = null,
                        bytes = null,
                        err = e.toString(),
                    )
                    serverClient.sendToLocalServerData(endData)
                    if (config.isDebugEnabled) {
                        println("LocalResponse: Response logged")
                    }
                } catch (e: Exception) {
                    if (config.isDebugEnabled) {
                        e.printStackTrace()
                    }
                }
            }
            throw e
        }
    }
}