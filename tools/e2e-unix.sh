#!/usr/bin/env bash
# A real install on macOS or Linux, inside a throwaway home folder: the actual launchers, shell profiles and
# commands, not the test sandbox. CI runs it on fresh runners; it never touches the real home folder.
#
#   tools/e2e-unix.sh <folder with severance, severancew and ClaudeSeverance> [screenshot folder]
#
# Claude Code and Claude Desktop are small stand-ins that write down how they were started.
set -euo pipefail

bin_in="$(cd "$1" && pwd)"
shots="${2:-}"
os="$(uname -s)"
work="$(cd "$(mktemp -d)" && pwd -P)"
log="$work/record"
fail() { echo "::error::$*"; exit 1; }
pass() { echo "ok    $*"; }

export HOME="$work/home"
export XDG_DATA_HOME="$HOME/.local/share" XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME/Desktop" "$XDG_CONFIG_HOME" "$work/fake" "$work/acme-project"
# Linux finds the desktop through user-dirs.dirs
printf 'XDG_DESKTOP_DIR="%s/Desktop"\n' "$HOME" > "$XDG_CONFIG_HOME/user-dirs.dirs"
# on Linux, zsh users get the same lines once they have a .zshrc
if [ "$os" = Linux ] && command -v zsh >/dev/null; then touch "$HOME/.zshrc"; fi
unset CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY

# ---- stand-ins ----
cat > "$work/fake/claude" <<EOF
#!/bin/sh
echo "code config=\${CLAUDE_CONFIG_DIR:-main} pwd=\$PWD args=\$*" >> "$log"
echo "claude stand-in \${CLAUDE_CONFIG_DIR:-main}"
EOF
cat > "$work/fake/faketerm" <<EOF
#!/bin/sh
echo "terminal pwd=\$PWD args=\$*" >> "$log"
EOF
chmod +x "$work/fake/claude" "$work/fake/faketerm"
export PATH="$work/fake:$PATH"
touch "$log"

if [ "$os" = Darwin ]; then
  app="$work/Claude.app"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/MacOS/Claude" <<EOF
#!/bin/sh
echo "desktop args=\$*" >> "$log"
EOF
  chmod +x "$app/Contents/MacOS/Claude"
  cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Claude</string>
  <key>CFBundleIdentifier</key><string>io.github.fauzulkc.claudeseverance.test.fakeclaude</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
  export SEVERANCE_DESKTOP_APP="$app"
fi

# a copy outside the repo, as a downloaded release would be
mkdir -p "$work/download"
cp "$bin_in/severance" "$bin_in/severancew" "$work/download/"
[ -f "$bin_in/ClaudeSeverance" ] && cp "$bin_in/ClaudeSeverance" "$work/download/"
sev="$work/download/severance"

# ---- install ----
if [ "$os" = Linux ]; then
  # no Claude Desktop: accounts still install, with terminal launchers only
  out="$("$sev" install)"
  echo "$out"
  grep -q "terminal launchers only" <<<"$out" || fail "no note about the missing Claude Desktop"
  pass "installs without Claude Desktop"
  cat > "$work/fake/claude-desktop" <<EOF
#!/bin/sh
echo "desktop args=\$*" >> "$log"
EOF
  chmod +x "$work/fake/claude-desktop"
fi
"$sev" install
"$sev" add Acme --email me@acme.example --folder "$work/acme-project"
"$sev" launchers acme --app both --terminal both
"$sev" list

if [ "$os" = Darwin ]; then
  root="$HOME/Library/Application Support/Claude Severance"
  menu="$HOME/Applications/Claude Severance"
else
  root="$XDG_DATA_HOME/claude-severance"
  menu="$XDG_DATA_HOME/applications/claude-severance"
fi
installed="$root/bin/severance"
[ -x "$installed" ] || fail "severance isn't installed in $root/bin"
pass "installed in $root"

