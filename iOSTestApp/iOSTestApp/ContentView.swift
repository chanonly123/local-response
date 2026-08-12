//
//  ContentView.swift
//  iOSTestApp
//
//  Created by Chandan on 17/09/24.
//

import SwiftUI

// MARK: - Endpoints

enum Endpoints {
    static let httpbin = "https://httpbin.org"
    static let jsonPlaceholder = "https://jsonplaceholder.typicode.com"
    static let postmanEcho = "https://postman-echo.com"
    static let webSocketEcho = "wss://ws.postman-echo.com/raw"
}

// MARK: - Result formatting

/// Everything a sample call reports back to the UI. The mapper app is the real
/// output; this is only here so it is obvious the call actually left the device.
struct CallOutcome {
    let ok: Bool
    let text: String

    static func success(_ text: String) -> CallOutcome { CallOutcome(ok: true, text: text) }
    static func failure(_ text: String) -> CallOutcome { CallOutcome(ok: false, text: text) }
}

enum Net {

    static func summary(data: Data, response: URLResponse?, note: String? = nil) -> CallOutcome {
        var parts = [String]()
        if let http = response as? HTTPURLResponse {
            parts.append("HTTP \(http.statusCode)")
            if let mime = http.mimeType { parts.append(mime) }
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary))
        if let note { parts.append(note) }

        var line = parts.joined(separator: " · ")
        if let body = String(data: data.prefix(160), encoding: .utf8), !body.isEmpty {
            line += "\n" + body.replacingOccurrences(of: "\n", with: " ")
        }
        return .success(line)
    }

    static func send(_ request: URLRequest, session: URLSession = .shared, note: String? = nil) async -> CallOutcome {
        do {
            let (data, response) = try await session.data(for: request)
            return summary(data: data, response: response, note: note)
        } catch {
            return .failure(describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    static func request(
        _ method: String,
        _ url: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 60
    ) -> URLRequest {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.httpBody = body
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        return req
    }

    static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// Writes a throwaway file so `uploadTask(with:fromFile:)` has something to send.
    static func temporaryFile(named name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, options: .atomic)
        return url
    }

    static func multipartBody(boundary: String, fields: [String: String], fileName: String, fileData: Data) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

// MARK: - Session flavours

/// Classic delegate-based session — a different swizzling path than the
/// completion-handler / async APIs, so it is worth exercising separately.
final class CollectingSessionDelegate: NSObject, URLSessionDataDelegate {

    private var buffer = Data()
    private var response: URLResponse?
    private var finish: ((CallOutcome) -> Void)?
    private var didFinish = false

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            finish?(.failure(Net.describe(error)))
        } else {
            finish?(Net.summary(data: buffer, response: response, note: "delegate"))
        }
        finish = nil
        session.finishTasksAndInvalidate()
    }

    func run(_ request: URLRequest) async -> CallOutcome {
        await withCheckedContinuation { continuation in
            finish = { continuation.resume(returning: $0) }
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.dataTask(with: request).resume()
        }
    }
}

/// Guards against a continuation being resumed twice when a callback API can
/// fire more than once (or fires after cancellation).
private final class OnceBox {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

// MARK: - Catalog

struct ApiSample: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let run: () async -> CallOutcome
}

struct ApiGroup: Identifiable {
    let id = UUID()
    let name: String
    let samples: [ApiSample]
}

enum ApiCatalog {

    static let groups: [ApiGroup] = [
        httpMethods,
        statusCodes,
        headersAndCookies,
        contentTypes,
        requestBodies,
        uploads,
        downloadsAndStreaming,
        media,
        failures,
        authentication,
        sessionStyles,
        concurrency
    ]

    // MARK: HTTP methods

