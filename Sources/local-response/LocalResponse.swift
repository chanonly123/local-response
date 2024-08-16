//
//  LocalData.swift
//  Swift-sample
//
//  Created by Chandan on 14/08/24.
//

import Foundation

class LocalResponse {
    private static var localDirPath: String?
    private static var injector: Injector = NetworkInjector()
    public static let shared = LocalResponse()
    
    private init() {
        Self.injector.delegate = self
    }
    
    private var taskIdResponse = [Int: HTTPURLResponse]()
    
    public func inject(path: String) {
        LocalResponse.localDirPath = path
        LocalResponse.injector.injectAllNetworkClasses(config: NetworkConfiguration())
    }
    
    static func debugPrint(_ msg: String) {
        print("local-response> \(msg)")
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
            LocalResponse.debugPrint("\(e)")
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
    func injectorSessionDidCallResume(task: URLSessionTask) {
        if isLocalServer(task: task) { return }
        LocalResponse.debugPrint(#function)
        let model = URLTaskModel(task: task, finished: false, response: nil, data: nil, err: nil)
        var req = createURLRequest(endpoint: Constants.recordBeginUrl)
        req.httpBody = toData(from: model)
        print(toString(from: model) ?? "")
        let task = URLSession.shared.dataTask(with: req) { _, _, err in
            print("Complete \(err)")
        }
        task.resume()
    }
    
    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        if isLocalServer(task: dataTask) { return }
        LocalResponse.debugPrint(#function)
        taskIdResponse[dataTask.taskIdentifier] = response as? HTTPURLResponse
    }
    
    func injectorSessionDidReceiveData(dataTask: URLSessionTask, data: Data) {
        if isLocalServer(task: dataTask) { return }
        LocalResponse.debugPrint(#function)
        let res = taskIdResponse[dataTask.taskIdentifier]
        let model = URLTaskModel(task: dataTask, finished: true, response: res, data: data, err: nil)
        var req = createURLRequest(endpoint: Constants.recordEndUrl)
        req.httpBody = toData(from: model)
        let task = URLSession.shared.dataTask(with: req) { _, _, err in
            print("Complete \(err)")
        }
        task.resume()
    }
    
    func injectorSessionDidComplete(task: URLSessionTask, error: (any Error)?) {
        let model = URLTaskModel(task: task, finished: true, response: nil, data: nil, err: error?.localizedDescription ?? "Unknown error")
        var req = createURLRequest(endpoint: Constants.recordEndUrl)
        req.httpBody = toData(from: model)
        URLSession.shared.dataTask(with: req)
        LocalResponse.debugPrint(#function)
    }
    
    func injectorSessionDidUpload(task: URLSessionTask, request: NSURLRequest, data: Data?) {
        LocalResponse.debugPrint(#function)
    }
    
    func injectorSessionWebSocketDidSendMessage(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        LocalResponse.debugPrint(#function)
    }
    
    func injectorSessionWebSocketDidReceive(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        LocalResponse.debugPrint(#function)
    }
    
    func injectorSessionWebSocketDidSendPingPong(task: URLSessionTask) {
        LocalResponse.debugPrint(#function)
    }
    
    func injectorSessionWebSocketDidSendCancelWithReason(task: URLSessionTask, closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        LocalResponse.debugPrint(#function)
    }
}
