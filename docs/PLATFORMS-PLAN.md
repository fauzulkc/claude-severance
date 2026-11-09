# Platforms plan: Linux and macOS

Claude Severance is Windows-only today. This plan brings it to Linux and macOS. **There is no iOS version, by design**; why is below.

## What each platform allows

| | Windows (today) | macOS | Linux | iOS |
|---|---|---|---|---|
| Claude Code CLI | Yes | Yes | Yes | No CLI on iOS |
| Separate Claude Code config | `CLAUDE_CONFIG_DIR` | `CLAUDE_CONFIG_DIR` | `CLAUDE_CONFIG_DIR` | n/a |
| Official Claude Desktop | Yes | Yes (`Claude.app`, Electron) | No official build at the time of writing | App Store app |
| Second Desktop instance | `--user-data-dir` | `open -n -a Claude --args --user-data-dir=...` | Same flag, *if* a Desktop build is installed | Not possible: apps can't start other apps with their own data folder |
| Launchers with their own icon | `.lnk` shortcuts | Small `.app` bundles in `~/Applications` | `.desktop` files in `~/.local/share/applications` | n/a |
| Auto-switch by folder | PowerShell profile hook | zsh and bash hooks | bash, zsh and fish hooks | n/a |

### Why not iOS

An iOS app runs in its own sandbox and can't start the Claude app with a different data folder, run a CLI, or hold another app's login. Anything that looked like Claude Severance on iOS would have to sign in to Claude itself, which Anthropic's terms don't allow for third-party apps. On iPhone and iPad, use the Claude app's own account menu, or a second device for a second account. We'll revisit only if Apple or Anthropic add a supported way to run accounts side by side.

## Approach

**One Go program for Linux and macOS** (`unix/`, `cmd/severance`): a single static binary with no runtime to install, cross-compiled for amd64 and arm64. Platform code is split by Go filename suffix (`_darwin.go`, `_linux.go`), and the logic they share sits in `internal/` packages. The Windows PowerShell version stays as it is; its `accounts.json` schema (version 1: id, name, label, colour, logo, alias, email, main, folders) is the contract both sides keep.

```
unix/
  go.mod
  cmd/severance/            main, subcommands
  internal/config/          accounts.json, the same schema as Windows
  internal/alias/           conflict check: shell builtins, other accounts, PATH, shell aliases
  internal/shell/           bash, zsh and fish hooks for auto-switch by folder
  internal/statusline/      the Claude Code status line badge
  internal/desktop/         launchers: desktop_darwin.go, desktop_linux.go
  internal/icon/            lettered shells and logos to .icns and .png
```

The commands match Windows: `severance list | add | remove | alias | setup | open | repair | uninstall`, plus `severance statusline`, which Claude Code calls for the badge. `severance setup` is an interactive terminal flow. A graphical setup window is out of scope for the first releases.

### Where things live

| | macOS | Linux |
|---|---|---|
| Data | `~/Library/Application Support/Claude Severance/` | `$XDG_DATA_HOME/claude-severance/` (`~/.local/share/...`) |
| Commands | `~/.local/bin/<alias>` (added to PATH by the shell hook) | `~/.local/bin/<alias>` |
| Launchers | `~/Applications/Claude Severance/Claude - <name>.app` | `~/.local/share/applications/claude-severance-<id>.desktop` |
| Main account | `~/.claude`, untouched except the `statusLine` key | same |

## Phases

1. **Spike (macOS and Linux).** Prove the three things the plan rests on, before writing the real code:
   - A second Desktop window with `--user-data-dir` keeps its own login on macOS, alongside the normal app.
   - Claude Code with `CLAUDE_CONFIG_DIR` keeps its login apart on macOS. Claude Code stores credentials in the macOS Keychain there, not in `.credentials.json`; check that each config folder gets its own Keychain entry. If it doesn't, the macOS port is CLI-limited until Anthropic supports it.
   - Whether a Linux build of Claude Desktop exists at that point, official or community, and whether it honours `--user-data-dir`.
   Each finding goes into this file before phase 2.
2. **CLI core, preview (both).** `list`, `add`, `remove`, `alias`, `repair`, `uninstall`, the status line badge, shell hooks, and the alias conflict check. Released as `v1.2.0-preview.N` tarballs. Tests run on `ubuntu-latest` and `macos-latest`.
3. **macOS launchers.** A per-account `.app` with its own `.icns` icon (from the logo or lettered shell), made locally, so Gatekeeper doesn't quarantine it. The release itself is ad-hoc signed and not notarized at first; installing is `xattr -d com.apple.quarantine` or Homebrew (below).
4. **Linux launchers**, only if phase 1 found a Desktop build that works: `.desktop` files with icons, otherwise Claude Code only, and the setup says so plainly.
5. **Packaging.** A Homebrew tap (`brew install fauzulkc/tap/claude-severance`) for macOS and Linux; then `.deb` and `.rpm` through nfpm, and an AUR package. Developer ID signing and notarization once there is an Apple Developer account (secrets in the release workflow; the job skips when they're missing).
6. **Stable.** Drop "preview" when both ports have been used daily for a release cycle with no data-loss bugs.

## Testing

- Unit tests (`go test ./...`) on `ubuntu-latest` and `macos-latest` for config, alias checks, shell hook text, the status line and icon generation, all in a temporary `HOME`.
- An end-to-end test per OS in CI: `severance add` and `remove` against a fake `claude` on PATH, checking the shims, hooks and launchers it writes, then that `uninstall` leaves nothing behind.
- Linux launchers are checked with `desktop-file-validate`; macOS bundles with `plutil -lint` and `codesign --verify`.

## Risks

- **Desktop multi-instance isn't officially supported** on any platform. Windows already depends on it; the macOS spike decides whether it holds there.
- **Keychain sharing on macOS** could make Claude Code accounts share a login. If so, the macOS port waits, or ships Desktop launchers only.
- **No Linux Claude Desktop.** The Linux port then covers Claude Code only, which is still the main use for developers.
- **The name.** See the naming decision in [RELEASING.md](../RELEASING.md); a rename is cheapest before these ports exist.
