//
//  File.swift
//
//
//  Created by Chandan on 20/08/24.
//

import Foundation

class ApiUseCase {
    
    private var taskIdResponse = [String: HTTPURLResponse]()
    private var taskIdResponseData = [String: Data]()

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
        taskIdResponse[task.uniqueId] = response as? HTTPURLResponse
    }
    
    func recordComplete(task: URLSessionTask, data: Data) {
        taskIdResponseData[task.uniqueId] = data
        let res = taskIdResponse[task.uniqueId]
        let model = URLTaskModelEnd(task: task, response: res, responseData: data, err: nil)
        var req = createURLRequest(endpoint: Constants.recordEndUrl)
        req.httpBody = toData(from: model)
        session.dataTask(with: req).resume()
    }
    
    func recordWithError(task: URLSessionTask, error: Error?) {
        let res = taskIdResponse[task.uniqueId]
        let model = URLTaskModelEnd(task: task, response: res, responseData: taskIdResponseData[task.uniqueId], err: error?.localizedDescription ?? "Unknown error")
        var req = createURLRequest(endpoint: Constants.recordEndUrl)
        req.httpBody = toData(from: model)
        session.dataTask(with: req).resume()
    }
    
    func checkIfLocalMapResponseAvailable(data: MapCheckRequest, completion: @escaping (String?) -> Void) {

        var req = createURLRequest(endpoint: Constants.checkMapResponse)
        req.httpBody = toData(from: data)
        
        self.session.dataTask(with: req) { data, res, err in
            var result: String?
            var error: Error?
            
            do {
                if let data, let id = String(data: data, encoding: .utf8), !id.isEmpty {
                    result = id
                } else {
                    error = err ?? NSError(domain: "data is nil", code: -1)
                }
            } catch let e {
                error = e
            }
            
            if let error {
                Logger.debugPrint("\(error)")
            }
            completion(result)
        }
        .resume()
    }
}
