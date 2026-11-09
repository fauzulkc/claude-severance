# Architecture

## The idea

Claude Desktop is an Electron app. Electron keys everything to its data folder: the login, the chats, the settings, and the lock that allows only one window per folder. Starting the same `Claude.exe` with a different `--user-data-dir` gives a second, independent app that runs alongside the first.

Claude Code reads its whole configuration (login, memory, `CLAUDE.md`, settings, MCP, history) from `CLAUDE_CONFIG_DIR`, and falls back to `%USERPROFILE%\.claude` when it isn't set.

Claude Severance gives each extra account its own pair of folders. Everything else is convenience: shortcuts, commands, a status line badge, auto-switching by folder, and a setup window to manage them.

## Where things live

```
%LOCALAPPDATA%\ClaudeSeverance\
  accounts.json            the accounts: id, name, label, colour, logo, alias, email, main, folders
  bin\                     scripts, fonts, icons, one <alias>.cmd per account, severance.cmd
  logos\<id>.png           an account's own logo, if it has one (256 px, copied in by setup)
  desktop\<id>\            Claude Desktop data for each extra account
  code\<id>\               Claude Code config for each extra account (CLAUDE_CONFIG_DIR)

%USERPROFILE%\.claude\     the main account's Claude Code config, untouched except the statusLine key
%USERPROFILE%\Claude Severance backups\   zips made when an account is removed (never with logins)
```

The main account uses the normal Claude Desktop app data and `%USERPROFILE%\.claude`. On the Microsoft Store build it starts through `shell:AppsFolder`, exactly as the Start menu does, so it keeps its app identity and Cowork.

## What runs

| Moment | Script | What it does |
|---|---|---|
| A Desktop shortcut | `Launch-Desktop.ps1` | Finds `Claude.exe` again (updates move it) and starts it with the account's data folder and `CLAUDE_CONFIG_DIR` |
| An account's command (`claude-<id>` or its alias) | `claude-account.ps1` | Shows the account banner, sets `CLAUDE_CONFIG_DIR`, hides `ANTHROPIC_API_KEY`, runs the real `claude` |
| `claude` in PowerShell | profile hook, then `claude-account.ps1 auto` | Picks the account whose folders contain the current one (longest match); asks when none does |
| Claude Code status line | `statusline.ps1` | Badge in the account's colour, signed-in email and org, model, folder, context use |
| `severance` | `severance.ps1` | List, add, remove, alias, setup, repair, open, uninstall |
| Setup | `Setup.ps1`, then `SetupWindow.ps1` or `Setup-Console.ps1` | Install, update, manage accounts, uninstall |

All the work is in `Severance.psm1`. The window and the text setup only collect choices, then call:

- `Get-SeveranceSetupInfo`: what is installed, found and possible
- `Invoke-SeveranceInstall`: install, update, repair and account changes, reporting each finished step
- `Invoke-SeveranceUninstall`: removal, reporting each finished step

The window runs these in a background runspace and shows each reported step as a line in its checklist, at least 260 ms apart, so real steps read as steps.

## Install, step by step

1. Install Claude Desktop (winget) or Claude Code (official installer), only if chosen.
2. Bring over an earlier ClaudeProfiles setup, if present.
3. Copy in any newly chosen logos, then check every account's command name with `Test-SeveranceAlias` (shape, reserved names, the other accounts, then anything `Get-Command` finds outside `bin`). If one is taken, stop here, before anything else changes.
4. Back up, then remove, any accounts taken out.
5. Save `accounts.json`, and copy the scripts, fonts and icons to `bin`.
6. For each account: create its folders, add the status line, and make its icon (its logo, or a coloured shell with its letter), shortcuts and command. A new extra account starts with the main account's `CLAUDE.md`, settings, commands, agents, skills and hooks, but never its login or memory.
7. Add the Start menu entries, PATH entry and shared update settings, plus auto-switch if chosen and allowed by policy.
8. Register in Settings > Apps.

## Uninstall

Uninstall runs from a temporary copy of the setup files, so every file in `bin` can be removed. It:

1. Closes the extra accounts' Desktop windows.
2. Zips their data, without logins, if you chose to remove them.
3. Removes the badge from the main account's settings, then the shortcuts, commands, PATH entry, profile hook and Settings > Apps entry.
4. Removes `bin`, or the whole folder if you chose to remove the accounts. Files still in use are removed at the next sign-in, through a RunOnce entry.
