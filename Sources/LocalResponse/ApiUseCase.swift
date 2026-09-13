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

    /// The rule lookup blocks on the mapper for as long as a matching rule's
    /// delay says, so it can't share the short-timeout session the record calls
    /// use — that one would cancel the lookup mid-delay and the request would
    /// go out unmapped.
    private lazy var mapCheckSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.mapCheckTimeout
        config.timeoutIntervalForResource = Constants.mapCheckTimeout
        return URLSession(configuration: config)
    }()

    /// Every body sent to the mapper goes through here, so this is the one
    /// place the payload is encrypted — see `LocalCrypto`.
    private func toData(from: Encodable) -> Data? {
        do {
            return LocalCrypto.seal(try JSONEncoder().encode(from))
        } catch let e {
            Logger.debugPrint("\(e)")
        }
        return nil
    }

    /// Encodes without going through `toData`, which seals its output — the
    /// point of this one is readable json.
    private func toString(from: Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(from) else { return nil }
        return String(data: data, encoding: .utf8)
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

    /// Reports the request a `modifyRequest` rule just rewrote. `recordBegin`
    /// has usually already reported the untouched one — its POST goes out while
    /// the rule lookup is still in flight — so this is an update to that record,
    /// not a second call.
    func recordUpdate(task: URLSessionTask, request: URLRequest) {
        let model = URLTaskModelUpdate(task: task, request: request)
        var req = createURLRequest(endpoint: Constants.recordUpdateUrl)
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

        if taskIdResponse[task.uniqueId] == nil {
            taskIdResponse[task.uniqueId] = ResponseBean()
        }
        // Mutate in place so we don't copy the whole accumulated buffer on each chunk.
        taskIdResponse[task.uniqueId]?.data.append(data)
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

    /// Asks the mapper what applies to this request: request edits, a canned
    /// response, or both. `nil` means no rule matched.
    func checkIfLocalMapResponseAvailable(data: MapCheckRequest, completion: @escaping (MapCheckResponse?) -> Void) {

        var req = createURLRequest(endpoint: Constants.checkMapResponse)
        req.httpBody = toData(from: data)

        self.mapCheckSession.dataTask(with: req) { data, res, err in
            var result: MapCheckResponse?
            var error: Error?

            if let data, !data.isEmpty {
                do {
                    guard let plain = LocalCrypto.open(data) else {
                        throw NSError(domain: "could not decrypt map check response", code: -1)
                    }
                    result = try JSONDecoder().decode(MapCheckResponse.self, from: plain)
                } catch let e {
                    error = e
                }
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
