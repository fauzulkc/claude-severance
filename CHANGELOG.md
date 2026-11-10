# Changelog

All notable changes to Claude Severance. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Org accounts only.** Your normal Claude no longer has to be one of the accounts. Leave it out with `severance install --no-personal`, remove it later with `severance remove personal` or in the manager window (Stop managing this account), and bring it back with `severance add <name> --main` or the window's "This is my normal Claude" box. Leaving it out keeps its login, history and settings as they are; only its launchers, its command and the account badge go.

### Changed
- **New accounts' commands are their name followed by `claude`** (`acmeclaude`, `unityflowclaude`), and your normal Claude's is `myclaude`, instead of `claude-<name>`. Accounts that already exist keep their commands. When something on the computer already has the suggested name, a first install uses `claude-<name>` and says so.
- **A fresh look for the 2.0 manager window.** Accounts are cards showing the command each one answers to. Choosing one opens its own page, beside the list in a wide window or in place of it in a narrow one. The page reads as plain phrases (Signs in as, Opens with) instead of a grid of labelled boxes.

### Fixed
- 2.0 manager window: maximised or on a big screen, the content no longer stretches across the whole screen. In a narrow window, shortcut choices move under their description instead of cutting it short, and the wrong-email warning wraps instead of being cut off. After saving, the footer no longer says there are unsaved changes.

## [2.0.0-preview.1] - 2026-11-10

The first preview of 2.0, the Rust rewrite: Claude Severance on macOS and Linux, a manager window, and launchers per account. Tested on fresh GitHub Windows, macOS and Linux machines, but not yet on a real Mac or Linux desktop. 1.1.0 stays the stable Windows release.

### Added
- **macOS and Linux** (phase 4, preview). Launchers are `.app` bundles in `~/Applications/Claude Severance` and on the desktop on macOS, and `.desktop` files in the app menu and on the desktop on Linux. The account commands, `CLAUDE_SEVERANCE_HOME` and auto-switch go in marked blocks in `~/.zshrc` and `~/.bashrc`, and come out again on uninstall. Claude Desktop opens as each account with its own data folder (`Claude.app`; on Linux a `claude-desktop` program when there is one, else accounts get terminal launchers only), and `severance terminal` opens `$TERMINAL` or the first terminal it finds. Launcher icons are `.icns` on macOS and `.png` on Linux. The manager window names the menu for the platform ("Applications folder", "app menu") and greys out the desktop-app launcher when there's no Claude Desktop.
- CI installs for real on fresh Linux and macOS runners (`tools/e2e-unix.sh`): it validates every launcher, runs each one, checks bash and zsh pick the right account by folder, opens the manager window (Linux screenshot uploaded), then removes an account and uninstalls, checking nothing is left behind.
- **The manager window** (`ClaudeSeverance.exe`, Tauri), opened from Start menu > Claude Severance - Manage accounts or `severance setup`. It lists every account with its sign-in check; open one to edit its name, email, command (checked for clashes as you type), folders, colour or logo, and its launchers. Save runs the same steps as the command line and shows each one. `--preview` opens it on sample accounts in a throwaway folder.
- **Launchers per account.** Each account has a desktop-app launcher (Claude Desktop as that account) and a terminal launcher (a terminal running its Claude Code, starting in its first folder), each on the desktop, in the Start menu, both or neither. Change them in the manager window or with `severance launchers <account> --app <where> --terminal <where>`; open either one now from the window, or the terminal with `severance terminal <account>`. Windows Terminal is used when it's installed. Accounts from 1.x keep their desktop-app shortcuts and gain a terminal launcher in the Start menu.
- **2.0 preview: the Rust core and `severance` command, at parity with 1.1 on Windows** (phase 2 of `docs/PLATFORMS-PLAN.md`). A Cargo workspace: `severance-core` (accounts, the command-name check, Claude Code settings and badge, auto-switch hook, icons and logos, backups, install, update and uninstall) and `severance-cli` (`severance`, plus `severancew`, which opens Claude Desktop from shortcuts without a console window).
- It reads and updates a 1.x install in place: the same folder and `accounts.json`, every login untouched, 1.x's scripts, shims, shortcuts, badge and profile hook replaced by 2.0's. An end-to-end test runs exactly that update in a sandbox.
- `severance install`, `repair`, `add` (now with `--logo`), `remove`, `alias`, `open`, `list` and `uninstall [--remove-data]`, the same as 1.1's. An account can be named by the start of its id or name when only one matches.
- `--sandbox <dir>` (or `SEVERANCE_SANDBOX`) runs any command against a pretend computer in one folder, changing nothing else.
- Colour only goes to a terminal, and `NO_COLOR` turns it off.

### Changed
- The README covers installing the 2.0 preview on macOS and Linux.
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

[Unreleased]: https://github.com/fauzulkc/claude-severance/compare/v2.0.0-preview.1...HEAD
[2.0.0-preview.1]: https://github.com/fauzulkc/claude-severance/compare/v1.1.0...v2.0.0-preview.1
[1.1.0]: https://github.com/fauzulkc/claude-severance/releases/tag/v1.1.0
