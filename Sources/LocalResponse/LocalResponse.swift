//
//  LocalData.swift
//  Swift-sample
//
//  Created by Chandan on 14/08/24.
//

import Foundation

public class LocalResponse {
    static let shared = LocalResponse()

    var connectionUrl: String = Constants.localBaseUrl
    private var injector: Injector = NetworkInjector()
    private let useCase = ApiUseCase()
    private var excludes: [String] = []

    private init() {
        injector.delegate = self
    }

    public static func connect(connectionUrl: String? = nil, excludes: [String] = []) {
        // Swizzle synchronously so requests fired immediately after this call are intercepted.
        shared.injector.injectAllNetworkClasses(config: NetworkConfiguration())
        shared.excludes = excludes
        // Resolve the actual server URL asynchronously (needs a network check for simulator vs device).
        Task {
            await shared.resolveConnectionUrl(connectionUrl: connectionUrl)
        }
    }

    private func resolveConnectionUrl(connectionUrl: String?) async {
        if await IPFinder.isServerRunning(urlString: Constants.localBaseUrl) {
            LocalResponse.shared.connectionUrl = Constants.localBaseUrl
        } else {
            LocalResponse.shared.connectionUrl = connectionUrl ?? Constants.localBaseUrl
        }

        if URL(string: LocalResponse.shared.connectionUrl) == nil {
            assertionFailure("❌ LocalResponse> Bad url! \(connectionUrl ?? "nil")")
        }
    }

    private func createURLRequest(endpoint: String) -> URLRequest {
        let method = String(endpoint.split(separator: " ").first!)
        let endPoint = String(endpoint.split(separator: " ").last!)
        let url = URL(string: connectionUrl + endPoint)!
        var req = URLRequest(url: url)
        req.httpMethod = String(method)
        return req
    }

    private func toData(from: Encodable) -> Data? {
        do {
            return try JSONEncoder().encode(from)
        } catch let e {
            Logger.debugPrint("\(e)")
        }
        return nil
    }

    private func toString(from: Encodable) -> String? {
        if let data = toData(from: from) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func shouldIgnoreTask(task: URLSessionTask) -> Bool {
        let url = task.currentRequest?.url?.absoluteString ?? ""
        if url.contains("overriden-request") {
            return false
        }
        return url.contains(connectionUrl) || excludes.contains { url.contains($0) }
    }
}

extension LocalResponse: InjectorDelegate {

    func injectorSessionOverrideResume(task: URLSessionTask, completion: @escaping () -> Void) {
        if shouldIgnoreTask(task: task) {
            completion()
            return
        }

        let data = MapCheckRequest(url: task.currentRequest?.url?.absoluteString ?? "",
                                   method: task.currentRequest?.httpMethod ?? "")
        LocalResponse.shared.useCase.checkIfLocalMapResponseAvailable(data: data) { result in
            if let result {
                // Edits go on first: they describe the request as the app would
                // have sent it, and a mapped response then replaces that request
                // wholesale.
                self.applyRequestChanges(result, to: task)

                if let id = result.overrideId {
                    var req = self.createURLRequest(endpoint: Constants.overridenRequest)
                    var comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: true)
                    comps?.queryItems = [URLQueryItem(name: "id", value: id)]
                    req.url = comps?.url
                    task.setValue(req, forKey: "currentRequest")
                }
            }

            completion()
        }
    }

    /// Applies a `modifyRequest` rule to the request the task is about to send.
    /// It runs before `resume` reaches the original implementation, which is the
    /// last point at which `currentRequest` still decides what goes on the wire.
    private func applyRequestChanges(_ changes: MapCheckResponse, to task: URLSessionTask) {
        guard changes.changesRequest, var req = task.currentRequest else { return }

        changes.reqHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let body = changes.reqBody {
            let data = Data(body.utf8)
            req.httpBody = data
            req.setValue("\(data.count)", forHTTPHeaderField: Constants.contentLengthKey)
        }

        task.setValue(req, forKey: "currentRequest")

        // Recorded from `req` rather than re-reading the task: this is exactly
        // what was written, whether or not URLSession keeps every field.
        useCase.recordUpdate(task: task, request: req)
    }

    func injectorSessionDidCallResume(task: URLSessionTask) {
        if shouldIgnoreTask(task: task) { return }
        Logger.debugPrint(#function)

        // record completion of the request
        useCase.recordBegin(task: task)
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        if shouldIgnoreTask(task: dataTask) { return }
        Logger.debugPrint(#function)

        // record when received response, data yet to come
        useCase.recordReceivedResponse(task: dataTask, response: response)
    }

    func injectorSessionDidReceiveData(dataTask: URLSessionTask, data: Data) {
        if shouldIgnoreTask(task: dataTask) { return }
        Logger.debugPrint(#function)

        // record completion of the request with data
        useCase.recordComplete(task: dataTask, data: data)
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: (any Error)?) {
        if shouldIgnoreTask(task: task) { return }
        Logger.debugPrint(#function)

        // record completion of the request with error
        useCase.recordWithError(task: task, error: error)
    }

    func injectorSessionDidUpload(task: URLSessionTask, request: NSURLRequest, data: Data?) {

    }

    func injectorSessionWebSocketDidSendMessage(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {

    }

    func injectorSessionWebSocketDidReceive(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {

    }

    func injectorSessionWebSocketDidSendPingPong(task: URLSessionTask) {

    }

    func injectorSessionWebSocketDidSendCancelWithReason(task: URLSessionTask, closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {

    }
}

