//
//  URLTaskObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import GRDB
import SwiftUI

/// One recorded call. A reference type rather than a struct so the derived
/// values below — the parsed header pairs, the cached image — are computed once
/// per row and not once per redraw; rows are re-fetched from the database
/// rather than mutated in place, so nothing is shared between threads.
final class URLTaskObject: Codable, Identifiable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "urlTask"

    var id: String { taskId }
    var date: Double = Date().timeIntervalSince1970
    var taskId: String = ""
    var startTime: Double = 0
    var url: String = ""
    var body: String = ""
    var method: String = ""
    var bundleID: String = ""
    var reqHeaders: [String: String] = [:]
    var mimeType: String = ""

    // after response
    var endTime: Double = 0
    var responseString: String = ""
    var resHeaders: [String: String] = [:]
    var statusCode: Int = 0
    var isEdited: Bool = false

    /// A `modifyRequest` rule rewrote this call on its way out, so the request
    /// shown here is not the one the app built.
    var isRequestEdited: Bool = false

    /// Only the stored columns. The `lazy` caches further down are stored
    /// properties too, and without this list they would be written to the
    /// database along with the real ones.
    enum CodingKeys: String, CodingKey {
        case date, taskId, startTime, url, body, method, bundleID, reqHeaders
        case mimeType, endTime, responseString, resHeaders, statusCode
        case isEdited, isRequestEdited
    }

    init(taskId: String) {
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
        new.isRequestEdited = isRequestEdited
        return new
    }

    func updateFrom(task: URLTaskModelBegin) {
        startTime = task.startTime ?? 0
        bundleID = task.bundleID ?? ""
        // Both records are posted from the client at nearly the same moment and
        // can land either way round. The edited request is the one that goes on
        // the wire, so once it has arrived, begin no longer overwrites it.
        guard !isRequestEdited else {
            // Except the body: `URLRequest.httpBody` is nil for a task built
            // from a stream or an upload, so begin may carry the only copy.
            if body.isEmpty {
                body = (try? Utils.prettyPrintJSON(from: task.body ?? "")) ?? task.body ?? ""
            }
            return
        }
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = (try? Utils.prettyPrintJSON(from: task.body ?? "")) ?? task.body ?? ""
    }

    /// The request after a rule rewrote it. Headers are replaced rather than
    /// merged: the client sends the full set it is about to put on the wire.
    func updateFrom(task: URLTaskModelUpdate) {
        isRequestEdited = true
        bundleID = task.bundleID ?? bundleID
        url = task.url
        method = task.method
        reqHeaders.removeAll()
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        if let taskBody = task.body {
            body = (try? Utils.prettyPrintJSON(from: taskBody)) ?? taskBody
        }
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
    //
    // Kept as pairs rather than one joined string: the detail pane collapses
    // oversized values per line, so it needs them separately.
    lazy var getQuery: [KeyValuePair] = {
        Utils.dictToPairs(item: Utils.getQueryParams(url))
    }()

    lazy var getReqHeaders: [KeyValuePair] = {
        Utils.dictToPairs(item: reqHeaders)
    }()

    lazy var getResHeaders: [KeyValuePair] = {
        Utils.dictToPairs(item: resHeaders)
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

    // Reused across every row/render — allocating a NumberFormatter per call is expensive.
    private static let timeDelayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var timeDelay: String {
        let diff = endTime - startTime
        guard diff > 0, let str = Self.timeDelayFormatter.string(from: NSNumber(value: diff)) else {
            return ""
        }
        return str
    }
}
