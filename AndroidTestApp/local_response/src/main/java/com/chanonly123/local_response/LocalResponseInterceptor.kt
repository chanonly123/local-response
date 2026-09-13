package com.chanonly123.local_response

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import java.util.UUID


class LocalResponseInterceptor internal constructor(
    private val config: LocalResponseConfig,
    private val serverClient: LocalServerClient
) : Interceptor {

    /// The constructor consumers use. The two-argument one exists so a test can
    /// hand in its own client, and is internal because [LocalServerClient] is.
    constructor(config: LocalResponseConfig) : this(config, LocalServerClient(config))

    private val coroutineScope = CoroutineScope(Dispatchers.IO)

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()

        if (shouldIgnore(request.url.toString())) {
            return chain.proceed(request)
        }

        val taskId = UUID.randomUUID().toString()

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

        var outgoing = request
        try {
            val map = MapCheckRequest(url = request.url.toString(), method = request.method)
            val result = serverClient.checkIfLocalMapResponseAvailable(data = map)
            if (result != null) {
                // Edits go on first: they describe the request as the app would
                // have sent it, and a mapped response then replaces that request
                // wholesale.
                if (result.changesRequest) {
                    // Kept separate from the override below: an edit that cannot
                    // be applied must not also cost the request its mapped
                    // response, which is the more visible half of a rule.
                    try {
                        outgoing = applyRequestChanges(result, outgoing)
                    } catch (e: Exception) {
                        if (config.isDebugEnabled) {
                            e.printStackTrace()
                        }
                    }

                    // Reported from the built request rather than from the rule,
                    // so the record shows exactly what goes on the wire.
                    val updateData = URLTaskModelUpdate.init(taskId = taskId, request = outgoing)
                    coroutineScope.launch {
                        try {
                            serverClient.sendToLocalServerData(obj = updateData)
                        } catch (e: Exception) {
                            if (config.isDebugEnabled) {
                                e.printStackTrace()
                            }
                        }
                    }
                }

                result.overrideId?.let { id ->
                    outgoing = serverClient.overriddenRequest(id, outgoing)
                    if (config.isDebugEnabled) {
                        println("LocalResponse: Mapped response $id for ${request.url}")
                    }
                }
            }
        } catch (e: Exception) {
            if (config.isDebugEnabled) {
                e.printStackTrace()
            }
        }

        try {
            val response = chain.proceed(outgoing)
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

    /**
     * Applies a `modifyRequest` rule to the request that is about to be sent.
     */
    private fun applyRequestChanges(changes: MapCheckResponse, request: Request): Request {
        val builder = request.newBuilder()

        // A rule sets parameters, it does not rewrite the query string: every
        // parameter the url already carries and no rule names is kept, in the
        // order it carries them.
        if (!changes.reqQuery.isNullOrEmpty()) {
            val url = request.url.newBuilder()
            changes.reqQuery.forEach { (key, value) -> url.setQueryParameter(key, value) }
            builder.url(url.build())
        }

        // `header` rather than `addHeader`: a rule declares what the header is,
        // not one more value for it.
        changes.reqHeaders?.forEach { (key, value) -> builder.header(key, value) }

        changes.reqBody?.let { body ->
            // OkHttp refuses a body on GET and HEAD — `Request.Builder.method`
            // throws rather than ignoring it — so the rest of the rule is
            // applied and the body dropped. URLSession has no such rule, so a
            // rule that sets a body on a GET behaves differently on iOS; there
            // is no way to send one here short of rewriting the method.
            if (!permitsRequestBody(request.method)) {
                if (config.isDebugEnabled) {
                    println(
                        "LocalResponse: rule sets a request body, but OkHttp does not " +
                            "allow one on ${request.method} — body ignored for ${request.url}"
                    )
                }
                return@let
            }
            // Content type stays as the app set it; the rule replaces what is
            // sent, not what it is. Content-Length is OkHttp's to fill in.
            builder.method(request.method, body.toRequestBody(request.body?.contentType()))
        }

        return builder.build()
    }

    /// The two methods OkHttp will not carry a body for. Mirrors its own
    /// internal `HttpMethod.permitsRequestBody`, which is not public API.
    private fun permitsRequestBody(method: String): Boolean =
        !(method.equals("GET", ignoreCase = true) || method.equals("HEAD", ignoreCase = true))

    /**
     * Anything the caller filtered out, plus the mapper itself: a request the
     * app aims at the local server is the mapper's own traffic, not the app's.
     */
    private fun shouldIgnore(url: String): Boolean {
        if (config.serverUrl.isNotEmpty() && url.startsWith(config.serverUrl)) {
            return true
        }
        if (config.excludeUrls.any { url.contains(it) }) {
            return true
        }
        return config.urlFilters.isNotEmpty() && config.urlFilters.none { url.contains(it) }
    }
}
