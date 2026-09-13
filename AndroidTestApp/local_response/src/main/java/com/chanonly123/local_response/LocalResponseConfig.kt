package com.chanonly123.local_response

/**
 * Emulator:
 */
data class LocalResponseConfig(
    val serverUrl: String = "",
    val isDebugEnabled: Boolean = false,
    val timeoutMs: Long = 5000,
    /// Rule lookup gets its own budget: it has to outlast the longest delay the
    /// mapper may hold a request for (10s), unlike the fire-and-forget record
    /// calls. With the shorter timeout the lookup times out before the mapper
    /// answers, and every held request goes out unmapped.
    val mapCheckTimeoutMs: Long = 20000,
    val urlFilters: List<String> = emptyList(), // URLs to include (if empty, includes all)
    val excludeUrls: List<String> = emptyList(), // URLs to exclude

    val endpointRecordBeginUrl: String = "POST /record-begin",
    val endpointRecordUpdateUrl: String = "POST /record-update",
    val endpointRecordEndUrl: String = "POST /record-end",
    val endpointCheckMapResponse: String = "POST /check-map-response",
    /// Path only, no method: the mapped response is fetched with whatever
    /// method the app's own request used, so the route has to answer all of
    /// them.
    val endpointOverriddenRequest: String = "/overriden-request"
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
