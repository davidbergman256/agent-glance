import Darwin
import Foundation

/// macOS ignores cursor changes from apps that aren't frontmost, and Agent Glance never takes
/// the front. The window server's "SetsCursorInBackground" connection property lifts that for
/// this app only. It's undocumented (used by many menu bar utilities), so it's looked up at run
/// time: if a future macOS drops it, this does nothing and the cursor simply stays an arrow.
enum BackgroundCursor {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func enable() {
        guard let handle = dlopen(nil, RTLD_NOW),
              let mainSym = dlsym(handle, "_CGSDefaultConnection") ?? dlsym(handle, "CGSMainConnectionID"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(mainSym, to: MainConnection.self)()
        _ = unsafeBitCast(setSym, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
