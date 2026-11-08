# Agent Glance

macOS menu-bar app showing the state of every Claude Code (Claude desktop app) and Codex (Codex desktop app) session. Click a row to open that session; the row's mic dictates a message into it. ⌥⌘A toggles the panel.

## Install

macOS 26+, Apple Silicon, Command Line Tools (no Xcode).

```bash
scripts/test.sh               # not bare `swift test`: adds CLT Swift Testing paths
scripts/bundle.sh --install   # → ~/Applications/Agent Glance.app
open ~/Applications/Agent\ Glance.app
```

`bundle.sh` signs with keychain identity `Agent Glance Dev` if present, else ad hoc. Ad hoc loses the Accessibility grant on every rebuild, so create that self-signed code-signing cert if you'll rebuild.

User must: click **Connect** on first launch; approve Codex's one-time hook-trust prompt (or Codex sessions won't show); grant Accessibility (for dictation), then relaunch; allow the mic on first dictation.

## Internals

- Hooks: entries whose command contains `agent-glance-hook` in `~/.claude/settings.json` and `~/.codex/hooks.json`. Nothing else in those files is touched; first install saves `<file>.agentglance-bak`.
- The hook command is an absolute path into the app bundle. After moving the app, toggle each source off/on in the menu.
- Hook → app via `~/Library/Application Support/AgentGlance/events.sock`. Hook prints nothing, always exits 0.
- Tested app behaviour: `docs/spike-findings.md`.

## Uninstall

Menu → Sources → turn both off (removes hooks), quit, then:

```bash
rm -rf ~/Applications/Agent\ Glance.app ~/Library/Application\ Support/AgentGlance
```

MIT.
