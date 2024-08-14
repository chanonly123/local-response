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
    
    private init() {}
    
    public static func inject(path: String) {
        LocalResponse.localDirPath = path
        LocalResponse.injector.injectAllNetworkClasses(config: NetworkConfiguration())
    }
    
    static func debugPrint(_ msg: String) {
        print("local-response: \(msg)")
    }
    
    static func find(task: URLSessionTask) -> Data? {
        do {
            let dir = localDirPath ?? ""
            let exists = FileManager.default.fileExists(atPath: dir)
            if !exists {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            
            let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            for file in files {
                let fileContent = try String(contentsOfFile: "\(dir)/\(file)")
                var comps = fileContent.split(separator: "\n")
                
                var url: String?
                var method: String?
                
                guard let firstLine = comps.first, firstLine.replacingOccurrences(of: " ", with: "").starts(with: "enable:true") else {
                    continue
                }
                
                if let comp = comps.first(where: { $0.starts(with: "url:") }), let last = String(comp).split(separator: ":", omittingEmptySubsequences: true).last {
                    url = String(last).trimmingCharacters(in: .whitespaces)
                } else {
                    LocalResponse.debugPrint("Wrong file structure (url: missing): \(file)")
                    continue
                }
                
                if let comp = comps.first(where: { $0.starts(with: "method:") }) {
                    if let last = String(comp).split(separator: ":", omittingEmptySubsequences: true).last {
                        method = String(last).trimmingCharacters(in: .whitespaces)
                    }
                }
                
                if let url, task.originalRequest?.url?.absoluteString.contains(url) ?? false,
                   let method, task.originalRequest?.httpMethod?.lowercased() == method.lowercased()  {
                    if let index = comps.firstIndex(where: { $0.starts(with: "response:") }) {
                        comps.removeFirst(index)
                        
                        var finalComps = comps.joined(separator: "\n").split(separator: ":")
                        finalComps.removeFirst()
                        let res = finalComps.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                        return res.data(using: .utf8)
                    } else {
                        LocalResponse.debugPrint("Wrong file structure (response: missing): \(file)")
                    }
                }
            }
        } catch let err {
            LocalResponse.debugPrint("\(err)")
        }
        return nil
    }
}