    static let httpMethods = ApiGroup(name: "HTTP methods", samples: [
        ApiSample(title: "GET", subtitle: "https://echo.free.beeceptor.com") {
            await Net.send(Net.request("GET", "https://echo.free.beeceptor.com"))
        },
        ApiSample(title: "GET", subtitle: "\(Endpoints.jsonPlaceholder)/todos/1?hello=world") {
            await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/todos/1?hello=world"))
        },
        ApiSample(title: "POST (JSON)", subtitle: "\(Endpoints.jsonPlaceholder)/posts") {
            await Net.send(Net.request(
                "POST", "\(Endpoints.jsonPlaceholder)/posts",
                headers: ["Content-Type": "application/json"],
                body: Net.json(["title": "Local Response", "body": "hello", "userId": 1])
            ))
        },
        ApiSample(title: "PUT", subtitle: "\(Endpoints.jsonPlaceholder)/posts/1") {
            await Net.send(Net.request(
                "PUT", "\(Endpoints.jsonPlaceholder)/posts/1",
                headers: ["Content-Type": "application/json"],
                body: Net.json(["id": 1, "title": "replaced", "body": "full update", "userId": 1])
            ))
        },
        ApiSample(title: "PATCH", subtitle: "\(Endpoints.jsonPlaceholder)/posts/1") {
            await Net.send(Net.request(
                "PATCH", "\(Endpoints.jsonPlaceholder)/posts/1",
                headers: ["Content-Type": "application/json"],
                body: Net.json(["title": "patched"])
            ))
        },
        ApiSample(title: "DELETE", subtitle: "\(Endpoints.jsonPlaceholder)/posts/1") {
            await Net.send(Net.request("DELETE", "\(Endpoints.jsonPlaceholder)/posts/1"))
        },
        ApiSample(title: "HEAD", subtitle: "no response body") {
            await Net.send(Net.request("HEAD", "\(Endpoints.httpbin)/anything"))
        },
        ApiSample(title: "OPTIONS", subtitle: "preflight-style call") {
            await Net.send(Net.request("OPTIONS", "\(Endpoints.httpbin)/anything"))
        }
    ])

    // MARK: Status codes

    static let statusCodes: ApiGroup = {
        let codes = [200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 418, 429, 500, 503]
        return ApiGroup(name: "Status codes", samples: codes.map { code in
            ApiSample(title: "\(code)", subtitle: "\(Endpoints.httpbin)/status/\(code)") {
                await Net.send(Net.request("GET", "\(Endpoints.httpbin)/status/\(code)"))
            }
        })
    }()

    // MARK: Headers, query, cookies

