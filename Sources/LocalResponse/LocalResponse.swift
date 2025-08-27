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
    private let bonjourClient = BonjourClient()

    private init() {
        injector.delegate = self
    }

    public static func connect(connectionUrl: String? = nil, excludes: [String] = []) {
        shared.connect(connectionUrl: connectionUrl, excludes: excludes)
        shared.bonjourClient.startBrowsing()
        shared.bonjourClient.setOnUpdate { url in
            LocalResponse.shared.connectionUrl = url
        }
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

class BonjourClient: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    let browser = NetServiceBrowser()
    var services: [NetService] = []

    private var onUpdate: ((String) -> Void)?

    override init() {
        super.init()
        browser.delegate = self
    }

    func setOnUpdate(callback: @escaping (String) -> Void) {
        onUpdate = callback
    }

    func startBrowsing() {
        // Look for services of type "_myapp._tcp."
        browser.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
    }

    // Found a service
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    // Resolved to hostname + IP
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let addresses = sender.addresses {
            for addrData in addresses {
                let ip = addrData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> String? in
                    let sockaddrPtr = pointer.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                    if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                        var addr = sockaddr_in()
                        memcpy(&addr, sockaddrPtr, MemoryLayout<sockaddr_in>.size)
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                        return String(cString: buffer)
                    }
                    return nil
                }
                if let ip = ip {
                    onUpdate?("http://\(ip):\(sender.port)")
                }
            }
        }
    }
}
