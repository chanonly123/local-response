//
//  File.swift
//
//
//  Created by Chandan on 16/08/24.
//

import Foundation

struct URLTaskModelBegin: Codable {

    let taskId: String
    let url: String
    let method: String
    let reqHeaders: [String: String]
    let body: String?
    let bundleID: String?
    let startTime: Double?

    init(task: URLSessionTask) {
        bundleID = Bundle.main.bundleIdentifier
        taskId = task.uniqueId
        url = task.originalRequest?.url?.absoluteString ?? ""
        method = task.originalRequest?.httpMethod ?? ""
        body = if let httpBody = task.originalRequest?.httpBody { String(data: httpBody, encoding: .utf8) } else { nil }
        reqHeaders = task.originalRequest?.allHTTPHeaderFields ?? [:]
        startTime = Date().timeIntervalSince1970
    }
}

struct URLTaskModelEnd: Codable {
    let taskId: String
    let resString: String?
    let resStringB64: String?
    let resHeaders: [String: String]?
    let statusCode: Int?
    let error: String?
    let bundleID: String?
    let mimeType: String?
    let endTime: Double?

    init(
        taskId: String,
        resString: String?,
        resStringB64: String?,
        resHeaders: [String : String]?,
        statusCode: Int?,
        error: String?,
        bundleID: String?,
        mimeType: String?
    ) {
        self.taskId = taskId
        self.resString = resString
        self.resStringB64 = resStringB64
        self.resHeaders = resHeaders
        self.statusCode = statusCode
        self.error = error
        self.bundleID = bundleID
        self.mimeType = mimeType
        self.endTime = Date().timeIntervalSince1970
    }

    init(task: URLSessionTask, response: URLResponse?, responseData: Data?, err: String?) {
        bundleID = Bundle.main.bundleIdentifier
        taskId = task.uniqueId
        if let res = response as? HTTPURLResponse {
            var _resHeaders = [String: String]()
            res.allHeaderFields.forEach {
                if let key = $0.key as? String, let value = $0.value as? String {
                    _resHeaders[key] = value
                }
            }
            resHeaders = _resHeaders
            if let responseData, let str = String(data: responseData, encoding: .utf8) {
                resString = str
            } else {
                resString = nil
            }
            resStringB64 = responseData?.base64EncodedString()
            statusCode = res.statusCode
            error = err
            mimeType = res.mimeType
            endTime = Date().timeIntervalSince1970
        } else {
            error = err ?? "Unknown"
            resString = nil
            resHeaders = nil
            resStringB64 = nil
            statusCode = 0
            mimeType = nil
            endTime = nil
        }
    }
}

extension URLSessionTask {

    var uniqueId: String {
        return "\(unsafeBitCast(self, to: Int.self))-\(self.taskIdentifier)"
    }
}

struct LocalModel: Codable {
    let subUrl: String?
    let method: String?
    let body: String?
    let statusCode: Int?
    let resHeaders: [String: String]?
}

struct MapCheckRequest: Codable {
    let url: String
    let method: String
}

/// How a matched rule should behave.
enum MapMode: String, Codable {
    /// Redirect the request to the local server and serve a stored response (original behavior).
    case mockResponse
    /// Let the request hit the real backend, but rewrite it first (url / method / headers).
    case modifyRequest
}

/// Instructions for rewriting an outgoing request before it is sent.
struct RequestOverride: Codable {
    /// Full replacement URL. `nil`/empty keeps the original.
    let url: String?
    /// HTTP method override. `nil`/empty keeps the original.
    let method: String?
    /// When true, drop every original header before applying `setHeaders` (the `*` sentinel).
    let clearAllHeaders: Bool
    /// Headers to add or override.
    let setHeaders: [String: String]
    /// Header names to remove from the original request.
    let removeHeaders: [String]
}

/// Reply from `/check-map-response`: which rule matched and what to do with it.
struct MapMatchResponse: Codable {
    let id: String
    let mode: MapMode
    /// Present only when `mode == .modifyRequest`.
    let request: RequestOverride?
}
