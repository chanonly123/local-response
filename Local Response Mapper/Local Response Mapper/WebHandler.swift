//
//  WebHandler.swift
//  Local Response Mapper
//
//  Created by Chandan on 15/08/24.
//

import FlyingFox
import Foundation
import Factory

class WebHandler {
    static let shared = WebHandler()
    
    init() {}
    
    let server = HTTPServer(port: 4040)
    @Injected(\.db) var db
    
    func startServer() {
        if AppDelegate.isPreview {
            return
        }
        Task {
            do {
                try await server.start()
                
            } catch let e {
                print("\(e)")
            }
        }
        
        Task {
            await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordBeginUrl), handler: recordBegin)
            await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordEndUrl), handler: recordEnd)
            
            await server.appendRoute("GET /hello") { req in
                let body = """
{
  "status": {
    "code": 201,
    "status": "NOT"
  },
  "response": {
    
  }
}
"""
                return HTTPResponse(statusCode: .ok, body: body.data(using: .utf8)!)
            }
            
        }
    }
    
    lazy var recordBegin: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let data = try await req.bodyData
        let obj = try await JSONDecoder().decode(URLTaskModel.self, from: req.bodyData)
        try self.db.recordBegin(task: obj)
        return HTTPResponse(statusCode: .ok)
    }
    
    lazy var recordEnd: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await JSONDecoder().decode(URLTaskModel.self, from: req.bodyData)
        try self.db.recordEnd(task: obj)
        return HTTPResponse(statusCode: .ok)
    }
}

