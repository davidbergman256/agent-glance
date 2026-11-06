import Darwin
import Foundation

/// Listens on a Unix socket for envelopes from `agent-glance-hook`: one JSON message per
/// connection, read to EOF. Idle cost is zero: it only wakes when a hook connects.
public final class EventSocketServer: @unchecked Sendable {
    private let path: URL
    private let onEvent: @Sendable (HookEvent) -> Void
    private let queue = DispatchQueue(label: "agentglance.socket")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    static let maxMessage = 1 << 20

    public init(path: URL, onEvent: @escaping @Sendable (HookEvent) -> Void) throws {
        self.path = path
        self.onEvent = onEvent
        unlink(path.path)  // a stale socket file from a previous run would block bind()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            throw POSIXError(.init(rawValue: err) ?? .EIO)
        }
        chmod(path.path, 0o600)  // only this user's processes may connect
        listenFD = fd
    }

    public func start() {
        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path.path)
    }

    private func acceptOne() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < Self.maxMessage {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        close(client)
        if let event = try? JSONDecoder().decode(HookEvent.self, from: data) {
            onEvent(event)
        }
    }
}
