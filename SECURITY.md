# Security

## Reporting a vulnerability

Please report security issues privately through **GitHub > Security > Report a vulnerability** on this repository, not in a public issue. Expect a reply within a week. Fixes are released as a patch version and credited in the changelog, unless you'd rather not be named.

## What Claude Severance does with sensitive data

| Data | Where it lives | What Severance does |
|---|---|---|
| Claude Desktop login | Each account's Desktop data folder | Never reads it |
| Claude Code login (`.credentials.json`) | Each account's Claude Code folder | Never reads it. Backups exclude it |
| Signed-in email and org | Claude Code's `.claude.json` | Reads them to show the badge and catch wrong logins. They stay local |
| MCP server settings | `.claude.json`, `claude_desktop_config.json` | Copied into backups only when you remove an account. Keep backups private |
| `ANTHROPIC_API_KEY` | Your environment | Hidden from Claude when an account starts, so the account's subscription is used |

Claude Severance runs as the current user without administrator rights. It writes only to `%LOCALAPPDATA%\ClaudeSeverance`, HKCU, the user's Start menu and desktop, the user's PATH, the PowerShell profile (auto-switch) and each account's Claude Code `settings.json` (`statusLine`). It contacts the network only when you choose to install Claude Desktop (winget) or Claude Code (`https://claude.ai/install.ps1`).

## Scope

In scope: anything in this repository that exposes, copies or sends credentials, writes outside the locations above, or runs code from an untrusted location.

Out of scope: Claude Desktop, Claude Code and Anthropic's services. Report those to Anthropic.
