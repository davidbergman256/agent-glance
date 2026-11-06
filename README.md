# Agent Glance

A tiny menu-bar app for macOS that floats a Liquid Glass pill above your windows and shows every running **Claude Code** (Claude desktop app) and **Codex** (Codex desktop app) session at a glance:

| Dot | Meaning |
| --- | --- |
| Blue, slowly pulsing | Working |
| Red, with a red row | Waiting for your permission |
| Yellow, with a yellow row | Asking you a multiple-choice question |
| Green | Done |

- **Hover** the pill to see the list: each session's title and what it's doing right now.
- **Click a row** to jump straight to that session.
- **Click the mic** on a row, speak, and press **Return**. The text is typed into that session and sent. **Esc** cancels.
- **Click an empty spot** in the open list to keep it open. Click an empty spot again to fold it back.

Everything runs on your Mac. Speech recognition is on-device, and nothing is sent anywhere except into the session you dictate to.

## Requirements

- macOS 26 or later on Apple Silicon.
- Xcode's Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.
- The Claude desktop app and/or the Codex desktop app.

## Build and install

```bash
scripts/test.sh               # run the tests
scripts/bundle.sh --install   # build, sign and copy to ~/Applications
open ~/Applications/Agent\ Glance.app
```

`bundle.sh` signs with a local code-signing certificate named **Agent Glance Dev** when one is in your login keychain. Every build then has the same identity, so macOS keeps the Accessibility and Microphone permissions across rebuilds. Without that certificate it signs ad hoc, and you'll have to grant Accessibility again after each rebuild. To create the certificate:

```bash
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes -subj "/CN=Agent Glance Dev" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -name "Agent Glance Dev" -passout pass:temp
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm key.pem id.p12
```

## First run

1. **Connect.** Agent Glance asks before adding its hooks to `~/.claude/settings.json` and `~/.codex/hooks.json`. It leaves your other settings and hooks alone, and keeps a one-time backup next to each file (`*.agentglance-bak`).
2. **Trust the hooks in Codex.** Codex asks once whether to trust them. Approve, or Codex sessions won't show up.
3. **Allow Accessibility,** needed to type dictated text into a session. If Agent Glance doesn't appear in System Settings → Privacy & Security → Accessibility, click **+**, press ⌘⇧G, go to `~/Applications`, add **Agent Glance**, and turn it on. Then quit and reopen the app.
4. **Allow the microphone** the first time you dictate. The first dictation also downloads Apple's on-device speech model.

## Menu bar

The menu bar icon is the same row of dots. Its menu has:

- **Show / Hide panel** (⌥⌘A).
- **Compact view:** when on, the panel rests as the pill and opens on hover. When off, the list stays open.
- **Sources:** turn off **Claude Code** or **Codex** to remove that app's hooks.
- **Launch at login.**
- **Quit.**

## How it works

- **Hooks.** Both apps run `agent-glance-hook` on their hook events: a prompt sent, a tool starting or finishing, a permission request, the turn ending. The hook passes the event to the app over a local Unix socket, `~/Library/Application Support/AgentGlance/events.sock`. It prints nothing, always exits 0, and finishes in under 10 ms, even when the app isn't running, so it can never slow down or change what Claude or Codex do.
- **No polling.** The app reads a log file only to find a session's title when an event arrives. While a Claude row is red or yellow, it also watches that one transcript to notice when you deny a permission, since no hook reports that.
- **Opening a session.** A row opens its session with a deep link: `codex://threads/<id>`, or `claude://claude.ai/epitaxy/<id>`. Before typing anything, the app checks that the right session is in front and that its message box has focus. If it can't confirm both, it copies your text and shows "Couldn't reach … Text copied." instead.
- **Dictation keys.** While you're dictating, Return, Enter and Esc are claimed as global shortcuts, so they work whichever app is in front. They're released the moment dictation ends.

Details from testing both apps are in [docs/spike-findings.md](docs/spike-findings.md). The design is in [docs/superpowers/specs/](docs/superpowers/specs/).

## Performance

Measured on an M5 MacBook with sessions running: about 0.0–0.1% CPU and a 29 MB memory footprint. The working dot's pulse is a Core Animation layer animation, so the window server draws it without per-frame work in the app.

## Uninstall

1. Turn both sources off in the menu, which removes the hooks, then quit.
2. Delete `~/Applications/Agent Glance.app` and `~/Library/Application Support/AgentGlance`.
3. Optionally, delete the **Agent Glance Dev** certificate in Keychain Access.