    static let headersAndCookies = ApiGroup(name: "Headers, query & cookies", samples: [
        ApiSample(title: "Query parameters", subtitle: "?search=local%20response&page=2") {
            var components = URLComponents(string: "\(Endpoints.httpbin)/get")!
            components.queryItems = [
                URLQueryItem(name: "search", value: "local response"),
                URLQueryItem(name: "page", value: "2"),
                URLQueryItem(name: "tags", value: "a,b,c")
            ]
            return await Net.send(URLRequest(url: components.url!))
        },
        ApiSample(title: "Custom headers", subtitle: "X-Request-Id, X-Api-Key, Accept-Language") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/headers", headers: [
                "X-Request-Id": UUID().uuidString,
                "X-Api-Key": "test-key-1234567890",
                "Accept-Language": "en-GB,en;q=0.8",
                "User-Agent": "LocalResponse-iOSTestApp/1.0"
            ]))
        },
        ApiSample(title: "Set cookies", subtitle: "\(Endpoints.httpbin)/cookies/set") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/cookies/set?session=abc123&theme=dark"))
        },
        ApiSample(title: "Read cookies back", subtitle: "\(Endpoints.httpbin)/cookies") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/cookies"))
        },
        ApiSample(title: "Follow redirect", subtitle: "3 hops via /redirect/3") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/redirect/3"))
        },
        ApiSample(title: "Cache validation", subtitle: "ETag round trip") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/etag/local-response-etag"))
        }
    ])

    // MARK: Content types

    static let contentTypes = ApiGroup(name: "Content types", samples: [
        ApiSample(title: "JSON", subtitle: "application/json") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/json"))
        },
        ApiSample(title: "Large JSON", subtitle: "100 posts + 500 comments") {
            let posts = await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/posts"))
            let comments = await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/comments"))
            return .success("posts → \(posts.text.prefix(40))\ncomments → \(comments.text.prefix(40))")
        },
        ApiSample(title: "XML", subtitle: "application/xml") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/xml"))
        },
        ApiSample(title: "HTML", subtitle: "text/html") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/html"))
        },
        ApiSample(title: "Plain text", subtitle: "robots.txt") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/robots.txt"))
        },
        ApiSample(title: "UTF-8 / emoji", subtitle: "non-ASCII response body") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/encoding/utf8"))
        },
        ApiSample(title: "Gzip encoded", subtitle: "Content-Encoding: gzip") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/gzip"))
        },
        ApiSample(title: "Deflate encoded", subtitle: "Content-Encoding: deflate") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/deflate"))
        },
        ApiSample(title: "Brotli encoded", subtitle: "Content-Encoding: br") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/brotli"))
        },
        ApiSample(title: "PNG image", subtitle: "binary body") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/image/png"))
        },
        ApiSample(title: "JPEG image", subtitle: "binary body") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/image/jpeg"))
        },
        ApiSample(title: "WebP image", subtitle: "binary body") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/image/webp"))
        },
        ApiSample(title: "SVG image", subtitle: "text-ish binary body") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/image/svg"))
        }
    ])

    // MARK: Request bodies

    static let requestBodies = ApiGroup(name: "Request bodies", samples: [
        ApiSample(title: "Form url-encoded", subtitle: "application/x-www-form-urlencoded") {
            let form = "name=Local+Response&platform=iOS&count=3"
            return await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: Data(form.utf8)
            ))
        },
        ApiSample(title: "Multipart form data", subtitle: "text fields + file part") {
            let boundary = "Boundary-\(UUID().uuidString)"
            let fileData = Data((0..<2048).map { UInt8($0 % 251) })
            let body = Net.multipartBody(
                boundary: boundary,
                fields: ["title": "multipart sample", "source": "iOSTestApp"],
                fileName: "payload.bin",
                fileData: fileData
            )
            return await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                body: body
            ))
        },
        ApiSample(title: "Raw text body", subtitle: "text/plain") {
            await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data("plain text payload — with unicode ✅".utf8)
            ))
        },
        ApiSample(title: "Nested JSON body", subtitle: "arrays + nested objects") {
            let payload: [String: Any] = [
                "user": ["id": 42, "name": "Chandan", "roles": ["admin", "tester"]],
                "device": ["os": "iOS", "simulator": true],
                "events": (1...5).map { ["seq": $0, "kind": "tap"] }
            ]
            return await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "application/json"],
                body: Net.json(payload)
            ))
        },
        ApiSample(title: "Large JSON body", subtitle: "~500 KB request") {
            let blob = String(repeating: "local-response-", count: 2_000)
            let payload = ["items": (1...30).map { ["id": $0, "blob": blob] }]
            return await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "application/json"],
                body: Net.json(payload)
            ))
        },
        ApiSample(title: "Empty body POST", subtitle: "no Content-Type") {
            await Net.send(Net.request("POST", "\(Endpoints.httpbin)/post"))
        }
    ])

    // MARK: Uploads

    static let uploads = ApiGroup(name: "Uploads", samples: [
        ApiSample(title: "uploadTask(from: Data)", subtitle: "256 KB in memory") {
            let payload = Data(repeating: 0xAB, count: 256 * 1024)
            let request = Net.request("POST", "\(Endpoints.httpbin)/post", headers: ["Content-Type": "application/octet-stream"])
            return await withCheckedContinuation { continuation in
                let once = OnceBox()
                URLSession.shared.uploadTask(with: request, from: payload) { data, response, error in
                    guard once.claim() else { return }
                    if let error {
                        continuation.resume(returning: .failure(Net.describe(error)))
                    } else {
                        continuation.resume(returning: Net.summary(data: data ?? Data(), response: response, note: "upload/data"))
                    }
                }.resume()
            }
        },
        ApiSample(title: "uploadTask(fromFile:)", subtitle: "streams a temp file") {
            do {
                let fileURL = try Net.temporaryFile(
                    named: "upload-sample.bin",
                    contents: Data((0..<(128 * 1024)).map { UInt8($0 % 256) })
                )
                let request = Net.request("PUT", "\(Endpoints.httpbin)/put", headers: ["Content-Type": "application/octet-stream"])
                return await withCheckedContinuation { continuation in
                    let once = OnceBox()
                    URLSession.shared.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                        guard once.claim() else { return }
                        if let error {
                            continuation.resume(returning: .failure(Net.describe(error)))
                        } else {
                            continuation.resume(returning: Net.summary(data: data ?? Data(), response: response, note: "upload/file"))
                        }
                    }.resume()
                }
            } catch {
                return .failure(Net.describe(error))
            }
        },
        ApiSample(title: "Multipart image upload", subtitle: "fetch a PNG, then post it back") {
            let downloaded = await Net.send(Net.request("GET", "\(Endpoints.httpbin)/image/png"))
            guard downloaded.ok else { return downloaded }

            guard let (imageData, _) = try? await URLSession.shared.data(for: Net.request("GET", "\(Endpoints.httpbin)/image/png")) else {
                return .failure("could not fetch source image")
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            let body = Net.multipartBody(
                boundary: boundary,
                fields: ["caption": "round-tripped png"],
                fileName: "image.png",
                fileData: imageData
            )
            return await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                body: body
            ))
        }
    ])

    // MARK: Downloads & streaming

    static let downloadsAndStreaming = ApiGroup(name: "Downloads & streaming", samples: [
        ApiSample(title: "downloadTask to disk", subtitle: "1 MB via /bytes") {
            await withCheckedContinuation { continuation in
                let once = OnceBox()
                URLSession.shared.downloadTask(with: URL(string: "\(Endpoints.httpbin)/bytes/1048576")!) { location, response, error in
                    guard once.claim() else { return }
                    if let error {
                        continuation.resume(returning: .failure(Net.describe(error)))
                        return
                    }
                    let size = location
                        .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64 }
                        .flatMap { $0 } ?? 0
                    let status = (response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" } ?? "-"
                    let readable = ByteCountFormatter.string(fromByteCount: size, countStyle: .binary)
                    continuation.resume(returning: .success("\(status) · downloaded \(readable) to disk"))
                }.resume()
            }
        },
        ApiSample(title: "Chunked JSON stream", subtitle: "/stream/25 newline-delimited") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/stream/25"))
        },
        ApiSample(title: "Slow drip", subtitle: "10 bytes over 5s") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/drip?duration=5&numbytes=10&code=200"), note: "drip")
        },
        ApiSample(title: "Byte-range request", subtitle: "Range: bytes=0-1023") {
            await Net.send(Net.request(
                "GET", "\(Endpoints.httpbin)/range/8192",
                headers: ["Range": "bytes=0-1023"]
            ))
        },
        ApiSample(title: "URLSession.bytes stream", subtitle: "async line-by-line consumption") {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: Net.request("GET", "\(Endpoints.httpbin)/stream/15"))
                var lines = 0
                for try await _ in bytes.lines { lines += 1 }
                let status = (response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" } ?? "-"
                return .success("\(status) · consumed \(lines) streamed lines")
            } catch {
                return .failure(Net.describe(error))
            }
        }
    ])

    // MARK: Media

    static let media = ApiGroup(name: "Media", samples: [
        ApiSample(title: "Random sample image", subtitle: "yavuzceliker sample-images") {
            let index = (1...100).randomElement()!
            return await Net.send(Net.request("GET", "https://yavuzceliker.github.io/sample-images/image-\(index).jpg"))
        },
        ApiSample(title: "MP4 video (small)", subtitle: "person-bicycle-car-detection.mp4") {
            await Net.send(Net.request("GET", "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4"))
        },
        ApiSample(title: "MP4 video (Big Buck Bunny)", subtitle: "large binary download") {
            await Net.send(Net.request("GET", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"))
        },
        ApiSample(title: "Video first 2 MB", subtitle: "ranged media fetch") {
            await Net.send(Net.request(
                "GET", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                headers: ["Range": "bytes=0-2097151"]
            ))
        }
    ])

    // MARK: Failures

    static let failures = ApiGroup(name: "Failures & timeouts", samples: [
        ApiSample(title: "Unresolvable host", subtitle: "DNS failure") {
            await Net.send(Net.request("GET", "https://this-host-does-not-exist-local-response.invalid/data"))
        },
        ApiSample(title: "Connection refused", subtitle: "http://127.0.0.1:9") {
            await Net.send(Net.request("GET", "http://127.0.0.1:9/", timeout: 5))
        },
        ApiSample(title: "Request timeout", subtitle: "10s delay, 3s timeout") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/delay/10", timeout: 3))
        },
        ApiSample(title: "Cancelled mid-flight", subtitle: "cancel after 300 ms") {
            let task = Task { () -> CallOutcome in
                await Net.send(Net.request("GET", "\(Endpoints.httpbin)/delay/10"))
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            task.cancel()
            return await task.value
        },
        ApiSample(title: "Expired TLS certificate", subtitle: "expired.badssl.com") {
            await Net.send(Net.request("GET", "https://expired.badssl.com/", timeout: 10))
        },
        ApiSample(title: "Self-signed certificate", subtitle: "self-signed.badssl.com") {
            await Net.send(Net.request("GET", "https://self-signed.badssl.com/", timeout: 10))
        },
        ApiSample(title: "Malformed JSON response", subtitle: "server returns HTML for a JSON call") {
            let outcome = await Net.send(Net.request("GET", "\(Endpoints.httpbin)/html", headers: ["Accept": "application/json"]))
            return outcome
        }
    ])

    // MARK: Authentication

    static let authentication = ApiGroup(name: "Authentication", samples: [
        ApiSample(title: "Basic auth — success", subtitle: "user / passwd") {
            let credentials = Data("user:passwd".utf8).base64EncodedString()
            return await Net.send(Net.request(
                "GET", "\(Endpoints.httpbin)/basic-auth/user/passwd",
                headers: ["Authorization": "Basic \(credentials)"]
            ))
        },
        ApiSample(title: "Basic auth — 401", subtitle: "wrong password") {
            let credentials = Data("user:wrong".utf8).base64EncodedString()
            return await Net.send(Net.request(
                "GET", "\(Endpoints.httpbin)/basic-auth/user/passwd",
                headers: ["Authorization": "Basic \(credentials)"]
            ))
        },
        ApiSample(title: "Bearer token", subtitle: "Authorization: Bearer …") {
            await Net.send(Net.request(
                "GET", "\(Endpoints.httpbin)/bearer",
                headers: ["Authorization": "Bearer local-response-test-token"]
            ))
        },
        ApiSample(title: "Digest auth", subtitle: "URLSession handles the challenge") {
            await Net.send(Net.request("GET", "\(Endpoints.httpbin)/digest-auth/auth/user/passwd"))
        },
        ApiSample(title: "Token refresh flow", subtitle: "401 → fetch token → retry") {
            let first = await Net.send(Net.request("GET", "\(Endpoints.httpbin)/status/401"))
            let token = await Net.send(Net.request(
                "POST", "\(Endpoints.httpbin)/post",
                headers: ["Content-Type": "application/json"],
                body: Net.json(["grant_type": "refresh_token", "refresh_token": "rt_123"])
            ))
            let retry = await Net.send(Net.request(
                "GET", "\(Endpoints.httpbin)/get",
                headers: ["Authorization": "Bearer refreshed-token"]
            ))
            return .success("401 → \(first.text.prefix(12)) | token → \(token.text.prefix(12)) | retry → \(retry.text.prefix(30))")
        }
    ])

    // MARK: Session styles

    static let sessionStyles = ApiGroup(name: "Session styles", samples: [
        ApiSample(title: "Completion handler", subtitle: "dataTask(with:completionHandler:)") {
            await withCheckedContinuation { continuation in
                let once = OnceBox()
                URLSession.shared.dataTask(with: URL(string: "\(Endpoints.jsonPlaceholder)/users/1")!) { data, response, error in
                    guard once.claim() else { return }
                    if let error {
                        continuation.resume(returning: .failure(Net.describe(error)))
                    } else {
                        continuation.resume(returning: Net.summary(data: data ?? Data(), response: response, note: "completion"))
                    }
                }.resume()
            }
        },
        ApiSample(title: "Delegate based", subtitle: "URLSessionDataDelegate callbacks") {
            await CollectingSessionDelegate().run(Net.request("GET", "\(Endpoints.jsonPlaceholder)/users/2"))
        },
        ApiSample(title: "Ephemeral session", subtitle: "no cache, no cookie store") {
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            return await Net.send(Net.request("GET", "\(Endpoints.httpbin)/get"), session: session, note: "ephemeral")
        },
        ApiSample(title: "Cache-only policy", subtitle: "returnCacheDataElseLoad") {
            var request = Net.request("GET", "\(Endpoints.httpbin)/cache/60")
            request.cachePolicy = .returnCacheDataElseLoad
            return await Net.send(request, note: "cache policy")
        },
        ApiSample(title: "Reload ignoring cache", subtitle: "reloadIgnoringLocalCacheData") {
            var request = Net.request("GET", "\(Endpoints.httpbin)/cache/60")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            return await Net.send(request, note: "no cache")
        },
        ApiSample(title: "HTTP/2 endpoint", subtitle: "postman-echo over h2") {
            await Net.send(Net.request("GET", "\(Endpoints.postmanEcho)/get?protocol=h2"))
        }
    ])

    // MARK: Concurrency

    static let concurrency = ApiGroup(name: "Concurrency", samples: [
        ApiSample(title: "10 parallel GETs", subtitle: "burst of independent requests") {
            let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
                for id in 1...10 {
                    group.addTask {
                        await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/todos/\(id)")).ok
                    }
                }
                var collected = [Bool]()
                for await value in group { collected.append(value) }
                return collected
            }
            return .success("\(results.filter { $0 }.count)/\(results.count) succeeded in parallel")
        },
        ApiSample(title: "Sequential chain", subtitle: "user → posts → comments") {
            let user = await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/users/1"))
            guard user.ok else { return user }
            let posts = await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/posts?userId=1"))
            guard posts.ok else { return posts }
            let comments = await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/comments?postId=1"))
            return .success("chained 3 calls · last → \(comments.text.prefix(60))")
        },
        ApiSample(title: "Mixed success & failure", subtitle: "5 calls, some 5xx") {
            let urls = [
                "\(Endpoints.httpbin)/status/200",
                "\(Endpoints.httpbin)/status/500",
                "\(Endpoints.httpbin)/status/404",
                "\(Endpoints.jsonPlaceholder)/todos/3",
                "https://this-host-does-not-exist-local-response.invalid/x"
            ]
            let outcomes = await withTaskGroup(of: Bool.self) { group -> [Bool] in
                for url in urls {
                    group.addTask { await Net.send(Net.request("GET", url, timeout: 10)).ok }
                }
                var collected = [Bool]()
                for await value in group { collected.append(value) }
                return collected
            }
            return .success("\(outcomes.filter { $0 }.count) completed, \(outcomes.filter { !$0 }.count) errored")
        },
        ApiSample(title: "Rapid fire (25 calls)", subtitle: "stress the recorder") {
            await withTaskGroup(of: Void.self) { group in
                for id in 1...25 {
                    group.addTask {
                        _ = await Net.send(Net.request("GET", "\(Endpoints.jsonPlaceholder)/todos/\(id)"))
                    }
                }
            }
            return .success("fired 25 requests")
        }
    ])
}

