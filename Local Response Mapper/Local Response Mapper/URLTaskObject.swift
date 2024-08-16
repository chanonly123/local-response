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
    @Persisted var method: String = ""
    @Persisted var reqHeaders: Map<String, String> = .init()
    
    // after response
    @Persisted var body: String = ""
    @Persisted var resHeaders: Map<String, String> = .init()
    @Persisted var statusCode: Int = 0
    @Persisted var finished: Bool = false
    
    convenience init(taskId: String) {
        self.init()
        self.taskId = taskId
    }
    
    func updateFrom(task: URLTaskModel) {
        date = Date().timeIntervalSince1970
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = task.body ?? ""
        task.resHeaders?.forEach { resHeaders[$0.key] = $0.value }
        statusCode = task.statusCode ?? 0
        finished = task.finished
    }
    
    var requestHeaders: [String: String] { realmMapToDict(reqHeaders) }
    var responseHeaders: [String: String] { realmMapToDict(resHeaders) }
    
    private func realmMapToDict(_ map: Map<String, String>) -> [String: String] {
        var dict = [String: String]()
        map.forEach { dict[$0.key] = $0.value }
        return dict
    }
}
