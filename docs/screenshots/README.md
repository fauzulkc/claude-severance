# Screenshots

These are rendered from the real setup window in preview mode, at 2x, by:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-screens.ps1
```

It takes about a minute, changes nothing on the PC, and writes `<mode>-<screen>-<theme>.png` here, plus `capture.log`. CI renders the same set on every push and uploads it as the `screenshots` artifact.

| Mode | Screens |
|---|---|
| install | welcome, accounts, working, ready, failed |
| update | welcome |
| manage | accounts |
| uninstall | confirm, removing, removed |
