//
//  WebHandler.swift
//  Local Response Mapper
//
//  Created by Chandan on 15/08/24.
//

import FlyingFox
import Foundation
import Factory

enum LocalServerError: Error {
    /// The body did not open with the shared key.
    case undecryptableBody
}

class LocalServer: ObservableObject {

    /// One server for the process, not one per window.
    ///
    /// It used to be a `@StateObject` on `ContentView`, so the listener's life
    /// was tied to a window's. Closing the window and reopening it from the
    /// Dock does not re-run `onAppear` — AppKit keeps the scene's state and
    /// only re-shows the window — so nothing restarted the server, and a
    /// window that had been torn down took the listener with it.
    @MainActor static let shared = LocalServer()

    @MainActor private init() {}

    let server = HTTPServer(address: .inet(port: UInt16(Constants.localBaseUrlPort)))
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
                    return HTTPResponse(statusCode: .ok, body: "Success".data(using: .utf8) ?? Data())
                }
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordBeginUrl), handler: recordBegin)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordUpdateUrl), handler: recordUpdate)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.recordEndUrl), handler: recordEnd)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.checkMapResponse), handler: returnMappedIfAny)
                await server.appendRoute(HTTPRoute(stringLiteral: Constants.overridenRequest), handler: overridenRequestHandler)
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

    @MainActor
    func reloadLocalAddress() {
        let ipAddr = IPFinder.getIPAddress() ?? "localhost"
        listeningAddress = "http://\(ipAddr):\(Constants.localBaseUrlPort)"
    }

    /// The library seals every body it sends, so nothing readable crosses the
    /// network. A body that will not open is from a build carrying a different
    /// `Constants.sharedKey` — the app and the library have to ship together.
    private static func decode<T: Decodable>(_ type: T.Type, from body: Data) throws -> T {
        guard let plain = LocalCrypto.open(body) else {
            throw LocalServerError.undecryptableBody
        }
        return try JSONDecoder().decode(type, from: plain)
    }

    lazy var recordBegin: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await Self.decode(URLTaskModelBegin.self, from: req.bodyData)
        // Dropped here rather than hidden in the list: a filtered call is never
        // written, so it costs no row, no file on disk and no redraw. The app
        // is told everything is fine — whether the mapper kept the record is
        // not its business, and a failure would only make it retry.
        guard Utils.recordFilters.allows(url: obj.url) else {
            return HTTPResponse(statusCode: .ok)
        }
        try self.db.recordBegin(task: obj)
        return HTTPResponse(statusCode: .ok)
    }

    lazy var recordUpdate: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await Self.decode(URLTaskModelUpdate.self, from: req.bodyData)
        // Checked against the rewritten url, which is the one the call actually
        // used. `recordUpdate` inserts when the row is missing — it races with
        // `recordBegin` — so without this a filtered call could still appear.
        guard Utils.recordFilters.allows(url: obj.url) else {
            return HTTPResponse(statusCode: .ok)
        }
        try self.db.recordUpdate(task: obj)
        return HTTPResponse(statusCode: .ok)
    }

    /// Not filtered: the payload carries no url to filter on, and it does not
    /// need one — `recordEnd` only finishes a row that already exists, so a
    /// call whose start was dropped has nothing here to find.
    lazy var recordEnd: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await Self.decode(URLTaskModelEnd.self, from: req.bodyData)
        try self.db.recordEnd(task: obj)
        return HTTPResponse(statusCode: .ok)
    }

    lazy var returnMappedIfAny: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        let obj = try await Self.decode(MapCheckRequest.self, from: req.bodyData)
        if let result = try self.db.getLocalMapIfAvailable(req: obj), !result.isEmpty {
            // Waited out here rather than on the client: the app blocks on this
            // check before it sends or serves anything, so holding the answer
            // is what makes the call itself look slow. Only requests a rule
            // matched are held — everything else is answered straight away.
            let delayMs = Utils.mapDelayMs
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
            guard let data = LocalCrypto.seal(try JSONEncoder().encode(result)) else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return HTTPResponse(statusCode: .ok, body: data)
        } else {
            return HTTPResponse(statusCode: .noContent)
        }
    }

    lazy var overridenRequestHandler: (@Sendable (HTTPRequest) async throws -> HTTPResponse) = { req in
        do {
            if let id = req.query["id"], let obj = try self.db.getLocalMap(id: id) {

                // Resolved as the response is served, so `{{timestamp}}` in a
                // canned body is the time the app receives it.
                var resolver = TemplateResolver()
                let body = resolver.resolve(obj.resString).data(using: .utf8) ?? Data()
                let statusCode = Int(obj.statusCode) ?? 0
                var resHeaders = [HTTPHeader: String]()
                obj.resHeadersMap.forEach { resHeaders[HTTPHeader($0.key)] = resolver.resolve($0.value) }
                resHeaders[HTTPHeader(Self.isEditedKey)] = "1"
                // Set last, so these win over anything the rule declares — the
                // rule editor tells the user as much.
                resHeaders[HTTPHeader(Constants.contentLengthKey)] = "\(body.count)"
                resHeaders[HTTPHeader(Constants.contentTypeKey)] = "application/json; charset=utf-8"

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

