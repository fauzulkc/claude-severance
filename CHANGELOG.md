# Changelog

All notable changes to Claude Severance. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **2.0 preview: the Rust core and `severance` command, at parity with 1.1 on Windows** (phase 2 of `docs/PLATFORMS-PLAN.md`). A Cargo workspace: `severance-core` (accounts, the command-name check, Claude Code settings and badge, auto-switch hook, icons and logos, backups, install, update and uninstall) and `severance-cli` (`severance`, plus `severancew`, which opens Claude Desktop from shortcuts without a console window).
- It reads and updates a 1.x install in place: the same folder and `accounts.json`, every login untouched, 1.x's scripts, shims, shortcuts, badge and profile hook replaced by 2.0's. An end-to-end test runs exactly that update in a sandbox.
- `severance install`, `repair`, `add` (now with `--logo`), `remove`, `alias`, `open`, `list` and `uninstall [--remove-data]`, the same as 1.1's. An account can be named by the start of its id or name when only one matches.
- `--sandbox <dir>` (or `SEVERANCE_SANDBOX`) runs any command against a pretend computer in one folder, changing nothing else.
- Colour only goes to a terminal, and `NO_COLOR` turns it off.

### Changed
- **Plan: version 2.0 is a rewrite in Rust** for Windows, macOS and Linux, replacing the planned separate Go port. One Cargo workspace (a core library, the `severance` command and a Tauri setup window) reads the same `accounts.json`, so a 1.x install updates in place. See `docs/PLATFORMS-PLAN.md`.
- CI checks the Rust workspace (format, Clippy, tests) on Windows, Linux and macOS once it exists. Release tags `v2.*` build Rust archives for Windows x64 and Arm64, Linux x86_64 and aarch64, and macOS universal; `v1.*` tags still build the PowerShell zip.

### Fixed
- The release workflow failed actionlint's shellcheck on unquoted `$TARGETS`; it now splits targets into an array.

## [1.1.0] - 2026-11-10

The first public release: a setup window of its own, any number of org accounts with their own icon and command, and tests and release automation.

### Added
- **Setup window.** One frameless window for install, update, account changes and uninstall, in light and dark. Its look is "the severed floor": one seam splits the window into the work floor and the outside, and the light running down it shows the step (grey-green waiting, brass deciding, teal working, rust removing, green done). Light is a quiet office; dark is an old phosphor terminal, with a faint field of digits while work is under way.
- **Accounts editor.** As many org accounts as you need. Each account is a quiet row (tile, name, command and email); clicking it opens its details inline, one account at a time. Add, rename or remove accounts, with an email check, a folder picker, and undo for removals.
- **Account icons.** Click an account's tile to give it one of eight base colours or your org's own logo (PNG, JPG, BMP, GIF or ICO). Shortcuts, the Start menu and the setup lists use the logo; without one, a coloured shell with the account's first letter. Logos are copied to `logos\<id>.png`, so the original file can move.
- **A command name per account.** Rename an account's terminal command in setup ("Command in the terminal") or with `severance alias <account> <command>`. Existing accounts keep `claude-<id>`.
- **Conflict check for commands.** Before a command is used, setup checks its shape, the names Windows, cmd and Claude reserve, the other accounts, and every program, script, function and alias PowerShell can find. It says what holds the name, live as you type, and stops before changing anything if a name is taken.
- **Terminal commands:** `severance list`, `severance add <name> [--email] [--alias] [--folder]...`, `severance remove <account>` and `severance alias`, with the same checks and backups as the window. `<account>` can be an id, name or command.
- **Update in place.** Running a newer `Install.cmd` opens the update screen and keeps accounts, logins and history as they are.
- **Ready screen.** Opens each new account and explains the sign-in code flow.
- **Installs prerequisites.** Claude Desktop (through winget) and Claude Code (Anthropic's official installer), when missing and only when you choose to.
- **Uninstall keeps the extra accounts by default**, signed in, so reinstalling brings them back. An option zips them (without logins) and removes them.
- `severance setup --text`, `Install.cmd /text`, `severance repair`, and silent switches (`Setup.ps1 -Silent`, `-Mode uninstall -Silent [-RemoveData]`).
- Preview mode (`Preview.cmd`) and a screenshot renderer (`tools\capture-screens.ps1`) that change nothing on the PC.
- Logo, app icon and banners (`tools\make-graphics.ps1`, built with WPF), and bundled fonts: IBM Plex Sans and IBM Plex Mono (SIL OFL).
- Unit tests (Pester 5, `tests\`), CI on Windows with a Linux and macOS matrix ready for the Unix port, and a release workflow with build attestations. Plans: `docs\PLATFORMS-PLAN.md` (Linux and macOS; why not iOS) and `RELEASING.md`.

### Changed
- An account's label is its first letter, and new accounts get muted mid-century colours. Existing accounts keep their colours.
- Install, update and uninstall logic moved into the module (`Invoke-SeveranceInstall`, `Invoke-SeveranceUninstall`), shared by the window, the text setup and the `severance` commands.
- Settings > Apps entries open the setup window. Uninstall runs from a temporary copy, so every installed file can be removed.

### Fixed
- The main account showed as "not signed in yet" in its banner and in `severance` when its `.claude.json` held keys that differ only by case, which `ConvertFrom-Json` rejects. The email and org are now read with a case-sensitive JSON reader.

## [1.0.0] - 2026-11-08

### Added
- Separate Claude Desktop instances per account (`--user-data-dir`) and separate Claude Code configs (`CLAUDE_CONFIG_DIR`).
- Coloured Desktop and Start menu shortcuts and a `claude-<account>` command per account.
- Auto-switching `claude` in PowerShell, chosen by folder; it asks when the folder isn't mapped.
- Claude Code status line badge with the signed-in email and org, plus a WRONG ACCOUNT warning.
- `severance` status command, shared update settings, migration from the earlier ClaudeProfiles scripts, and backup before removal (login tokens excluded).

[Unreleased]: https://github.com/fauzulkc/claude-severance/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/fauzulkc/claude-severance/releases/tag/v1.1.0
