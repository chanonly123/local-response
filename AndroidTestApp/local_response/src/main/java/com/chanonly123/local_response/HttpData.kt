package com.chanonly123.local_response

import okhttp3.Response
import android.util.Base64
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.ResponseBody
import okio.Buffer
import java.util.UUID

data class URLTaskModelBegin(
    val taskId: String,
    val url: String,
    val method: String,
    val reqHeaders: Map<String, String>,
    val body: String?,
    val bundleID: String?,
    val startTime: Double?
) {
    companion object {

        fun init(
            taskId: String,
            request: Request
        ): URLTaskModelBegin {
            return URLTaskModelBegin(
                taskId = taskId,
                url = request.url.toString(),
                method = request.method,
                reqHeaders = request.headers.toMap(),
                body = request.body?.let { readRequestBody(it) },
                bundleID = URLTaskModelEnd.getBundleId(),
                startTime = System.currentTimeMillis() / 1000.0
            )
        }
        fun readRequestBody(requestBody: RequestBody): String? {
            return try {
                val buffer = Buffer()
                requestBody.writeTo(buffer)
                buffer.readUtf8()
            } catch (e: Exception) {
                null
            }
        }
    }
}

data class URLTaskModelEnd(
    val taskId: String,
    val resString: String?,
    val resStringB64: String?,
    val resHeaders: Map<String, String>?,
    val statusCode: Int?,
    val error: String?,
    val bundleID: String?,
    val mimeType: String?,
    val endTime: Double?
) {

    companion object {

        fun init(
            taskId: String,
            response: Response?,
            bytes: ByteArray?,
            err: String?
        ) : URLTaskModelEnd {
            val mimeType = response?.body?.contentType()?.toString()?.split(";")?.first() ?: ""
            val isString = mimeType.contains("json") || mimeType.contains("text")
            return URLTaskModelEnd(
                taskId = taskId,
                resString = if (isString) bytes?.toString(Charsets.UTF_8) else null,
                resStringB64 = if (!isString) Base64.encodeToString(bytes, Base64.DEFAULT) else null,
                resHeaders = response?.headers?.toMap(),
                statusCode = response?.code,
                error = err,
                bundleID = getBundleId(),
                mimeType = response?.body?.contentType()?.toString()?.split(";")?.first(),
                endTime = System.currentTimeMillis() / 1000.0
            )
        }

        fun getBundleId(): String? {
            // In Android, you can get the package name (like bundle ID)
            return try {
//                val context = MyApp.context  // replace with your Application context reference
//                context.packageName
                "package_name"
            } catch (e: Exception) {
                null
            }
        }
    }
}


data class MapCheckRequest(
    val url: String,
    val method: String,
)
