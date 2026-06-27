import Foundation
import OSLog

/// Talks to the AeroSpace server directly over its unix-domain socket, skipping
/// the ~11ms cost of spawning the `aerospace` CLI per call (the spawn, not the
/// server work, was the dominant latency — a refresh drops ~35ms → ~15ms).
///
/// The wire protocol is UNDOCUMENTED (reverse-engineered from aerospace
/// 0.20.3): send a JSON `{"args":[<full argv>],"stdin":""}` request, half-close
/// the write side to signal EOF, then read back a
/// `{"exitCode","stdout","stderr","serverVersionAndHash"}` envelope.
///
/// There is NO CLI fallback by design. If aerospace changes the protocol this
/// fails loudly — errors hit the log and Spaces goes blank — so the breakage is
/// obvious and gets fixed, rather than silently masked by a slow spawn path.
enum AerospaceClient {
    private static let socketPath = "/tmp/bobko.aerospace-\(NSUserName()).sock"

    private struct Request: Encodable {
        let args: [String]
        let stdin = ""
    }
    private struct Response: Decodable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs an aerospace command over the socket. Returns stdout as `Data`, or
    /// `nil` on any transport / protocol / non-zero-exit failure (all logged).
    static func run(_ args: [String]) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Logger.aerospace.error(
                "socket() failed: \(String(cString: strerror(errno)))")
            return nil
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Logger.aerospace.error("socket path too long: \(socketPath)")
            return nil
        }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) {
                dst in
                pathBytes.withUnsafeBufferPointer {
                    dst.update(from: $0.baseAddress!, count: pathBytes.count)
                }
            }
        }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            Logger.aerospace.error(
                "connect to \(socketPath) failed: \(String(cString: strerror(errno))) — is AeroSpace running?"
            )
            return nil
        }

        // Send the request, then half-close the write side so the server sees EOF.
        guard let payload = try? JSONEncoder().encode(Request(args: args)) else {
            return nil
        }
        let sent = payload.withUnsafeBytes {
            send(fd, $0.baseAddress, $0.count, 0)
        }
        guard sent == payload.count else {
            Logger.aerospace.error(
                "short write to socket (\(sent)/\(payload.count))")
            return nil
        }
        shutdown(fd, SHUT_WR)

        // The server answers one envelope per request, but our half-close makes
        // it read EOF and tack on a second `{"exitCode":1,"stderr":"Empty
        // request"}` envelope before closing. So read only up to the end of the
        // first complete top-level JSON object and ignore the trailing noise.
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        var objectEnd: Int?
        while objectEnd == nil {
            let n = read(fd, &buf, buf.count)
            if n < 0 {
                Logger.aerospace.error(
                    "read failed: \(String(cString: strerror(errno)))")
                return nil
            }
            if n == 0 { break }
            data.append(buf, count: n)
            objectEnd = Self.firstJSONObjectEnd(in: data)
        }
        let envelope = objectEnd.map { data.prefix($0 + 1) } ?? data

        guard let resp = try? JSONDecoder().decode(Response.self, from: envelope)
        else {
            Logger.aerospace.fault(
                "PROTOCOL MISMATCH decoding aerospace response for \(args) — the socket wire format likely changed; fix AerospaceClient. Raw: \(String(data: data.prefix(256), encoding: .utf8) ?? "<binary>")"
            )
            return nil
        }
        guard resp.exitCode == 0 else {
            Logger.aerospace.error(
                "aerospace \(args) exited \(resp.exitCode): \(resp.stderr)")
            return nil
        }
        return Data(resp.stdout.utf8)
    }

    /// Index of the closing `}` of the first complete top-level JSON object in
    /// `data`, or nil if not yet fully received. String-aware so braces inside
    /// string values don't throw off the depth count.
    private static func firstJSONObjectEnd(in data: Data) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        for (i, byte) in data.enumerated() {
            if escaped {
                escaped = false
                continue
            }
            if inString {
                if byte == 0x5c { escaped = true }       // backslash
                else if byte == 0x22 { inString = false } // closing quote
                continue
            }
            switch byte {
            case 0x22: inString = true                    // opening quote
            case 0x7b: depth += 1                          // {
            case 0x7d:                                     // }
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
        }
        return nil
    }
}
