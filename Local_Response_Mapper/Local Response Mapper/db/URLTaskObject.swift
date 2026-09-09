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

    /// This row's own identity, given once and never changed — the table is
    /// keyed on it, so a row that re-keys is a row the list has to throw away
    /// and build again.
    var taskId: String = ""

    /// What the client calls this call while it is in flight, used to find the
    /// row again when its update and its response arrive.
    ///
    /// It is the address of the client's `URLSessionTask` plus that task's
    /// identifier, and an address is handed out again once the task that held
    /// it is gone. Cleared when the response lands, so a later call landing on
    /// the same address cannot find this finished row.
    var liveKey: String = ""
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
        case date, taskId, liveKey, startTime, url, body, method, bundleID, reqHeaders
        case mimeType, endTime, responseString, resHeaders, statusCode
        case isEdited, isRequestEdited
    }

    init(taskId: String) {
        self.taskId = taskId
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
                body = task.body ?? ""
            }
            return
        }
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = task.body ?? ""
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
            body = taskBody
        }
    }

    func updateFrom(task: URLTaskModelEnd) {
        endTime = task.endTime ?? 0
        bundleID = task.bundleID ?? ""
        task.resHeaders?.forEach { resHeaders[$0.key] = $0.value }
        responseString = task.resString ?? ""
        statusCode = task.statusCode ?? 0
        isEdited = resHeaders[LocalServer.isEditedKey] == "1"
        resHeaders[LocalServer.isEditedKey] = nil
        mimeType = task.mimeType ?? ""
    }

    /// The file a non-text response is kept in, and what goes in it — or `nil`
    /// when the body is text and belongs in the row itself.
    ///
    /// Separate from `updateFrom` so the write can happen outside the database
    /// transaction: an image or a video is written a page at a time, and doing
    /// that while the writer lock is held stops every other recorded call for
    /// as long as it takes.
    func pendingFile(for task: URLTaskModelEnd) -> (url: URL, data: Data)? {
        guard
            let data = Data(base64Encoded: task.resStringB64 ?? ""),
            contentType != .text,
            let path = fileURL
        else {
            return nil
        }
        return (path, data)
    }

    /// Written atomically: the pane can be asked to reload while this is still
    /// running, and a half-written file read at that moment would be cached as a
    /// broken one. With `.atomic` the path either holds the previous file or the
    /// finished one, never part of it.
    static func writeResponseFile(at url: URL, data: Data) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.debugPrint("Could not save response body: \(error)")
        }
    }

    /// Whether this record still says what the list row says.
    ///
    /// Only the columns a recorded call can change after it is first written;
    /// the rest are set once. Used to keep a cached record — and the laid-out
    /// bodies hanging off it — across a refresh that did not touch it.
    func matches(_ row: URLTaskRow) -> Bool {
        taskId == row.taskId
            && statusCode == row.statusCode
            && endTime == row.endTime
            && startTime == row.startTime
            && date == row.date
            && url == row.url
            && method == row.method
            && mimeType == row.mimeType
            && isEdited == row.isEdited
            && isRequestEdited == row.isRequestEdited
    }

    /// Bodies are stored exactly as they went over the wire and laid out only
    /// when something shows one.
    ///
    /// Pretty-printing parses and re-serializes the whole body, and it used to
    /// happen inside the write that records the call — so a flood paid for it
    /// on every request, on the connection's own queue, for bodies nothing ever
    /// opened. One row is on screen at a time; this is that row's copy.
    lazy var prettyBody: String = {
        (try? Utils.prettyPrintJSON(from: body)).flatMap { $0 } ?? body
    }()

    lazy var prettyResponseString: String = {
        (try? Utils.prettyPrintJSON(from: responseString)).flatMap { $0 } ?? responseString
    }()

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
