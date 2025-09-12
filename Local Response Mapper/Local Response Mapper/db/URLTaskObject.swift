//
//  URLTaskObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import RealmSwift
import SwiftUI

class URLTaskObject: Object, Identifiable {
    var id: String { taskId }
    @Persisted var date: Double = Date().timeIntervalSince1970
    @Persisted(primaryKey: true) var taskId: String
    @Persisted var startTime: Double = 0
    @Persisted var url: String = ""
    @Persisted var body: String = ""
    @Persisted var method: String = ""
    @Persisted var bundleID: String = ""
    @Persisted var reqHeaders: Map<String, String> = .init()
    @Persisted var mimeType: String = ""

    // after response
    @Persisted var endTime: Double = 0
    @Persisted var responseString: String = ""
    @Persisted var resHeaders: Map<String, String> = .init()
    @Persisted var statusCode: Int = 0
    @Persisted var isEdited: Bool = false

    convenience init(taskId: String) {
        self.init()
        self.taskId = taskId
    }

    func createCopy() -> URLTaskObject {
        let new = URLTaskObject(taskId: UUID().uuidString)
        new.date = date
        new.startTime = startTime
        new.endTime = endTime
        new.url = url
        new.body = body
        new.method = method
        new.reqHeaders = reqHeaders
        new.responseString = responseString
        new.resHeaders = resHeaders
        new.statusCode = statusCode
        new.mimeType = mimeType
        return new
    }

    func updateFrom(task: URLTaskModelBegin) {
        startTime = task.startTime ?? 0
        bundleID = task.bundleID ?? ""
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = (try? Utils.prettyPrintJSON(from: task.body ?? "")) ?? task.body ?? ""
    }

    func updateFrom(task: URLTaskModelEnd) {
        endTime = task.endTime ?? 0
        bundleID = task.bundleID ?? ""
        task.resHeaders?.forEach { resHeaders[$0.key] = $0.value }
        responseString = (try? Utils.prettyPrintJSON(from: task.resString ?? "")) ?? task.resString ?? ""
        statusCode = task.statusCode ?? 0
        isEdited = resHeaders[LocalServer.isEditedKey] == "1"
        resHeaders[LocalServer.isEditedKey] = nil
        mimeType = task.mimeType ?? ""
        if
            let data = Data(base64Encoded: task.resStringB64 ?? ""),
            contentType != .text,
            let path = fileURL
        {
            do {
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try data.write(to: path)
            } catch {
                print("Error saving video data: \(error)")
            }
        }
    }

    lazy var contentType: ContentType? = {
        Utils.determineFileExtensionAndType(from: self).type
    }()
    
    lazy var image: (Image, CGSize)? = {
        guard
            contentType == .image,
            let url = fileURL,
            let data = try? Data(contentsOf: url),
            let nsImage = NSImage(data: data)
        else {
            return nil
        }
        return (Image(nsImage: nsImage), nsImage.size)
    }()

    lazy var fileURL: URL? = {
        if contentType != .text {
            let ext = Utils.determineFileExtensionAndType(from: self).ext
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("cache/\(taskId).\(ext)")
        }
        return nil
    }()

    // cache storage
    lazy var getQuery: AttributedString = {
        Utils.dictToString(item: Utils.getQueryParams(url))
    }()

    lazy var getReqHeaders: AttributedString = {
        Utils.dictToString(item: reqHeaders)
    }()

    lazy var getResHeaders: AttributedString = {
        Utils.dictToString(item: resHeaders)
    }()

    lazy var getReqBody: AttributedString = {
        Utils.highlightJson(body)
    }()

    lazy var getHost: AttributedString = {
        Utils.getHost(url)
    }()

    lazy var getPath: AttributedString = {
        Utils.getPath(url)
    }()

    lazy var getPathString: String = {
        guard let urlObj = URL(string: url) else {
            return ""
        }
        return (urlObj.host() ?? "") + urlObj.path()
    }()

    var timeDelay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let diff = endTime - startTime
        let number = NSNumber(value: diff)
        guard diff > 0, let str = formatter.string(from: number) else {
            return ""
        }
        return str
    }
}
