import UniformTypeIdentifiers

enum ContentType {
    case text
    case image
    case audio
    case video
    case pdf
    case form
    case binary
    case unknown

    init(fromMimeType string: String) {
        let type = string
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch type {
        case "text/plain", "text/html", "text/css", "text/markdown",
             "text/xml", "application/xml", "application/xhtml+xml",
             "application/json", "application/ld+json", "application/vnd.api+json",
             "application/javascript", "text/javascript",
             "application/rss+xml", "application/atom+xml":
            self = .text
        case "application/x-www-form-urlencoded", "multipart/form-data":
            self = .form
        case "application/pdf":
            self = .pdf
        case "application/octet-stream", "application/zip",
             "application/vnd.ms-excel",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            self = .binary
        case let s where s.hasPrefix("image/"):
            self = .image
        case let s where s.hasPrefix("audio/"):
            self = .audio
        case let s where s.hasPrefix("video/"):
            self = .video
        default:
            self = .unknown
        }
    }

    init(fromExtension ext: String) {
        let ext = ext.lowercased()
        switch ext {
        case "txt", "html", "htm", "css", "md", "xml", "json", "js", "rss", "atom":
            self = .text
        case "pdf":
            self = .pdf
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg":
            self = .image
        case "mp3", "wav", "m4a", "aac", "ogg", "flac":
            self = .audio
        case "mp4", "mov", "avi", "mkv", "webm":
            self = .video
        case "zip", "bin", "exe", "dmg", "pkg":
            self = .binary
        default:
            self = .unknown
        }
    }
}

