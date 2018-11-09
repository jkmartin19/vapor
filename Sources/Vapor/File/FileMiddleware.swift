import Foundation
import HTTP
import libc

/// Servers files from the supplied public directory
/// on not found errors.
public final class FileMiddleware: Middleware {

    private var publicDir: String
    private let loader = DataFile()
    private let chunkSize: Int

    public init(publicDir: String, chunkSize: Int? = nil) {
        // Remove last "/" from the publicDir if present, so we can directly append uri path from the request.
        self.publicDir = publicDir.finished(with: "/")
        self.chunkSize = chunkSize ?? 32_768 // 2^15
    }

    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        if let rangeHeader = request.headers["Range"] {
            if rangeHeader.starts(with: "bytes=") {
                let rangeString = String(rangeHeader.dropFirst(6))
                let split = rangeString.split(separator: "-")
                if split.count == 2, let start = Int(split[0]), let end = Int(split[1]) {
                    var path = request.uri.path
                    guard !path.contains("../") else { throw HTTP.Status.forbidden }
                    if path.hasPrefix("/") {
                        path = String(path.toCharacterSequence().dropFirst())
                    }
                    let filePath = publicDir + path
                    if let data = NSData(contentsOfFile: filePath) {
                        let length = end - start + 1
                        if length > 0 { //}, length < data.length {
                            let retValue = data.subdata(with: NSRange(location: start, length: length))
                            let headers: [HeaderKey: String] = [
                                HeaderKey.contentLength: "\(length)",
                                HeaderKey.contentRange: "bytes \(start)-\(end)/\(data.length)",
                                HeaderKey.acceptRanges: "bytes"
                            ]
                            let response = Response(status: .partialContent, headers: headers, body: retValue)
                            return response
                        }
                    }
                }
            }
        }
        do {
            return try next.respond(to: request)
        } catch RouterError.missingRoute {
            // Check in file system
            var path = request.uri.path
            guard !path.contains("../") else { throw HTTP.Status.forbidden }
            if path.hasPrefix("/") {
                path = String(path.toCharacterSequence().dropFirst())
            }
            let filePath = publicDir + path
            let ifNoneMatch = request.headers["If-None-Match"]
            return try Response(filePath: filePath, ifNoneMatch: ifNoneMatch, chunkSize: chunkSize)
        }
    }
}