# ---- launchers ----
ls -la "$HOME/Desktop" "$menu"
if [ "$os" = Darwin ]; then
  for name in "Claude - Personal" "Claude Code - Personal" "Claude - Acme" "Claude Code - Acme" \
              "Claude Severance - Manage accounts" "Uninstall Claude Severance"; do
    [ -d "$menu/$name.app" ] || fail "no $name in the Applications folder"
    plutil -lint "$menu/$name.app/Contents/Info.plist" >/dev/null || fail "$name: Info.plist doesn't parse"
    [ -x "$menu/$name.app/Contents/MacOS/launcher" ] || fail "$name: launcher isn't executable"
  done
  [ -d "$HOME/Desktop/Claude - Acme.app" ] && [ -d "$HOME/Desktop/Claude Code - Acme.app" ] \
    || fail "Acme's desktop launchers are missing"
  [ -f "$menu/Claude - Acme.app/Contents/Resources/icon.icns" ] || fail "no icon in the Acme app"
  pass "app bundles in ~/Applications/Claude Severance and on the desktop"
  # the terminal launcher's command file, run as Terminal would run it
  sh "$menu/Claude Code - Acme.app/Contents/Resources/run.command"
  # the app launcher, through LaunchServices
  "$menu/Claude - Acme.app/Contents/MacOS/launcher"
