# Platforms plan: one Rust codebase

Claude Severance 1.x is a Windows-only PowerShell tool. **Version 2.0 is a rewrite in Rust** that runs on Windows, macOS and Linux from one codebase, with a command-line tool and a setup window on all three. **There is no iOS version, by design**; why is below.

Decided 2026-11-10. This replaces the earlier plan for a separate Go port alongside the PowerShell version.

## Why one Rust codebase

- **One implementation.** Accounts, the alias conflict check, command shims, icons, launchers and the Claude Code settings are written and tested once, not in PowerShell and again in a second language.
- **Fewer runtime surprises.** Much of 1.x's bug-fixing was Windows PowerShell 5.1 itself: case-insensitive variables shadowing each other, JSON keys that differ only by case, PSObject wrapping, overload picking. The compiler and `serde` rule those out.
- **Nothing to install for users.** A native binary per platform, no runtime, no administrator rights, as today.
- **The setup window travels.** WPF exists only on Windows. The 2.0 window is a [Tauri](https://tauri.app) app drawn by the system webview (WebView2, built into Windows 11; WKWebView on macOS; WebKitGTK on Linux), so the Severance look carries over as HTML and CSS with the same IBM Plex fonts.

## What each platform allows

| | Windows | macOS | Linux | iOS |
|---|---|---|---|---|
| Claude Code CLI | Yes | Yes | Yes | No CLI on iOS |
| Separate Claude Code config | `CLAUDE_CONFIG_DIR` | `CLAUDE_CONFIG_DIR` | `CLAUDE_CONFIG_DIR` | n/a |
| Official Claude Desktop | Yes | Yes (`Claude.app`, Electron) | No official build at the time of writing | App Store app |
| Second Desktop instance | `--user-data-dir` | `open -n -a Claude --args --user-data-dir=...` | Same flag, *if* a Desktop build is installed | Not possible: apps can't start other apps with their own data folder |
| Launchers with their own icon | `.lnk` shortcuts | Small `.app` bundles in `~/Applications` | `.desktop` files in `~/.local/share/applications` | n/a |
| Auto-switch by folder | PowerShell profile hook | zsh and bash hooks | bash, zsh and fish hooks | n/a |

### Why not iOS

An iOS app runs in its own sandbox and can't start the Claude app with a different data folder, run a CLI, or hold another app's login. Anything that looked like Claude Severance on iOS would have to sign in to Claude itself, which Anthropic's terms don't allow for third-party apps. On iPhone and iPad, use the Claude app's own account menu, or a second device for a second account. We'll revisit only if Apple or Anthropic add a supported way to run accounts side by side.

## Layout

A Cargo workspace at the repository root. The PowerShell 1.x code stays in `src/` until 2.0 ships (see "The 1.x line" below).

```
Cargo.toml                  workspace; [workspace.package] version is the single source of truth for 2.x
rust-toolchain.toml         pinned stable toolchain, with clippy and rustfmt
crates/
  severance-core/           everything that isn't UI
    config                  accounts.json (schema version 1, unchanged), read and written with serde
    alias                   conflict check: reserved names, other accounts, PATH, shell aliases and builtins
    install                 install, update, repair and uninstall as one plan of steps, with a backup first
    claude                  find Claude Desktop and Claude Code; read the signed-in email (never the tokens)
    shims                   per-account commands: <alias>.cmd on Windows, small sh scripts elsewhere
    hooks                   auto-switch by folder: PowerShell profile, bash, zsh and fish
    statusline              the Claude Code status line badge
    icon                    lettered shells and logos to .ico, .icns and .png (image, ab_glyph, bundled Plex)
    platform/windows.rs     .lnk shortcuts, the user PATH (HKCU\Environment), Start menu
    platform/macos.rs       .app launchers, Info.plist, icns
    platform/linux.rs       .desktop files, XDG folders
  severance-cli/            the `severance` binary: list, add, remove, alias, setup, open, repair, uninstall, statusline, version
app/
  src-tauri/                the `Claude Severance` window: install, update, accounts, uninstall
  ui/                       plain HTML, CSS and a little JS, no bundler; the screens from docs/DESIGN.md
```

`severance-core` has no UI code and no Tauri dependency, so the CLI stays small and every behaviour is unit-tested without a window. Platform code sits behind one trait with three `cfg(target_os)` implementations.

### Where things live

| | Windows | macOS | Linux |
|---|---|---|---|
| Data (`accounts.json`, logos, profiles) | `%LOCALAPPDATA%\ClaudeSeverance\`, the same as 1.x | `~/Library/Application Support/Claude Severance/` | `$XDG_DATA_HOME/claude-severance/` (`~/.local/share/...`) |
| Commands | `%LOCALAPPDATA%\ClaudeSeverance\bin` on the user PATH | `~/.local/bin/<alias>` | `~/.local/bin/<alias>` |
| Launchers | Start menu and desktop `.lnk` | `~/Applications/Claude Severance/Claude - <name>.app` | `~/.local/share/applications/claude-severance-<id>.desktop` |
| Main account | `~/.claude`, untouched except the `statusLine` key | same | same |

On Windows, 2.0 reads the 1.x install as it is: same folder, same `accounts.json`, same profiles and logos. Updating replaces the PowerShell files, shims and shortcuts and keeps every account signed in. A backup is taken first, without `.credentials.json`, as 1.x does.

## Rules carried over from 1.x

- No administrator rights, on any platform. Windows installs per user.
- Never read, copy or print login tokens (`.credentials.json`, Desktop session data, Keychain items).
- Changes to the user's PATH, shell profiles and Claude settings are listed in the setup window and confirmed before they happen.
- Preview mode (`--preview`) shows every screen with sample accounts and changes nothing; CI renders every screen from it.

## Status

- **Phase 2 (core and CLI on Windows): built, not yet released.** `crates/severance-core` and `crates/severance-cli` do what 1.1's module and `severance` command do, against the same `accounts.json`. Tests cover 1.1's Pester cases and a sandboxed update of a 1.1 install. The first `v2.0.0-preview.1` tag waits for the steps below.
- Done 2026-11-10: the update from 1.1 on a real install with two accounts (backup first, without logins): both stayed signed in, and the commands, shortcuts, badge, auto-switch hook and Settings > Apps entry moved to 2.0.
- Before the first preview: the auto-switch prompt for an unmapped folder in a real terminal, and the ClaudeProfiles migration (1.x's, not yet ported; anyone still on ClaudeProfiles can install 1.1 first).
- Phase 1 (the spike) is still open for macOS and Linux; Windows didn't need it.

## Phases

1. **Spike (all three).** Prove what the plan rests on before writing the real code:
   - A second Desktop window with `--user-data-dir` keeps its own login on macOS, alongside the normal app.
   - Claude Code with `CLAUDE_CONFIG_DIR` keeps its login apart on macOS. Claude Code stores credentials in the macOS Keychain there, not in `.credentials.json`; check that each config folder gets its own Keychain entry. If it doesn't, macOS is Desktop-only until Anthropic supports it.
   - Whether a Linux build of Claude Desktop exists, official or community, and whether it honours `--user-data-dir`.
   - Tauri per-user install on Windows (NSIS `currentUser`) without administrator rights, and WebView2 present on a clean Windows 10 and 11.

   Each finding goes into this file before phase 2.
2. **Core and CLI on Windows, at parity with 1.1.** `severance-core` and `severance-cli` do everything the PowerShell `severance` command and install do today, against the same `accounts.json`. Pester's 37 cases are ported as Rust tests. An end-to-end test upgrades a 1.1 install made by the PowerShell version in CI and checks nothing was lost. Released as `v2.0.0-preview.N`.
3. **The setup window.** The Tauri app with the 1.1 screens (install, update, accounts editor with tiles and logos, uninstall), light and dark, plus preview mode and screenshot capture for CI.
4. **macOS and Linux.** Launchers, shell hooks and the status line, behind the same core. macOS `.app` launchers are made locally per account, so Gatekeeper doesn't quarantine them; Linux launchers only where phase 1 found a Desktop build, otherwise Claude Code only, and setup says so plainly.
5. **Packaging.** Windows: a portable zip and a per-user installer, plus winget and Scoop. macOS and Linux: a Homebrew tap (`brew install fauzulkc/tap/claude-severance`), then `.deb`, `.rpm` and AUR. Code signing on Windows and Developer ID notarization on macOS once certificates exist (secrets in the release workflow; those steps skip when they're missing).
6. **2.0 stable.** When 2.0 has been used daily on Windows for a release cycle with no data-loss bugs and the update from 1.1 is proven. macOS and Linux may stay marked preview after that until the same bar is met there.

## Testing

- `cargo fmt --check`, `cargo clippy -D warnings` and `cargo test --workspace` on `windows-latest`, `ubuntu-latest` and `macos-latest` for every push and pull request.
- Core tests run in a temporary home folder with a fake `claude` on PATH: config round-trips (including 1.x files), alias conflicts, shims, hooks, the status line, icons, and install then uninstall leaving nothing behind.
- Linux launchers are checked with `desktop-file-validate`; macOS bundles with `plutil -lint` and `codesign --verify`.
- The window: every screen rendered in preview mode, light and dark, uploaded as CI artifacts like the 1.x screenshots.

## The 1.x line

- Until 2.0 is stable, `main` holds both: PowerShell in `src/`, Rust in `crates/` and `app/`. Tags `v1.*` build the PowerShell zip; tags `v2.*` build the Rust binaries (see `.github/workflows/release.yml`).
- When 2.0 is stable, a `1.x` branch is cut from the last PowerShell commit for fixes, and the PowerShell code leaves `main`.
- 1.x keeps `releases/latest/download/ClaudeSeverance.zip` until 2.0 stable takes it over with its own Windows zip.

## Risks

- **Desktop multi-instance isn't officially supported** on any platform. Windows already depends on it; the macOS spike decides whether it holds there.
- **Keychain sharing on macOS** could make Claude Code accounts share a login. If so, macOS ships Desktop launchers only at first.
- **No Linux Claude Desktop.** The Linux build then covers Claude Code only, which is still the main use for developers.
- **Unsigned binaries.** Windows SmartScreen and macOS Gatekeeper warn about unsigned downloads, as antivirus sometimes flags unsigned PowerShell today. Signing is phase 5; until then the README says what the warning looks like.
- **Rewrite risk.** 1.1 works today. The 1.x line stays supported until 2.0 has proven the update path on real installs.
- **The name.** See the naming decision in [RELEASING.md](../RELEASING.md).
