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

    init(task: URLSessionTask) {
        bundleID = Bundle.main.bundleIdentifier
        taskId = task.uniqueId
        url = task.originalRequest?.url?.absoluteString ?? ""
        method = task.originalRequest?.httpMethod ?? ""
        body = if let httpBody = task.originalRequest?.httpBody { String(data: httpBody, encoding: .utf8) } else { nil }
        var _reqHeaders = [String: String]()
        task.originalRequest?.allHTTPHeaderFields?.forEach {
            _reqHeaders[$0.key] = $0.value
        }
        reqHeaders = _reqHeaders
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
        } else {
            error = err ?? "Unknown"
            resString = nil
            resHeaders = nil
            resStringB64 = nil
            statusCode = 0
            mimeType = nil
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
