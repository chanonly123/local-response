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
    
    // after response
    let body: String?
    let resHeaders: [String: String]?
    let statusCode: Int?
    let error: String?
    let finished: Bool
    
    init(task: URLSessionTask, finished: Bool, response: URLResponse?, data: Data?, err: String?) {
        taskId = task.uniqueId //"\(task.taskIdentifier)-" + URLTaskModel.sessionId
        url = task.originalRequest?.url?.absoluteString ?? ""
        method = task.originalRequest?.httpMethod ?? ""
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
                if let data, let str = String(data: data, encoding: .utf8) {
                    body = str
                } else {
                    body = nil
                }
                statusCode = res.statusCode
                error = nil
            } else {
                error = err ?? "Unknown"
                body = nil
                resHeaders = nil
                statusCode = 0
            }
        } else {
            resHeaders = nil
            body = nil
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
