//
//  Models.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import Foundation

struct FileItem {
    let name: String
    let path: String
}

struct URLTaskItemModel: Codable {
    var taskId: Int
    var url: String
    var method: String
    var reqHeaders: [String: String]
    
    // after end
    var body: Data
    var resHeaders: [String: String]
    var statusCode: Int
    var finished: Bool
    
    init(task: URLSessionTask) {
        taskId = task.taskIdentifier
        url = task.originalRequest?.url?.absoluteString ?? ""
        method = task.originalRequest?.httpMethod ?? ""
        var _reqHeaders = [String: String]()
        task.originalRequest?.allHTTPHeaderFields?.forEach {
            _reqHeaders[$0.key] = $0.value
        }
        reqHeaders = _reqHeaders
        
        resHeaders = .init()
        body = Data()
        statusCode = 0
        finished = false
    }
}
