//
//  File.swift
//  
//
//  Created by Chandan on 16/08/24.
//

import Foundation

struct URLTaskModel: Codable {
    private static let sessionId = UUID().uuidString
    
    let taskId: String
    let url: String
    let method: String
    let reqHeaders: [String: String]
    let body: String?

    // after response
    let resString: String?
    let resHeaders: [String: String]?
    let statusCode: Int?
    let error: String?
    let finished: Bool
    
    init(task: URLSessionTask, finished: Bool, response: URLResponse?, responseString: Data?, err: String?) {
        taskId = task.uniqueId
        url = task.originalRequest?.url?.absoluteString ?? ""
        method = task.originalRequest?.httpMethod ?? ""
        body = if let httpBody = task.originalRequest?.httpBody { String(data: httpBody, encoding: .utf8) } else { nil }
        var _reqHeaders = [String: String]()
        task.originalRequest?.allHTTPHeaderFields?.forEach {
            _reqHeaders[$0.key] = $0.value
        }
        reqHeaders = _reqHeaders
        self.finished = finished
        
        if finished {
            if let res = response as? HTTPURLResponse {
                var _resHeaders = [String: String]()
                res.allHeaderFields.forEach {
                    if let key = $0.key as? String, let value = $0.value as? String {
                        _resHeaders[key] = value
                    }
                }
                resHeaders = _reqHeaders
                if let responseString, let str = String(data: responseString, encoding: .utf8) {
                    resString = str
                } else {
                    resString = nil
                }
                statusCode = res.statusCode
                error = nil
            } else {
                error = err ?? "Unknown"
                resString = nil
                resHeaders = nil
                statusCode = 0
            }
        } else {
            resHeaders = nil
            resString = nil
            statusCode = nil
            error = nil
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

struct MapCheckResponse: Codable {
    let statusCode: Int
    let method: String
    let body: String
    let resHeaders: [String: String]
}