// MARK: - WebSocket

@MainActor
final class WebSocketTester: ObservableObject {

    @Published private(set) var log: [String] = []
    @Published private(set) var isConnected = false

    private var task: URLSessionWebSocketTask?
    private var counter = 0

    func connect() {
        guard task == nil else { return }
        let socket = URLSession.shared.webSocketTask(with: URL(string: Endpoints.webSocketEcho)!)
        task = socket
        socket.resume()
        isConnected = true
        append("connected to \(Endpoints.webSocketEcho)")
        listen()
    }

    func sendText() {
        counter += 1
        send(.string("hello from iOSTestApp #\(counter)"))
    }

    func sendBinary() {
        counter += 1
        send(.data(Data((0..<64).map { UInt8(($0 &+ counter) % 256) })))
    }

    func ping() {
        task?.sendPing { [weak self] error in
            Task { @MainActor in
                self?.append(error.map { "ping failed: \(Net.describe($0))" } ?? "pong received")
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: Data("client closed".utf8))
        task = nil
        isConnected = false
        append("closed")
    }

    private func send(_ message: URLSessionWebSocketTask.Message) {
        guard let task else {
            append("not connected")
            return
        }
        task.send(message) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.append("send failed: \(Net.describe(error))")
                } else {
                    self?.append("sent \(Self.describe(message))")
                }
            }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.append("received \(Self.describe(message))")
                    self.listen()
                case .failure(let error):
                    self.append("receive failed: \(Net.describe(error))")
                    self.isConnected = false
                    self.task = nil
                }
            }
        }
    }

    private static func describe(_ message: URLSessionWebSocketTask.Message) -> String {
        switch message {
        case .string(let text): return "text: \(text)"
        case .data(let data): return "binary: \(data.count) bytes"
        @unknown default: return "unknown frame"
        }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 12 { log.removeFirst(log.count - 12) }
    }
}

