//
//  LocalData.swift
//  Swift-sample
//
//  Created by Chandan on 14/08/24.
//

import Foundation

public class LocalResponse {
    private static var localDirPath: String?
    private static var injector: Injector = NetworkInjector()
    public static let shared = LocalResponse()

    private let useCase = ApiUseCase()

    private init() {
        Self.injector.delegate = self
    }

    public func inject(path: String) {
        LocalResponse.localDirPath = path
        LocalResponse.injector.injectAllNetworkClasses(config: NetworkConfiguration())
    }

    func createURLRequest(endpoint: String) -> URLRequest {
        let method = String(endpoint.split(separator: " ").first!)
        let endPoint = String(endpoint.split(separator: " ").last!)
        let url = URL(string: Constants.localBaseUrl + endPoint)!
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

    func isLocalServer(task: URLSessionTask) -> Bool {
        let url = task.currentRequest?.url?.absoluteString ?? ""
        return url.contains(Constants.localBaseUrl)
    }
}

extension LocalResponse: InjectorDelegate {

    func injectorSessionOverrideResume(task: URLSessionTask, completion: @escaping () -> Void) {
        Logger.debugPrint(task.currentRequest?.url?.absoluteString ?? "")
        if useCase.isLocalServer(task: task) {
            completion()
            return
        }

        let data = MapCheckRequest(url: task.currentRequest?.url?.absoluteString ?? "",
                                   method: task.currentRequest?.httpMethod ?? "")
        LocalResponse.shared.useCase.checkIfLocalMapResponseAvailable(data: data) { map in
            do {
                if let map {
                    var req = self.createURLRequest(endpoint: Constants.overridenRequest)
                    req.httpBody = try? JSONEncoder().encode(map)
                    task.setValue(req, forKey: "currentRequest")
                }
            } catch let e {
                Logger.debugPrint("\(e)")
            }
            completion()
        }
    }

    func injectorSessionDidCallResume(task: URLSessionTask) {
        Logger.debugPrint(task.currentRequest?.url?.absoluteString ?? "")
        if useCase.isLocalServer(task: task) { return }
        Logger.debugPrint(#function)

        // record completion of the request
        useCase.recordBegin(task: task)
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        if useCase.isLocalServer(task: dataTask) { return }
        Logger.debugPrint(#function)

        // record when received response, data yet to come
        useCase.recordReceivedResponse(task: dataTask, response: response)
    }

    func injectorSessionDidReceiveData(dataTask: URLSessionTask, data: Data) {
        if useCase.isLocalServer(task: dataTask) { return }
        Logger.debugPrint(#function)

        // record completion of the request with data
        useCase.recordComplete(task: dataTask, data: data)
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: (any Error)?) {
        if useCase.isLocalServer(task: task) { return }
        Logger.debugPrint(#function)

        // record completion of the request with error
        useCase.recordWithError(task: task, error: error)
    }

    func injectorSessionDidUpload(task: URLSessionTask, request: NSURLRequest, data: Data?) {
        Logger.debugPrint(#function)
    }

    func injectorSessionWebSocketDidSendMessage(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        Logger.debugPrint(#function)
    }

    func injectorSessionWebSocketDidReceive(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        Logger.debugPrint(#function)
    }

    func injectorSessionWebSocketDidSendPingPong(task: URLSessionTask) {
        Logger.debugPrint(#function)
    }

    func injectorSessionWebSocketDidSendCancelWithReason(task: URLSessionTask, closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Logger.debugPrint(#function)
    }
}

