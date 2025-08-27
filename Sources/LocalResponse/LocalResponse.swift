//
//  LocalData.swift
//  Swift-sample
//
//  Created by Chandan on 14/08/24.
//

import Foundation
import Network

public class LocalResponse {
    static let shared = LocalResponse()

    var connectionUrl: String = Constants.localBaseUrl
    private var injector: Injector = NetworkInjector()
    private let useCase = ApiUseCase()
    private var excludes: [String] = []
    private let bonjourClient = BonjourClient()

    private init() {
        injector.delegate = self
    }

    public static func connect(connectionUrl: String? = nil, excludes: [String] = []) {
        shared.connect(connectionUrl: connectionUrl, excludes: excludes)
        shared.bonjourClient.setOnUpdate { url in
            LocalResponse.shared.connectionUrl = url
        }
        shared.bonjourClient.startBrowsing()
    }

    private func connect(connectionUrl: String?, excludes: [String]) {
        LocalResponse.shared.connectionUrl = connectionUrl ?? Constants.localBaseUrl
        if URL(string: LocalResponse.shared.connectionUrl) == nil {
            assertionFailure("LocalResponse> Bad url! \(connectionUrl ?? "nil")")
        }
        LocalResponse.shared.injector.injectAllNetworkClasses(config: NetworkConfiguration())
        self.excludes = excludes
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
        LocalResponse.shared.useCase.checkIfLocalMapResponseAvailable(data: data) { id in
            if let id {
                var req = self.createURLRequest(endpoint: Constants.overridenRequest)
                var comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: true)
                comps?.queryItems = [URLQueryItem(name: "id", value: id)]
                req.url = comps?.url
                task.setValue(req, forKey: "currentRequest")
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

final class BonjourClient {
    private var browser: NWBrowser?

    private var onUpdate: ((String) -> Void)?

    func setOnUpdate(callback: @escaping (String) -> Void) {
        onUpdate = callback
    }

    func startBrowsing() {
        // Look for HTTP services advertised with Bonjour
        let parameters = NWParameters.tcp
        browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local."), using: parameters)

        browser?.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("Browser ready")
            case .failed(let error):
                print("Browser failed with error: \(error)")
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { results, changes in
            for result in results {
                switch result.endpoint {
                case let .service(name: name, type: type, domain: domain, interface: _):
                    print("Found service: \(name) (\(type)) in \(domain)")

                    // Resolve connection
                    let connection = NWConnection(to: result.endpoint, using: parameters)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            print("Resolved service \(name) to: \(connection.endpoint)")
                        case .failed(let error):
                            print("Failed to connect: \(error)")
                        default:
                            break
                        }
                    }
                    connection.start(queue: .main)

                default:
                    break
                }
            }
        }

        browser?.start(queue: .main)
    }
}