// MARK: - Views

struct ContentView: View {

    @State private var results: [UUID: CallOutcome] = [:]
    @State private var running: Set<UUID> = []
    @StateObject private var webSocket = WebSocketTester()

    var body: some View {
        NavigationView {
            List {
                Section("How to use") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. `LocalResponse.connect()` in AppDelegate didFinishLaunchingWithOptions")
                        Text("2. Open the *Local Response* macOS app")
                        Text("3. Run any call below — it should appear in the mapper")
                    }
                    .font(.footnote)
                    Button("Run every sample (slow)") { runAll() }
                }

                ForEach(ApiCatalog.groups) { group in
                    Section {
                        ForEach(group.samples) { sample in
                            SampleRow(
                                sample: sample,
                                outcome: results[sample.id],
                                isRunning: running.contains(sample.id),
                                action: { run(sample) }
                            )
                        }
                    } header: {
                        HStack {
                            Text(group.name)
                            Spacer()
                            Button("Run all") { runGroup(group) }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                Section("WebSocket") {
                    WebSocketSection(tester: webSocket)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Local Response")
        }
        .navigationViewStyle(.stack)
    }

    private func run(_ sample: ApiSample) {
        guard !running.contains(sample.id) else { return }
        running.insert(sample.id)
        results[sample.id] = nil
        Task {
            let outcome = await sample.run()
            results[sample.id] = outcome
            running.remove(sample.id)
        }
    }

    private func runGroup(_ group: ApiGroup) {
        for sample in group.samples {
            run(sample)
        }
    }

    private func runAll() {
        Task {
            for group in ApiCatalog.groups {
                runGroup(group)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }
}

struct SampleRow: View {

    let sample: ApiSample
    let outcome: CallOutcome?
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sample.title).font(.body)
                    Text(sample.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isRunning {
                    ProgressView()
                } else {
                    Button("Run", action: action)
                        .buttonStyle(.bordered)
                }
            }

            if let outcome {
                Text(outcome.text)
                    .font(.caption2)
                    .foregroundColor(outcome.ok ? .green : .orange)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}

struct WebSocketSection: View {

    @ObservedObject var tester: WebSocketTester

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Endpoints.webSocketEcho)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button(tester.isConnected ? "Connected" : "Connect") { tester.connect() }
                    .disabled(tester.isConnected)
                Button("Text") { tester.sendText() }
                Button("Binary") { tester.sendBinary() }
                Button("Ping") { tester.ping() }
                Button("Close") { tester.disconnect() }
            }
            .buttonStyle(.bordered)
            .font(.caption)

            ForEach(Array(tester.log.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
}
