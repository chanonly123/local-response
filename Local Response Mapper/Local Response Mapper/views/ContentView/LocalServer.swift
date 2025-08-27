//
//  WebHandler.swift
//  Local Response Mapper
//
//  Created by Chandan on 15/08/24.
//

import FlyingFox
import Foundation
import Factory

class LocalServer: NSObject, ObservableObject {

    @MainActor override init() {
        super.init()
    }

    let server = HTTPServer(address: .inet(port: UInt16(Constants.localBaseUrlPort)))
    private var service: NetService?
    @Injected(\.db) var db

    @MainActor @Published var listeningAddress: String = ""
    @MainActor @Published var isListening: Bool? = false
    @MainActor @Published var error: Error?

    static let isEditedKey = "--isEdited--"

    @MainActor
    func startServer() {
        if Utils.isPreview {
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
                await server.appendRoute("/") { request in
                    return HTTPResponse(statusCode: .ok, body: "Local Response Mapper Running".data(using: .utf8) ?? Data())
                }
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordBeginUrl), handler: recordBegin)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordEndUrl), handler: recordEnd)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.checkMapResponse), handler: returnMappedIfAny)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.overridenRequest), handler: overridenRequestHandler)
                startBonjourService()
            } catch let e {
                Logger.debugPrint("Error: \(e)")
                error = e
                isListening = false
            }
        }

        Task { [weak self] in
            guard let `self` = self else { return }
            do {
                try await server.run()
            } catch let e {
                Logger.debugPrint("Error: \(e)")
                error = e
                isListening = false
            }
        }
    }

    func startBonjourService() {
        // Publish service: type "_myapp._tcp.", domain "local.", name "My Local Server"
        service = NetService(domain: "local.",
                             type: "_http._tcp.",
                             name: "Local Response Mapper Server",
                             port: Int32(Constants.localBaseUrlPort))
        service?.delegate = self
        service?.publish()
    }

    @MainActor
    func reloadLocalAddress() {
        let ipAddr = Utils.getIPAddress() ?? "localhost"
        listeningAddress = "http://\(ipAddr):\(Constants.localBaseUrlPort)"
    }

    lazy var recordBegin: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let data = try await req.bodyData
        let obj = try await JSONDecoder().decode(URLTaskModelBegin.self, from: req.bodyData)
        try self.db.recordBegin(task: obj)
        return HTTPResponse(statusCode: .ok)
    }

    lazy var recordEnd: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await JSONDecoder().decode(URLTaskModelEnd.self, from: req.bodyData)
        try self.db.recordEnd(task: obj)
        return HTTPResponse(statusCode: .ok)
    }

    lazy var returnMappedIfAny: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await JSONDecoder().decode(MapCheckRequest.self, from: req.bodyData)
        if let id = try self.db.getLocalMapIfAvailable(req: obj), let data = id.data(using: .utf8) {
            return HTTPResponse(statusCode: .ok, body: data)
        } else {
            return HTTPResponse(statusCode: .noContent)
        }
    }

    lazy var overridenRequestHandler: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        do {
            if let id = req.query["id"], let obj = try self.db.getLocalMap(id: id) {

                let body = obj.resString.data(using: .utf8) ?? Data()
                let statusCode = Int(obj.statusCode) ?? 0
                var resHeaders = [HTTPHeader: String]()
                obj.resHeadersMap.forEach { resHeaders[HTTPHeader($0.key)] = $0.value }
                resHeaders[HTTPHeader(Self.isEditedKey)] = "1"
                resHeaders[HTTPHeader("Content-Length")] = "\(body.count)"
                resHeaders[HTTPHeader("Content-Type")] = "application/json; charset=utf-8"

                return HTTPResponse(
                    statusCode: HTTPStatusCode(
                        statusCode,
                        phrase: "custom"
                    ),
                    headers: resHeaders,
                    body: body
                )
            }
        } catch let e {
            Logger.debugPrint("error: \(e)")
        }
        return HTTPResponse(statusCode: .internalServerError)
    }
}

extension LocalServer: NetServiceDelegate {

    func netServiceDidPublish(_ sender: NetService) {
        Logger.debugPrint("Bonjour Service published: domain=\(sender.domain) type=\(sender.type) name=\(sender.name) port=\(sender.port)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        Logger.debugPrint("Bonjour Service failed to publish: \(errorDict)")
    }
}
