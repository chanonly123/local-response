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

/// The request as it actually goes out, sent after a `modifyRequest` rule has
/// edited it. `recordBegin` has already reported the request the app built, so
/// this replaces those fields on the recorded call.
struct URLTaskModelUpdate: Codable {

    let taskId: String
    let url: String
    let method: String
    let reqHeaders: [String: String]
    let body: String?
    let bundleID: String?

    init(task: URLSessionTask, request: URLRequest) {
        bundleID = Bundle.main.bundleIdentifier
        taskId = task.uniqueId
        url = request.url?.absoluteString ?? ""
        method = request.httpMethod ?? ""
        reqHeaders = request.allHTTPHeaderFields ?? [:]
        body = if let httpBody = request.httpBody { String(data: httpBody, encoding: .utf8) } else { nil }
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

/// What the mapper wants done with a request that is about to be sent: edits to
/// apply to it, and — when a rule answers it locally — the rule that serves the
/// response instead.
struct MapCheckResponse: Codable {

    /// Rule id whose canned response replaces this request, if one matched.
    let overrideId: String?

    /// Headers to set on the outgoing request, merged from every matching
    /// `modifyRequest` rule in priority order.
    let reqHeaders: [String: String]

    /// Replacement request body, when a rule declares one.
    let reqBody: String?

    init(overrideId: String? = nil, reqHeaders: [String: String] = [:], reqBody: String? = nil) {
        self.overrideId = overrideId
        self.reqHeaders = reqHeaders
        self.reqBody = reqBody
    }

    var isEmpty: Bool { overrideId == nil && reqHeaders.isEmpty && reqBody == nil }

    var changesRequest: Bool { !reqHeaders.isEmpty || reqBody != nil }
}
