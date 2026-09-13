package com.chanonly123.androidtestapp.catalog

import com.chanonly123.androidtestapp.NetworkModule
import com.chanonly123.androidtestapp.Post
import com.chanonly123.androidtestapp.PostRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.CookieJar
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

class ApiSample(
    val title: String,
    val subtitle: String,
    val run: suspend () -> CallOutcome
)

class ApiGroup(val name: String, val samples: List<ApiSample>)

/**
 * The Android half of the iOS test app's catalogue — same groups, same
 * endpoints, so a call recorded from either platform looks alike in the mapper.
 *
 * Where a sample exercises something specific to `URLSession`, the equivalent
 * OkHttp mechanism is used instead: the "Session styles" group is the clearest
 * case, swapping delegates and session configurations for OkHttp's synchronous
 * and enqueued calls.
 */
object ApiCatalog {

    val groups: List<ApiGroup> by lazy {
        listOf(
            httpMethods,
            statusCodes,
            headersAndCookies,
            contentTypes,
            largePayloads,
            requestBodies,
            uploads,
            downloadsAndStreaming,
            media,
            failures,
            authentication,
            clientStyles,
            concurrency,
            retrofit
        )
    }

    // MARK: HTTP methods

    private val httpMethods = ApiGroup(
        "HTTP methods",
        listOf(
            ApiSample("GET", "${Endpoints.JSON_PLACEHOLDER}/todos/1?hello=world") {
                Net.send(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/todos/1?hello=world"))
            },
            ApiSample("POST (JSON)", "${Endpoints.JSON_PLACEHOLDER}/posts") {
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.JSON_PLACEHOLDER}/posts",
                        headers = mapOf("Content-Type" to "application/json"),
                        body = Net.json {
                            put("title", "Local Response")
                            put("body", "hello")
                            put("userId", 1)
                        }
                    )
                )
            },
            ApiSample("PUT", "${Endpoints.JSON_PLACEHOLDER}/posts/1") {
                Net.send(
                    Net.request(
                        "PUT", "${Endpoints.JSON_PLACEHOLDER}/posts/1",
                        headers = mapOf("Content-Type" to "application/json"),
                        body = Net.json {
                            put("id", 1)
                            put("title", "replaced")
                            put("body", "full update")
                            put("userId", 1)
                        }
                    )
                )
            },
            ApiSample("PATCH", "${Endpoints.JSON_PLACEHOLDER}/posts/1") {
                Net.send(
                    Net.request(
                        "PATCH", "${Endpoints.JSON_PLACEHOLDER}/posts/1",
                        headers = mapOf("Content-Type" to "application/json"),
                        body = Net.json { put("title", "patched") }
                    )
                )
            },
            ApiSample("DELETE", "${Endpoints.JSON_PLACEHOLDER}/posts/1") {
                Net.send(Net.request("DELETE", "${Endpoints.JSON_PLACEHOLDER}/posts/1"))
            },
            ApiSample("HEAD", "no response body") {
                Net.send(Net.request("HEAD", "${Endpoints.HTTPBIN}/anything"))
            }
        )
    )

    // MARK: Status codes

    private val statusCodes = ApiGroup(
        "Status codes",
        listOf(200, 204, 301, 401, 404, 429, 500).map { code ->
            ApiSample("$code", "${Endpoints.HTTPBIN}/status/$code") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/status/$code"))
            }
        }
    )

    // MARK: Headers, query, cookies

    private val headersAndCookies = ApiGroup(
        "Headers, query & cookies",
        listOf(
            ApiSample("Query parameters", "?search=local%20response&page=2") {
                val url = "${Endpoints.HTTPBIN}/get".toHttpUrl().newBuilder()
                    .addQueryParameter("search", "local response")
                    .addQueryParameter("page", "2")
                    .addQueryParameter("tags", "a,b,c")
                    .addQueryParameter(
                        "token",
                        "It is a long established fact that a reader will be distracted by the readable content of a page when looking at its layout. The point of using Lorem Ipsum is that it has a more-or-less normal distribution of letters, as opposed to using 'Content here, content here', making it look like readable English."
                    )
                    .build()
                Net.send(Net.request("GET", url.toString()))
            },
            ApiSample("Custom headers", "X-Request-Id, X-Api-Key, Accept-Language") {
                Net.send(
                    Net.request(
                        "GET", "${Endpoints.HTTPBIN}/headers",
                        headers = mapOf(
                            "X-Request-Id" to UUID.randomUUID().toString(),
                            "X-Api-Key" to "test-key-1234567890",
                            "Accept-Language" to "en-GB,en;q=0.8",
                            "User-Agent" to "LocalResponse-AndroidTestApp/1.0"
                        )
                    )
                )
            },
            ApiSample("Set cookies", "${Endpoints.HTTPBIN}/cookies/set") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/cookies/set?session=abc123&theme=dark"))
            },
            ApiSample("Follow redirect", "3 hops via /redirect/3") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/redirect/3"))
            },
            ApiSample("Cache validation", "ETag round trip") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/etag/local-response-etag"))
            }
        )
    )

    // MARK: Content types

    private val contentTypes = ApiGroup(
        "Content types",
        listOf(
            ApiSample("JSON", "application/json") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/json"))
            },
            ApiSample("XML", "application/xml") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/xml"))
            },
            ApiSample("HTML", "text/html") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/html"))
            },
            ApiSample("Plain text", "robots.txt") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/robots.txt"))
            },
            ApiSample("UTF-8 / emoji", "non-ASCII response body") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/encoding/utf8"))
            },
            ApiSample("Gzip encoded", "Content-Encoding: gzip") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/gzip"))
            },
            ApiSample("PNG image", "binary body") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/image/png"))
            },
            ApiSample("SVG image", "text-ish binary body") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/image/svg"))
            }
        )
    )

    // MARK: Large payloads

    /// Big response bodies, in the two shapes that behave differently: laid out
    /// over many lines, and minified onto one. A single enormous line is what
    /// makes the mapper's editor crawl, so pretty and minified files are kept
    /// in matched sizes.
    private val largePayloads = ApiGroup(
        "Large payloads",
        listOf(
            ApiSample("64 KB JSON", "pretty · still highlighted") {
                Net.send(Net.request("GET", "${Endpoints.JSON_DUMMY}/64KB.json"))
            },
            ApiSample("256 KB JSON", "pretty · past the highlight budget") {
                Net.send(Net.request("GET", "${Endpoints.JSON_DUMMY}/256KB.json"))
            },
            ApiSample("512 KB JSON", "minified · one 464 KB line") {
                Net.send(Net.request("GET", "${Endpoints.JSON_DUMMY}/512KB-min.json"))
            },
            ApiSample("5 MB JSON", "minified · one 4.6 MB line") {
                Net.send(Net.request("GET", "${Endpoints.JSON_DUMMY}/5MB-min.json"), note = "big")
            },
            ApiSample("1 MB array", "${Endpoints.JSON_PLACEHOLDER}/photos · 5000 objects") {
                Net.send(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/photos"))
            }
        )
    )

    // MARK: Request bodies

    private val requestBodies = ApiGroup(
        "Request bodies",
        listOf(
            ApiSample("Form url-encoded", "application/x-www-form-urlencoded") {
                val form = "name=Local+Response&platform=Android&count=3"
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "application/x-www-form-urlencoded"),
                        body = form.toRequestBody("application/x-www-form-urlencoded".toMediaType())
                    )
                )
            },
            ApiSample("Multipart form data", "text fields + file part") {
                val boundary = Net.boundary()
                val fileData = ByteArray(2048) { (it % 251).toByte() }
                val body = Net.multipartBody(
                    boundary = boundary,
                    fields = mapOf("title" to "multipart sample", "source" to "AndroidTestApp"),
                    fileName = "payload.bin",
                    fileData = fileData
                )
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "multipart/form-data; boundary=$boundary"),
                        body = body.toRequestBody("multipart/form-data; boundary=$boundary".toMediaType())
                    )
                )
            },
            ApiSample("Nested JSON body", "arrays + nested objects") {
                val payload = JSONObject().apply {
                    put("user", JSONObject().apply {
                        put("id", 42)
                        put("name", "Chandan")
                        put("roles", Net.jsonArray(listOf("admin", "tester")))
                    })
                    put("device", JSONObject().apply {
                        put("os", "Android")
                        put("emulator", false)
                    })
                    put("events", JSONArray().apply {
                        (1..5).forEach { put(JSONObject().apply { put("seq", it); put("kind", "tap") }) }
                    })
                }
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "application/json"),
                        body = payload.toString().toRequestBody("application/json".toMediaType())
                    )
                )
            },
            ApiSample("Large JSON body", "~500 KB request") {
                val blob = "local-response-".repeat(2_000)
                val payload = JSONObject().apply {
                    put("items", JSONArray().apply {
                        (1..30).forEach { put(JSONObject().apply { put("id", it); put("blob", blob) }) }
                    })
                }
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "application/json"),
                        body = payload.toString().toRequestBody("application/json".toMediaType())
                    )
                )
            }
        )
    )

    // MARK: Uploads

    private val uploads = ApiGroup(
        "Uploads",
        listOf(
            ApiSample("Upload from memory", "256 KB byte array") {
                val payload = ByteArray(256 * 1024) { 0xAB.toByte() }
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "application/octet-stream"),
                        body = payload.toRequestBody("application/octet-stream".toMediaType())
                    ),
                    note = "upload/data"
                )
            },
            ApiSample("Upload from file", "streams a temp file") {
                withContext(Dispatchers.IO) {
                    try {
                        val file = File.createTempFile("upload-sample", ".bin")
                        file.writeBytes(ByteArray(128 * 1024) { (it % 256).toByte() })
                        val outcome = Net.send(
                            Net.request(
                                "PUT", "${Endpoints.HTTPBIN}/put",
                                headers = mapOf("Content-Type" to "application/octet-stream"),
                                body = file.asRequestBody("application/octet-stream".toMediaType())
                            ),
                            note = "upload/file"
                        )
                        file.delete()
                        outcome
                    } catch (e: Exception) {
                        CallOutcome.failure(Net.describe(e))
                    }
                }
            },
            ApiSample("Multipart image upload", "fetch a PNG, then post it back") {
                val image = withContext(Dispatchers.IO) {
                    try {
                        Net.client.newCall(Net.request("GET", "${Endpoints.HTTPBIN}/image/png"))
                            .execute().use { it.body.bytes() }
                    } catch (e: Exception) {
                        null
                    }
                } ?: return@ApiSample CallOutcome.failure("could not fetch source image")

                val boundary = Net.boundary()
                val body = Net.multipartBody(
                    boundary = boundary,
                    fields = mapOf("caption" to "round-tripped png"),
                    fileName = "image.png",
                    fileData = image
                )
                Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "multipart/form-data; boundary=$boundary"),
                        body = body.toRequestBody("multipart/form-data; boundary=$boundary".toMediaType())
                    )
                )
            }
        )
    )

    // MARK: Downloads & streaming

    private val downloadsAndStreaming = ApiGroup(
        "Downloads & streaming",
        listOf(
            ApiSample("Download to disk", "/bytes — httpbin caps the body at 100 KB") {
                withContext(Dispatchers.IO) {
                    try {
                        val file = File.createTempFile("download-sample", ".bin")
                        Net.client.newCall(Net.request("GET", "${Endpoints.HTTPBIN}/bytes/1048576"))
                            .execute().use { response ->
                                file.outputStream().use { out -> response.body.byteStream().copyTo(out) }
                                val size = Net.readableBytes(file.length())
                                file.delete()
                                CallOutcome.success("HTTP ${response.code} · downloaded $size to disk")
                            }
                    } catch (e: Exception) {
                        CallOutcome.failure(Net.describe(e))
                    }
                }
            },
            ApiSample("Chunked JSON stream", "/stream/25 newline-delimited") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/stream/25"))
            },
            ApiSample("Line-by-line stream", "consumed as it arrives") {
                withContext(Dispatchers.IO) {
                    try {
                        Net.client.newCall(Net.request("GET", "${Endpoints.HTTPBIN}/stream/15"))
                            .execute().use { response ->
                                var lines = 0
                                val source = response.body.source()
                                while (source.readUtf8Line() != null) {
                                    lines++
                                }
                                CallOutcome.success("HTTP ${response.code} · consumed $lines streamed lines")
                            }
                    } catch (e: Exception) {
                        CallOutcome.failure(Net.describe(e))
                    }
                }
            }
        )
    )

    // MARK: Media

    private val media = ApiGroup(
        "Media",
        listOf(
            ApiSample("Random sample image", "yavuzceliker sample-images") {
                val index = (1..100).random()
                Net.send(Net.request("GET", "https://yavuzceliker.github.io/sample-images/image-$index.jpg"))
            },
            ApiSample("MP4 video (small)", "person-bicycle-car-detection.mp4") {
                Net.send(
                    Net.request(
                        "GET",
                        "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4"
                    )
                )
            },
            ApiSample("Video first 2 MB", "ranged media fetch") {
                Net.send(
                    Net.request(
                        "GET",
                        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                        headers = mapOf("Range" to "bytes=0-2097151")
                    )
                )
            }
        )
    )

    // MARK: Failures

    private val failures = ApiGroup(
        "Failures & timeouts",
        listOf(
            ApiSample("Unresolvable host", "DNS failure") {
                Net.send(Net.request("GET", "https://this-host-does-not-exist-local-response.invalid/data"))
            },
            ApiSample("Connection refused", "http://127.0.0.1:9") {
                Net.send(Net.request("GET", "http://127.0.0.1:9/"), timeoutSec = 5)
            },
            ApiSample("Request timeout", "10s delay, 3s timeout") {
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/delay/10"), timeoutSec = 3)
            },
            ApiSample("Cancelled mid-flight", "cancel after 300 ms") {
                withContext(Dispatchers.IO) {
                    val call = Net.client.newCall(Net.request("GET", "${Endpoints.HTTPBIN}/delay/10"))
                    coroutineScope {
                        val running = async {
                            try {
                                call.execute().use { Net.summary(it) }
                            } catch (e: Exception) {
                                CallOutcome.failure(Net.describe(e))
                            }
                        }
                        delay(300)
                        call.cancel()
                        running.await()
                    }
                }
            },
            ApiSample("Expired TLS certificate", "expired.badssl.com") {
                Net.send(Net.request("GET", "https://expired.badssl.com/"), timeoutSec = 10)
            },
            ApiSample("Malformed JSON response", "server returns HTML for a JSON call") {
                Net.send(
                    Net.request(
                        "GET", "${Endpoints.HTTPBIN}/html",
                        headers = mapOf("Accept" to "application/json")
                    )
                )
            }
        )
    )

    // MARK: Authentication

    private val authentication = ApiGroup(
        "Authentication",
        listOf(
            ApiSample("Basic auth — success", "user / passwd") {
                Net.send(
                    Net.request(
                        "GET", "${Endpoints.HTTPBIN}/basic-auth/user/passwd",
                        headers = mapOf("Authorization" to basic("user", "passwd"))
                    )
                )
            },
            ApiSample("Basic auth — 401", "wrong password") {
                Net.send(
                    Net.request(
                        "GET", "${Endpoints.HTTPBIN}/basic-auth/user/passwd",
                        headers = mapOf("Authorization" to basic("user", "wrong"))
                    )
                )
            },
            ApiSample("Bearer token", "Authorization: Bearer …") {
                Net.send(
                    Net.request(
                        "GET", "${Endpoints.HTTPBIN}/bearer",
                        headers = mapOf("Authorization" to "Bearer local-response-test-token")
                    )
                )
            },
            ApiSample("Token refresh flow", "401 → fetch token → retry") {
                val first = Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/status/401"))
                val token = Net.send(
                    Net.request(
                        "POST", "${Endpoints.HTTPBIN}/post",
                        headers = mapOf("Content-Type" to "application/json"),
                        body = Net.json {
                            put("grant_type", "refresh_token")
                            put("refresh_token", "rt_123")
                        }
                    )
                )
                val retry = Net.send(
                    Net.request(
                        "GET", "${Endpoints.HTTPBIN}/get",
                        headers = mapOf("Authorization" to "Bearer refreshed-token")
                    )
                )
                CallOutcome.success(
                    "401 → ${first.text.take(12)} | token → ${token.text.take(12)} | retry → ${retry.text.take(30)}"
                )
            }
        )
    )

    // MARK: Client styles

    /// The iOS app calls this group "Session styles" and varies `URLSession`.
    /// OkHttp has no delegates or session configurations, so the equivalent
    /// axes are how the call is dispatched and how the client is built.
    private val clientStyles = ApiGroup(
        "Client styles",
        listOf(
            ApiSample("Synchronous call", "Call.execute() on an IO thread") {
                Net.send(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/users/1"), note = "execute")
            },
            ApiSample("Enqueued call", "Call.enqueue() with a Callback") {
                Net.enqueue(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/users/2"), note = "enqueue")
            },
            ApiSample("No cache, no cookies", "a throwaway client") {
                // Built from the shared client so the interceptor — and the
                // connection pool — come along; only the storage is dropped.
                val bare = Net.client.newBuilder()
                    .cache(null)
                    .cookieJar(CookieJar.NO_COOKIES)
                    .build()
                Net.send(Net.request("GET", "${Endpoints.HTTPBIN}/get"), client = bare, note = "throwaway")
            },
            ApiSample("HTTP/2 endpoint", "postman-echo over h2") {
                Net.send(Net.request("GET", "${Endpoints.POSTMAN_ECHO}/get?protocol=h2"))
            }
        )
    )

    // MARK: Concurrency

    private val concurrency = ApiGroup(
        "Concurrency",
        listOf(
            ApiSample("Sequential chain", "user → posts → comments") {
                val user = Net.send(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/users/1"))
                if (!user.ok) return@ApiSample user
                val posts = Net.send(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/posts?userId=1"))
                if (!posts.ok) return@ApiSample posts
                val comments = Net.send(Net.request("GET", "${Endpoints.JSON_PLACEHOLDER}/comments?postId=1"))
                CallOutcome.success("chained 3 calls · last → ${comments.text.take(60)}")
            },
            ApiSample("Mixed success & failure", "5 calls, some 5xx") {
                val urls = listOf(
                    "${Endpoints.HTTPBIN}/status/200",
                    "${Endpoints.HTTPBIN}/status/500",
                    "${Endpoints.HTTPBIN}/status/404",
                    "${Endpoints.JSON_PLACEHOLDER}/todos/3",
                    "https://this-host-does-not-exist-local-response.invalid/x"
                )
                val outcomes = coroutineScope {
                    urls.map { url ->
                        async { Net.send(Net.request("GET", url), timeoutSec = 10).ok }
                    }.awaitAll()
                }
                CallOutcome.success(
                    "${outcomes.count { it }} completed, ${outcomes.count { !it }} errored"
                )
            }
        )
    )

    // MARK: Retrofit

    /// The interceptor is usually reached through Retrofit rather than raw
    /// OkHttp, and Retrofit builds its own requests — annotations, converters,
    /// a fixed base url — so it is worth exercising on its own.
    private val retrofit = ApiGroup(
        "Retrofit",
        listOf(
            ApiSample("GET via Retrofit", "@GET(\"/posts/{id}?pqr=cde\")") {
                withContext(Dispatchers.IO) {
                    try {
                        val response = repository.getPost(1)
                        val body = response.body()?.string().orEmpty()
                        CallOutcome.success(
                            "HTTP ${response.code()} · ${Net.readableBytes(body.length.toLong())}\n" +
                                body.take(160).replace("\n", " ")
                        )
                    } catch (e: Exception) {
                        CallOutcome.failure(Net.describe(e))
                    }
                }
            },
            ApiSample("POST via Retrofit", "@Body Post, gson converter") {
                withContext(Dispatchers.IO) {
                    try {
                        val response = repository.createPost(
                            Post(userId = 1, id = null, title = "Test Post", body = "from the catalogue")
                        )
                        val body = response.body()?.string().orEmpty()
                        CallOutcome.success(
                            "HTTP ${response.code()} · ${Net.readableBytes(body.length.toLong())}\n" +
                                body.take(160).replace("\n", " ")
                        )
                    } catch (e: Exception) {
                        CallOutcome.failure(Net.describe(e))
                    }
                }
            }
        )
    )

    private val repository by lazy { PostRepository(NetworkModule.apiService) }

    private fun basic(user: String, password: String): String {
        val encoded = android.util.Base64.encodeToString(
            "$user:$password".toByteArray(Charsets.UTF_8),
            android.util.Base64.NO_WRAP
        )
        return "Basic $encoded"
    }
}
