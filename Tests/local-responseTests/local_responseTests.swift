import XCTest
@testable import LocalResponse

final class local_responseTests: XCTestCase {
    
    var obs: Any?
    
    func testExample() async throws {
        LocalResponse.shared.connect()
        
        let url = "https://gist.githubusercontent.com/qb-mithuns/4160386/raw/13ff411a17e2cd558804d98da241d6f711c6c57a/Sample%2520Response"
        let sess = URLSession.shared
        
        let e1 = expectation(description: "1")
        obs = sess.dataTaskPublisher(for: URL(string: url)!)
            .tryMap { (data: Data, response: URLResponse) in
                if let resString = String(data: data, encoding: .utf8) {
                    return resString
                }
                throw NSError(domain: "wrong!!!", code: -1)
            }
            .sink(receiveCompletion: { error in
            }, receiveValue: { val in
                Logger.debugPrint("res1: \(val)")
                e1.fulfill()
            })
        
        await waitForExpectations(timeout: 100)
        
        try await Task.sleep(nanoseconds: UInt64(2e9))
//
//        let req = URLRequest(url: URL(string: url)!)
//        sess.dataTask(with: req) { data, res, err in
//            if let data, let resString = String(data: data, encoding: .utf8) {
//                Logger.debugPrint("res2: \(resString)")
//            } else {
//                Logger.debugPrint("res2 error: error")
//            }
//        }
//        .resume()
    }
}
