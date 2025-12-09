package com.chanonly123.local_response

/**
 * Emulator:
 */
data class LocalResponseConfig(
    val serverUrl: String = "",
    val isDebugEnabled: Boolean = false,
    val timeoutMs: Long = 5000,
    val urlFilters: List<String> = emptyList(), // URLs to include (if empty, includes all)
    val excludeUrls: List<String> = emptyList(), // URLs to exclude

    val endpointRecordBeginUrl: String = "POST /record-begin",
    val endpointRecordEndUrl: String = "POST /record-end",
    val endpointCheckMapResponse: String = "POST /check-map-response",
    val endpointOverriddenRequest: String = "GET /overriden-request"
) {
    companion object {

        fun localIpAddress(url: String, isDebugEnabled: Boolean = false): LocalResponseConfig {
            return LocalResponseConfig(
                serverUrl = url,
                isDebugEnabled = isDebugEnabled,
            )
        }

        fun emulator(isDebugEnabled: Boolean = false): LocalResponseConfig {
            return LocalResponseConfig(
                serverUrl = "http://10.0.2.2:4040",
                isDebugEnabled = isDebugEnabled,
            )
        }

        fun genymotion(isDebugEnabled: Boolean = false): LocalResponseConfig {
            return LocalResponseConfig(
                serverUrl = "http://192.168.56.1:4040",
                isDebugEnabled = isDebugEnabled,
            )
        }
    }
}