else
  for f in claude-personal claude-code-personal claude-acme claude-code-acme \
           claude-severance-manage-accounts uninstall-claude-severance; do
    [ -f "$menu/$f.desktop" ] || fail "no $f.desktop in the app menu"
  done
  desktop-file-validate "$menu"/*.desktop "$HOME/Desktop"/*.desktop || fail "a .desktop file doesn't validate"
  [ -f "$HOME/Desktop/claude-acme.desktop" ] && [ -f "$HOME/Desktop/claude-code-acme.desktop" ] \
    || fail "Acme's desktop launchers are missing"
  grep -q '^Terminal=true$' "$menu/claude-code-acme.desktop" || fail "the terminal launcher doesn't ask for a terminal"
  grep -q "^Path=$work/acme-project$" "$menu/claude-code-acme.desktop" || fail "the terminal launcher doesn't start in Acme's folder"
  pass "desktop entries validate"
  # run each launcher's Exec line the way the desktop would (without the terminal window)
  for f in claude-code-acme claude-acme; do
    exec_line="$(sed -n 's/^Exec=//p' "$menu/$f.desktop")"
    dir="$(sed -n 's/^Path=//p' "$menu/$f.desktop")"
    (cd "$dir" && eval "$exec_line")
  done
fi

# ---- what the launchers started ----
for _ in $(seq 1 20); do grep -q '^desktop ' "$log" && break; sleep 0.5; done
cat "$log"
grep -q "^code config=$root/code/acme pwd=$work/acme-project" "$log" || fail "the terminal launcher didn't run Acme's Claude Code in its folder"
pass "terminal launcher runs Acme's Claude Code in its folder"
grep -q "^desktop args=--user-data-dir=$root/desktop/acme" "$log" || fail "the app launcher didn't open Claude Desktop with Acme's data folder"
pass "app launcher opens Claude Desktop with Acme's data folder"

# ---- shell profiles: PATH, commands and auto-switch ----
if [ "$os" = Darwin ]; then shells="zsh"; rc="$HOME/.zshrc"; else shells="bash"; rc="$HOME/.bashrc"; fi
if [ "$os" = Linux ] && [ -f "$HOME/.zshrc" ]; then shells="bash zsh"; fi
cat "$rc"
grep -q '# >>> claude-severance >>>' "$rc" || fail "no auto-switch block in $rc"
for sh in $shells; do
  : > "$log"
  out="$(cd "$work/acme-project" && "$sh" -ic 'type claude; command -v claude-acme; claude --version' 2>&1)" || { echo "$out"; fail "$sh: commands failed"; }
  echo "$out"
  grep -q "$root/bin/claude-acme" <<<"$out" || fail "$sh: claude-acme isn't on PATH"
  grep -q "^code config=$root/code/acme .*args=--version" "$log" || fail "$sh: claude in Acme's folder didn't pick Acme"
  : > "$log"
  (cd "$HOME" && "$sh" -ic 'claude-personal -p hi' >/dev/null 2>&1) || fail "$sh: claude-personal failed"
  grep -q "^code config=main .*args=-p hi" "$log" || fail "$sh: claude-personal didn't use the main account"
  pass "$sh: PATH, account commands and auto-switch work"
done

# ---- open a terminal (Linux, with TERMINAL set to a stand-in) ----
if [ "$os" = Linux ]; then
  : > "$log"
  TERMINAL=faketerm "$installed" terminal acme
  for _ in $(seq 1 20); do grep -q '^terminal ' "$log" && break; sleep 0.5; done
  grep -q "^terminal pwd=$work/acme-project args=-e $installed run acme" "$log" || { cat "$log"; fail "severance terminal didn't open \$TERMINAL in Acme's folder"; }
  pass "severance terminal opens \$TERMINAL in Acme's folder"
fi

# ---- the manager window opens on the real accounts ----
if [ -x "$root/bin/ClaudeSeverance" ]; then
  if [ "$os" = Linux ]; then
    out_dir="${shots:-$work}"
    Xvfb :99 -screen 0 1280x900x24 -nolisten tcp & xvfb=$!
    sleep 2
    # Xvfb has no GPU, so WebKitGTK renders in software
    DISPLAY=:99 SEVERANCE_DEBUG=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 LIBGL_ALWAYS_SOFTWARE=1 \
      "$root/bin/ClaudeSeverance" > "$out_dir/manager-linux.log" 2>&1 & pid=$!
    # a debug build takes a while to start on a CI runner: wait for the window, then for it to paint
    shown=no
    for _ in $(seq 1 90); do
      if DISPLAY=:99 xwininfo -root -tree | grep -q '"Claude Severance"'; then shown=yes; break; fi
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    grep -q 'page Finished' "$out_dir/manager-linux.log" 2>/dev/null || sleep 5
    sleep 2
    alive=yes; kill -0 "$pid" 2>/dev/null || alive=no
    echo "--- windows on the display"; DISPLAY=:99 xwininfo -root -tree | head -40 || true
    DISPLAY=:99 import -window root "$out_dir/manager-linux.png" || true
    kill "$pid" "$xvfb" 2>/dev/null || true
    echo "--- the window's output"; cat "$out_dir/manager-linux.log"
    [ "$alive" = yes ] || fail "the manager window exited early on Linux"
    [ "$shown" = yes ] || fail "the manager window never appeared on Linux"
    grep -q 'page Finished' "$out_dir/manager-linux.log" || fail "the manager window's page didn't load on Linux"
  else
    "$root/bin/ClaudeSeverance" & pid=$!
    sleep 12
    kill -0 "$pid" || fail "the manager window exited early on macOS"
    [ -n "$shots" ] && screencapture -x "$shots/manager-macos.png" || true
    kill "$pid"
  fi
  pass "manager window stays open"
fi

# ---- remove an account, then uninstall ----
"$installed" remove acme --yes
[ ! -e "$root/code/acme" ] || fail "Acme's data is still there"
ls "$HOME/Claude Severance backups/"*.zip >/dev/null || fail "no backup zip for Acme"
"$installed" uninstall --yes
[ ! -e "$root/bin" ] || fail "bin is still there after uninstall"
[ ! -e "$menu" ] || fail "the menu folder is still there after uninstall"
if ls "$HOME/Desktop" | grep -qi claude; then fail "launchers left on the desktop"; fi
for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$f" ] && grep -q claude-severance "$f"; then fail "lines left in $f"; fi
done
pass "uninstall leaves nothing behind"
echo "All real-install checks passed on $os."
