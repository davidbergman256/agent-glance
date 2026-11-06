// agent-glance-hook --source claude|codex [--socket <path>]
//
// Run by Claude Code and Codex on every hook event. Reads the hook JSON from stdin and
// forwards {"source": ..., "payload": <stdin>} to Agent Glance over a Unix socket.
// It must never affect the agent: it prints nothing, always exits 0, and gives up fast
// when the app isn't running. Darwin only (no Foundation) to keep startup quick.
import Darwin

signal(SIGPIPE, SIG_IGN)

var source = "claude"
var socketPath: String? = nil
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--source": if let v = args.next(), v == "claude" || v == "codex" { source = v }
    case "--socket": socketPath = args.next()
    default: break
    }
}
if socketPath == nil, let home = getenv("HOME") {
    socketPath = String(cString: home) + "/Library/Application Support/AgentGlance/events.sock"
}

// Read stdin, capped at 1 MB.
var input: [UInt8] = []
var buf = [UInt8](repeating: 0, count: 16 * 1024)
while input.count < 1 << 20 {
    let n = read(STDIN_FILENO, &buf, buf.count)
    if n <= 0 { break }
    input.append(contentsOf: buf[0..<n])
}
while let last = input.last, last == 10 || last == 13 || last == 32 { input.removeLast() }
guard !input.isEmpty, let path = socketPath else { exit(0) }

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(path.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { exit(0) }
withUnsafeMutableBytes(of: &addr.sun_path) { b in
    b.copyBytes(from: pathBytes)
    b[pathBytes.count] = 0
}
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else { close(fd); exit(0) }

let message = Array("{\"source\":\"\(source)\",\"payload\":".utf8) + input + [UInt8(ascii: "}")]
var sent = 0
while sent < message.count {
    let n = message[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    if n <= 0 { break }
    sent += n
}
close(fd)
exit(0)
