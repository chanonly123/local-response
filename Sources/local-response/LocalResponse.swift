//
//  LocalData.swift
//  Swift-sample
//
//  Created by Chandan on 14/08/24.
//

import Foundation

public class LocalResponse {
    public static let shared = LocalResponse()

    private var connectionUrl: String = Constants.localBaseUrl
    private var injector: Injector = NetworkInjector()
    private let useCase = ApiUseCase()
    private var excludes: [String] = []

    private init() {
        injector.delegate = self
    }

    public func connect(connectionUrl: String? = nil, excludes: [String] = []) {
        LocalResponse.shared.connectionUrl = connectionUrl ?? Constants.localBaseUrl
        LocalResponse.shared.injector.injectAllNetworkClasses(config: NetworkConfiguration())
        self.excludes = excludes
    }

    func createURLRequest(endpoint: String) -> URLRequest {
        let method = String(endpoint.split(separator: " ").first!)
        let endPoint = String(endpoint.split(separator: " ").last!)
        let url = URL(string: connectionUrl + endPoint)!
        var req = URLRequest(url: url)
        req.httpMethod = String(method)
        return req
    }

    func toData(from: Encodable) -> Data? {
        do {
            return try JSONEncoder().encode(from)
        } catch let e {
            Logger.debugPrint("\(e)")
        }
        return nil
    }

    func toString(from: Encodable) -> String? {
        if let data = toData(from: from) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    func shouldIgnoreTask(task: URLSessionTask) -> Bool {
        let url = task.currentRequest?.url?.absoluteString ?? ""
        if url.contains("overriden-request") {
            return false
        }
        return url.contains(Constants.localBaseUrl) || excludes.contains { url.contains($0) }
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
        LocalResponse.shared.useCase.checkIfLocalMapResponseAvailable(data: data) { id in
            do {
                if let id {
                    var req = self.createURLRequest(endpoint: Constants.overridenRequest)
                    var comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: true)
                    comps?.queryItems = [URLQueryItem(name: "id", value: id)]
                    req.url = comps?.url
                    task.setValue(req, forKey: "currentRequest")
                }
            } catch let e {
                Logger.debugPrint("\(e)")
            }
            completion()
        }
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

