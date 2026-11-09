# Contributing

Thanks for helping. Claude Severance is small on purpose: plain PowerShell and WPF, no build step, and nothing to install beyond what Windows already ships.

## Getting started

```powershell
git clone https://github.com/fauzulkc/claude-severance
cd claude-severance
Preview.cmd install light            # the setup window with sample accounts; changes nothing
```

Every screen can be opened directly: `Preview.cmd <install|update|manage|uninstall> <light|dark> <screen>`. The screens are `welcome`, `accounts`, `working`, `ready`, `failed`, `confirm`, `removing` and `removed`.

To try a real install without touching your own setup, use a Windows Sandbox or a spare Windows user.

## Layout

| Path | What it is |
|---|---|
| `src/Severance.psm1` | Everything that does work: paths, accounts, install, uninstall, backups |
| `src/SetupWindow.ps1` | The setup window (WPF). Screens and motion only; it calls the module |
| `src/Setup.ps1` | Entry point: picks the window, the text setup or a silent run |
| `src/Setup-Console.ps1` | The text setup |
| `src/claude-account.ps1`, `src/statusline.ps1`, `src/severance.ps1`, `src/Launch-Desktop.ps1` | What runs every day |
| `tools/` | Screenshot renderer, release builder, graphics generator |
| `assets/`, `docs/` | Logo, banners, screenshots, design and architecture notes |

## Rules

- **Windows PowerShell 5.1.** Don't use `??`, `?:`, `&&`, `ForEach-Object -Parallel` or other PowerShell 7-only syntax.
- **ASCII only** in `.ps1`, `.psm1` and `.cmd` files. Windows PowerShell reads BOM-less files as ANSI. Build any other character at runtime, e.g. `[char]0x2026`.
- **CRLF line endings** for scripts (`.gitattributes` enforces this).
- **No administrator.** Everything stays under the current user: HKCU, `%LOCALAPPDATA%`, the user's Start menu and desktop.
- **Never read, copy or send login tokens.** Backups exclude `.credentials.json`; keep it that way.
- **Uninstall removes only what Severance added.** The main account's data is never deleted.
- **Words in the window:** short, plain sentences that say what happens. Use the moment's colour only where it carries meaning (see [docs/DESIGN.md](docs/DESIGN.md)).

## Before you open a pull request

- [ ] `tools\capture-screens.ps1` renders every screen in both themes, and `docs\screenshots\capture.log` shows `saved=True` for each.
- [ ] CI is green: scripts parse, ASCII check, PSScriptAnalyzer (errors).
- [ ] If you changed a screen, the PR includes its before and after screenshots.
- [ ] `CHANGELOG.md` has a line under **Unreleased**.

## Releasing

1. Bump `$script:Version` in `src/Severance.psm1`, and move **Unreleased** in `CHANGELOG.md` under the new version.
2. Tag `vX.Y.Z` and push. The release workflow builds `ClaudeSeverance-X.Y.Z.zip` with `tools\build-release.ps1` and attaches it to a GitHub release, with its SHA-256.
