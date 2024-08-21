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
    @Persisted var finished: Bool = false
    
    convenience init(taskId: String) {
        self.init()
        self.taskId = taskId
    }
    
    func updateFrom(task: URLTaskModel) {
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = (try? Utils.prettyPrintJSON(from: task.body ?? "")) ?? ""
        task.resHeaders?.forEach { resHeaders[$0.key] = $0.value }
        responseString = task.resString ?? ""
        statusCode = task.statusCode ?? 0
        finished = task.finished
    }
    
}
