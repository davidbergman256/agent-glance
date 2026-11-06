import Carbon.HIToolbox

/// A single global shortcut (⌥⌘A) via Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission and costs nothing until pressed.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    init(keyCode: UInt32 = UInt32(kVK_ANSI_A), modifiers: UInt32 = UInt32(cmdKey | optionKey), action: @escaping @MainActor () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4147_4C4E), id: 1)  // 'AGLN'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
