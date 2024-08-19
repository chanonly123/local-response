//
//  WebHandler.swift
//  Local Response Mapper
//
//  Created by Chandan on 15/08/24.
//

import FlyingFox
import Foundation
import Factory

class LocalServer: ObservableObject {
    
    @MainActor init() {}
    
    let server = HTTPServer(address: .loopback(port: UInt16(Constants.localBaseUrlPort)))
    @Injected(\.db) var db
    
    @MainActor @Published var listeningAddress: String = ""
    @MainActor @Published var isListening: Bool? = false
    @MainActor @Published var error: Error?
    
    @MainActor
    func startServer() {
        if AppDelegate.isPreview {
            return
        }
        guard isListening == false else { return }
        Task {
            isListening = nil
        }
        
        Task { [weak self] in
            guard let `self` = self else { return }
            do {
                try await server.waitUntilListening(timeout: 10)
                isListening = await server.isListening
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordBeginUrl), handler: recordBegin)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordEndUrl), handler: recordEnd)
            } catch let e {
                print("Error: \(e)")
                error = e
                isListening = false
            }
        }
        
        Task { [weak self] in
            guard let `self` = self else { return }
            do {
                try await server.start()
            } catch let e {
                print("Error: \(e)")
                error = e
                isListening = false
            }
        }
    }
    
    @MainActor
    func reloadLocalAddress() {
        listeningAddress = Utils.getIPAddress() ?? ":\(Constants.localBaseUrlPort)"
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
    
    lazy var returnMappedIfAny: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await JSONDecoder().decode(URLTaskModel.self, from: req.bodyData)
        try self.db.recordEnd(task: obj)
        return HTTPResponse(statusCode: .ok)
    }

}

