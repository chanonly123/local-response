//
//  URLTaskObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import RealmSwift

class URLTaskObject: Object, Identifiable {
    var id: String { taskId }
    @Persisted var date: Double = Date().timeIntervalSince1970
    @Persisted(primaryKey: true) var taskId: String
    @Persisted var url: String = ""
    @Persisted var body: String = ""
    @Persisted var method: String = ""
    @Persisted var reqHeaders: Map<String, String> = .init()
    
    // after response
    @Persisted var responseString: String = ""
    @Persisted var resHeaders: Map<String, String> = .init()
    @Persisted var statusCode: Int = 0
    
    convenience init(taskId: String) {
        self.init()
        self.taskId = taskId
    }

    func createCopy() -> URLTaskObject {
        let new = URLTaskObject(taskId: UUID().uuidString)
        new.date = date
        new.url = url
        new.body = body
        new.method = method
        new.reqHeaders = reqHeaders
        new.responseString = responseString
        new.resHeaders = resHeaders
        new.statusCode = statusCode
        return new
    }

    func updateFrom(task: URLTaskModelBegin) {
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = (try? Utils.prettyPrintJSON(from: task.body ?? "")) ?? ""
    }

    func updateFrom(task: URLTaskModelEnd) {
        task.resHeaders?.forEach { resHeaders[$0.key] = $0.value }
        responseString = (try? Utils.prettyPrintJSON(from: task.resString ?? "")) ?? ""
        statusCode = task.statusCode ?? 0
    }

}
