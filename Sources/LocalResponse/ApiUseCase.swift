//
//  File.swift
//
//
//  Created by Chandan on 20/08/24.
//

import Foundation

class ApiUseCase {

    private struct ResponseBean {
        var response: HTTPURLResponse?
        var data = Data()
    }

    private let lock = NSLock()
    private var taskIdResponse = [String: ResponseBean]()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

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

    private func createURLRequest(endpoint: String) -> URLRequest {
        let method = String(endpoint.split(separator: " ").first!)
        let endPoint = String(endpoint.split(separator: " ").last!)
        let url = URL(string: LocalResponse.shared.connectionUrl + endPoint)!
        var req = URLRequest(url: url)
        req.httpMethod = String(method)
        return req
    }

    func recordBegin(task: URLSessionTask) {
        let model = URLTaskModelBegin(task: task)
        var req = createURLRequest(endpoint: Constants.recordBeginUrl)
        req.httpBody = toData(from: model)
        session.dataTask(with: req).resume()
    }

    func recordReceivedResponse(task: URLSessionTask, response: URLResponse) {
        lock.lock()
        defer { lock.unlock() }
        
        taskIdResponse[task.uniqueId] = ResponseBean(response: response as? HTTPURLResponse)
    }

    func recordComplete(task: URLSessionTask, data: Data) {
        lock.lock()
        defer { lock.unlock() }

        var stored = taskIdResponse[task.uniqueId] ?? ResponseBean()
        stored.data.append(data)
        taskIdResponse[task.uniqueId] = stored
    }

    func recordWithError(task: URLSessionTask, error: Error?) {
        lock.lock()
        defer { lock.unlock() }

        let res = taskIdResponse[task.uniqueId]
        let data = taskIdResponse[task.uniqueId]?.data
        let model = URLTaskModelEnd(task: task, response: res?.response, responseData: data, err: error?.localizedDescription)
        var req = createURLRequest(endpoint: Constants.recordEndUrl)
        req.httpBody = toData(from: model)
        session.dataTask(with: req).resume()

        taskIdResponse[task.uniqueId] = nil
    }

    func checkIfLocalMapResponseAvailable(data: MapCheckRequest, completion: @escaping (String?) -> Void) {

        var req = createURLRequest(endpoint: Constants.checkMapResponse)
        req.httpBody = toData(from: data)

        self.session.dataTask(with: req) { data, res, err in
            var result: String?
            var error: Error?

            if let data, let id = String(data: data, encoding: .utf8), !id.isEmpty {
                result = id
            } else {
                error = err ?? NSError(domain: "data is nil", code: -1)
            }

            if let error {
                Logger.debugPrint("\(error)")
            }
            completion(result)
        }
        .resume()
    }
}
