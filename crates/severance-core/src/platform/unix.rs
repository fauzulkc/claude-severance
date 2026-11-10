//! macOS and Linux.
//!
//! - Launchers: `.desktop` files on Linux (the app menu is `~/.local/share/applications/claude-severance`), small
//!   `.app` bundles on macOS (the menu is `~/Applications/Claude Severance`, which Launchpad and Spotlight show).
//! - The PATH entry, the `CLAUDE_SEVERANCE_HOME` variable and auto-switch are marked blocks in `~/.zshrc` and
//!   `~/.bashrc` (see [`crate::hooks`]).
//! - Claude Desktop is `Claude.app` on macOS. Anthropic doesn't make it for Linux, so there a `claude-desktop` program
//!   on PATH is used when there is one, and Claude Code accounts work without it.
//!
//! `SEVERANCE_DESKTOP_APP` points at a Claude Desktop somewhere else (a `.app` on macOS, a program on Linux).

use super::Launcher;
use crate::hooks::{posix_profiles, put_block, sh_quote};
use crate::install::MARKER;
use crate::{Account, Paths};
use anyhow::{Context, Result, bail};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const MAC: bool = cfg!(target_os = "macos");

/// What this platform calls the place launchers go besides the desktop
pub const MENU_NAME: &str = if MAC {
    "Applications folder"
} else {
    "app menu"
};

/// Why there's no Claude Desktop on Linux, and what is used when there is one
pub const NO_DESKTOP_LINUX: &str = "Anthropic doesn't make Claude Desktop for Linux. Claude Code accounts work \
     without it, and a community build installed as 'claude-desktop' is used when there is one.";

fn home() -> Option<PathBuf> {
    dirs::home_dir()
}

pub fn start_menu_dir() -> Option<PathBuf> {
    if MAC {
        Some(home()?.join("Applications").join("Claude Severance"))
    } else {
        Some(
            dirs::data_dir()?
                .join("applications")
                .join("claude-severance"),
        )
    }
}

pub fn ignore_ctrl_c() {}

pub fn enable_ansi() {}

fn is_executable(p: &Path) -> bool {
    p.metadata()
        .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

fn on_path(name: &str) -> Option<PathBuf> {
    on_path_in(name, &std::env::var_os("PATH")?)
}

fn on_path_in(name: &str, path: &std::ffi::OsStr) -> Option<PathBuf> {
    std::env::split_paths(path)
        .map(|d| d.join(name))
        .find(|p| is_executable(p))
}

/// Claude Desktop: `Claude.app` on macOS, a `claude-desktop` program on Linux
pub fn resolve_claude_exe() -> Result<PathBuf> {
    if let Some(p) = std::env::var_os("SEVERANCE_DESKTOP_APP").map(PathBuf::from) {
        if p.exists() {
            return Ok(p);
        }
        bail!(
            "SEVERANCE_DESKTOP_APP is set to {}, which isn't there.",
            p.display()
        );
    }
    if MAC {
        let mut places = vec![PathBuf::from("/Applications/Claude.app")];
        if let Some(h) = home() {
            places.push(h.join("Applications").join("Claude.app"));
        }
        places
            .into_iter()
            .find(|p| p.join("Contents").is_dir())
            .context("Claude Desktop isn't in Applications. Get it from claude.ai/download.")
    } else {
        on_path("claude-desktop").context(NO_DESKTOP_LINUX)
    }
}

/// Starts a program on its own, so closing the terminal or launcher that started it leaves it running
fn spawn_detached(cmd: &mut Command) -> Result<()> {
    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    cmd.spawn()
        .with_context(|| format!("couldn't start {:?}", cmd.get_program()))?;
    Ok(())
}

/// Opens Claude Desktop as this account: its own `--user-data-dir` for an extra account, the normal one for the main
pub fn start_desktop(account: &Account, paths: &Paths) -> Result<()> {
    let app = resolve_claude_exe()?;
    let data = account.desktop_dir(paths);
    if let Some(d) = &data {
        std::fs::create_dir_all(d)?;
    }
    if MAC && app.extension().is_some_and(|e| e == "app") {
        let mut cmd = Command::new("/usr/bin/open");
        // a second copy needs -n; the main one only when it isn't open already, else it just comes to the front
        let main_open = super::desktop_processes()
            .iter()
            .any(|p| !p.command_line.contains("--user-data-dir"));
        if data.is_some() || !main_open {
            cmd.arg("-n");
        }
        cmd.arg("-a").arg(&app);
        if let Some(d) = &data {
            cmd.arg("--args")
                .arg(format!("--user-data-dir={}", d.display()));
        }
        let status = cmd.status().context("couldn't run open")?;
        if !status.success() {
            bail!("macOS couldn't open {}.", app.display());
        }
        Ok(())
    } else {
        let mut cmd = Command::new(&app);
        if let Some(d) = &data {
            cmd.arg(format!("--user-data-dir={}", d.display()));
        }
        spawn_detached(&mut cmd)
    }
}

/// PATH and environment lines go in their own blocks, apart from auto-switch, so each can be taken out alone
const PATH_START: &str = "# >>> claude-severance path >>>";
const PATH_END: &str = "# <<< claude-severance path <<<";

fn profiles() -> Vec<PathBuf> {
    home().map(|h| posix_profiles(&h)).unwrap_or_default()
}

pub fn set_user_path_entry(dir: &Path, add: bool) -> Result<()> {
    let d = sh_quote(&dir.display().to_string());
    let body =
        |_: &Path| format!("case \":$PATH:\" in *:{d}:*) ;; *) export PATH={d}\":$PATH\" ;; esac");
    let body: &dyn Fn(&Path) -> String = &body;
    put_block(&profiles(), PATH_START, PATH_END, add.then_some(body))
}

pub fn set_user_env(name: &str, value: Option<&str>) -> Result<()> {
    let start = format!("# >>> claude-severance {name} >>>");
    let end = format!("# <<< claude-severance {name} <<<");
    let body = |_: &Path| format!("export {name}={}", sh_quote(value.unwrap_or("")));
    let body: &dyn Fn(&Path) -> String = &body;
    put_block(&profiles(), &start, &end, value.is_some().then_some(body))
}

/// (policy, scope) that applies to PowerShell profile scripts; there are none to block here
pub fn profile_execution_policy() -> (String, String) {
    ("Unrestricted".into(), "Default".into())
}

pub fn allow_profile_scripts() -> Result<()> {
    Ok(())
}

/// The launcher file for `name` in `dir`: `name.app` on macOS, a lower-case `.desktop` file on Linux
pub fn launcher_path(dir: &Path, name: &str) -> PathBuf {
    if MAC {
        dir.join(format!("{name}.app"))
    } else {
        dir.join(format!("{}.desktop", slug(name)))
    }
}

pub fn remove_launcher(path: &Path) {
    let _ = if path.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    };
}

/// "Claude Code - Acme Corp" -> "claude-code-acme-corp"
fn slug(name: &str) -> String {
    let mut out = String::new();
    for c in name.chars().flat_map(char::to_lowercase) {
        if c.is_alphanumeric() {
            out.push(c);
        } else if !out.is_empty() && !out.ends_with('-') {
            out.push('-');
        }
    }
    out.trim_end_matches('-').to_string()
}

/// The words of a launcher's arguments (subcommands and ids, which never hold spaces)
fn words(args: &str) -> Vec<&str> {
    args.split_whitespace().collect()
}

/// One argument of a `.desktop` file's Exec line, quoted the way the Desktop Entry spec asks
fn exec_arg(arg: &str) -> String {
    let arg = arg.replace('%', "%%");
    let reserved = |c: char| " \t\n\"'\\><~|&;$*?#()`".contains(c);
    let quoted = if arg.is_empty() || arg.chars().any(reserved) {
        let mut q = String::from("\"");
        for c in arg.chars() {
            if "\"`$\\".contains(c) {
                q.push('\\');
            }
            q.push(c);
        }
        q.push('"');
        q
    } else {
        arg
    };
    // the Exec value is itself a desktop-entry string, where a backslash is written twice
    quoted.replace('\\', "\\\\")
}

/// A `.desktop` value on one line
fn entry_value(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('\n', "\\n")
        .replace('\t', "\\t")
}

fn xml(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// The shell command a launcher runs: go to the folder, then run the program
fn terminal_command(target: &Path, args: &str, workdir: &Path) -> String {
    let mut cmd = format!(
        "cd {} && exec {}",
        sh_quote(&workdir.display().to_string()),
        sh_quote(&target.display().to_string())
    );
    for w in words(args) {
        cmd.push(' ');
        cmd.push_str(&sh_quote(w));
    }
    cmd
}

fn write_executable(path: &Path, text: &str) -> Result<()> {
    if let Some(d) = path.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::fs::write(path, text).with_context(|| format!("couldn't write {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755))?;
    Ok(())
}

/// Makes a launcher. Terminal launchers open a terminal window running the program (Linux: `Terminal=true`;
/// macOS: a `.command` file, which Terminal opens without asking for permission to be controlled).
pub fn create_shortcut(file: &Path, l: &Launcher) -> Result<()> {
    if MAC {
        return create_app_bundle(file, l);
    }
    let mut exec = exec_arg(&l.target.display().to_string());
    for w in words(l.args) {
        exec.push(' ');
        exec.push_str(&exec_arg(w));
    }
    let mut text = format!(
        "[Desktop Entry]\nType=Application\nVersion=1.5\nName={}\nComment={}\nExec={exec}\nPath={}\nTerminal={}\nCategories=Development;\n",
        entry_value(l.name),
        entry_value(l.description),
        entry_value(&l.workdir.display().to_string()),
        l.terminal,
    );
    if let Some(i) = l.icon {
        text.push_str(&format!("Icon={}\n", entry_value(&i.display().to_string())));
    }
    text.push_str(&format!("X-{MARKER}=true\n"));
    write_executable(file, &text)?;
    // GNOME runs a launcher on the desktop only once it's marked trusted; other desktops ignore this
    if file.parent() != start_menu_dir().as_deref() {
        let _ = Command::new("gio")
            .args([
                "set",
                &file.display().to_string(),
                "metadata::trusted",
                "true",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    Ok(())
}

fn create_app_bundle(app: &Path, l: &Launcher) -> Result<()> {
    remove_launcher(app);
    let contents = app.join("Contents");
    let run = terminal_command(l.target, l.args, l.workdir);
    let script = if l.terminal {
        write_executable(
            &contents.join("Resources").join("run.command"),
            &format!("#!/bin/sh\n{run}\n"),
        )?;
        "#!/bin/sh\nexec /usr/bin/open \"$(dirname \"$0\")/../Resources/run.command\"\n".to_string()
    } else {
        format!("#!/bin/sh\n{run}\n")
    };
    write_executable(&contents.join("MacOS").join("launcher"), &script)?;
    let mut icon_key = String::new();
    if let Some(i) = l.icon {
        let res = contents.join("Resources");
        std::fs::create_dir_all(&res)?;
        if std::fs::copy(i, res.join("icon.icns")).is_ok() {
            icon_key = "  <key>CFBundleIconFile</key><string>icon</string>\n".into();
        }
    }
    let plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIdentifier</key><string>io.github.fauzulkc.claudeseverance.{id}</string>
  <key>CFBundleName</key><string>{name}</string>
  <key>CFBundleDisplayName</key><string>{name}</string>
  <key>CFBundleGetInfoString</key><string>{desc}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>{version}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSUIElement</key><true/>
{icon_key}  <key>{MARKER}</key><true/>
</dict>
</plist>
"#,
        id = slug(l.name),
        name = xml(l.name),
        desc = xml(l.description),
        version = crate::VERSION,
    );
    std::fs::write(contents.join("Info.plist"), plist)?;
    Ok(())
}

/// Launchers in `dir` that Claude Severance made
pub fn shortcuts_with(dir: &Path, marker: &str) -> Vec<PathBuf> {
    std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| match p.extension().and_then(|e| e.to_str()) {
            Some("desktop") => {
                std::fs::read_to_string(p).is_ok_and(|t| t.contains(&format!("X-{marker}=")))
            }
            Some("app") => std::fs::read_to_string(p.join("Contents").join("Info.plist"))
                .is_ok_and(|t| t.contains(&format!("<key>{marker}</key>"))),
            _ => false,
        })
        .collect()
}

pub struct UninstallEntry<'a> {
    pub version: &'a str,
    pub root: &'a Path,
    pub icon: Option<&'a Path>,
    pub exe: &'a Path,
    pub size_kb: u32,
}

/// There's no list of installed programs to join here; the menu has an uninstall launcher instead
pub fn register_uninstall(_e: &UninstallEntry) -> Result<()> {
    Ok(())
}

pub fn unregister_uninstall() {}

pub fn installed_version() -> Option<String> {
    None
}

/// Files in use can be deleted here, so nothing is ever left for later
pub fn remove_later(_dir: &Path) {}

pub fn unblock(_file: &Path) {}

pub fn install_desktop_app() -> Result<()> {
    if !MAC {
        bail!("{NO_DESKTOP_LINUX}");
    }
    let Some(brew) = on_path("brew") else {
        bail!("Get Claude Desktop from claude.ai/download (or install Homebrew), then try again.");
    };
    let ok = Command::new(brew)
        .args(["install", "--cask", "claude"])
        .status()
        .is_ok_and(|s| s.success());
    if !ok {
        bail!("Homebrew couldn't install Claude Desktop. Get it from claude.ai/download.");
    }
    Ok(())
}

/// Anthropic's installer for Claude Code
pub fn install_claude_code() -> Result<()> {
    let ok = Command::new("/bin/sh")
        .args(["-c", "curl -fsSL https://claude.ai/install.sh | bash"])
        .status()
        .is_ok_and(|s| s.success());
    if !ok {
        bail!("Claude Code didn't install. Get it from claude.ai/download.");
    }
    Ok(())
}

pub fn has_winget() -> bool {
    false
}

/// Terminals to try on Linux after `$TERMINAL`: the program, arguments that come first, how it takes the folder
/// (`--x=` joined, `--x` apart, or not at all), and what comes before the command
const LINUX_TERMINALS: &[(&str, &[&str], &str, &str)] = &[
    ("x-terminal-emulator", &[], "", "-e"),
    ("gnome-terminal", &[], "--working-directory=", "--"),
    ("kgx", &[], "--working-directory=", "--"),
    ("ptyxis", &["--new-window"], "--working-directory=", "--"),
    ("konsole", &[], "--workdir", "-e"),
    ("xfce4-terminal", &[], "--working-directory=", "-x"),
    ("kitty", &[], "--directory", ""),
    ("alacritty", &[], "--working-directory", "-e"),
    ("wezterm", &["start"], "--cwd", "--"),
    ("foot", &[], "--working-directory=", ""),
    ("xterm", &[], "", "-e"),
];

/// The command that opens a Linux terminal in `dir` running `exe run <id>`, if there's a terminal (`path` and
/// `terminal` are `PATH` and `TERMINAL`)
fn linux_terminal_command(
    dir: &Path,
    exe: &Path,
    id: &str,
    path: &std::ffi::OsStr,
    terminal: Option<&str>,
) -> Option<Command> {
    if let Some(t) = terminal.filter(|t| !t.trim().is_empty()).and_then(|t| {
        on_path_in(t, path).or_else(|| Some(PathBuf::from(t)).filter(|p| is_executable(p)))
    }) {
        let mut cmd = Command::new(t);
        cmd.current_dir(dir).arg("-e").arg(exe).args(["run", id]);
        return Some(cmd);
    }
    LINUX_TERMINALS
        .iter()
        .find_map(|(name, first, folder, then)| {
            let prog = on_path_in(name, path)?;
            let mut cmd = Command::new(prog);
            cmd.current_dir(dir).args(*first);
            if folder.ends_with('=') {
                cmd.arg(format!("{folder}{}", dir.display()));
            } else if !folder.is_empty() {
                cmd.arg(folder).arg(dir);
            }
            if !then.is_empty() {
                cmd.arg(then);
            }
            cmd.arg(exe).args(["run", id]);
            Some(cmd)
        })
}

/// Opens a terminal window running this account's Claude Code, in its first folder
pub fn open_terminal(account: &Account, paths: &Paths) -> Result<()> {
    let installed = paths.bin().join("severance");
    let exe = if installed.is_file() {
        installed
    } else {
        std::env::current_exe()?
    };
    let dir = account.start_dir(paths);
    let id = account.id.as_str();
    if MAC {
        let file = paths.root.join("terminal").join(format!("{id}.command"));
        let run = terminal_command(&exe, &format!("run {id}"), &dir);
        write_executable(&file, &format!("#!/bin/sh\n{run}\n"))?;
        let status = Command::new("/usr/bin/open").arg(&file).status()?;
        if !status.success() {
            bail!("macOS couldn't open a terminal.");
        }
        return Ok(());
    }
    let path = std::env::var_os("PATH").unwrap_or_default();
    let terminal = std::env::var("TERMINAL").ok();
    match linux_terminal_command(&dir, &exe, id, &path, terminal.as_deref()) {
        Some(mut cmd) => spawn_detached(&mut cmd),
        None => {
            let names: Vec<&str> = LINUX_TERMINALS.iter().map(|t| t.0).collect();
            bail!(
                "No terminal found (looked for {}). Set TERMINAL to yours, or run {} in one.",
                names.join(", "),
                account.alias()
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs_and_quotes_launcher_parts() {
        assert_eq!(slug("Claude Code - Acme Corp"), "claude-code-acme-corp");
        assert_eq!(slug("Claude - Ünïcode!"), "claude-ünïcode");
        assert_eq!(exec_arg("/usr/bin/severance"), "/usr/bin/severance");
        assert_eq!(
            exec_arg("/home/me/My Apps/severance"),
            "\"/home/me/My Apps/severance\""
        );
        assert_eq!(exec_arg("100%"), "100%%");
        assert_eq!(exec_arg("a$b"), "\"a\\\\$b\"");
        assert_eq!(
            terminal_command(Path::new("/x/severance"), "run acme", Path::new("/w/it's")),
            "cd '/w/it'\\''s' && exec '/x/severance' 'run' 'acme'"
        );
    }

    #[test]
    fn makes_and_finds_launchers() {
        let t = tempfile::tempdir().unwrap();
        let icon = t.path().join("icon.png");
        std::fs::write(&icon, b"png").unwrap();
        for (name, terminal) in [("Claude - Acme", false), ("Claude Code - Acme", true)] {
            let launcher = Launcher {
                name,
                target: Path::new("/opt/cs/bin/severance"),
                args: "run acme",
                workdir: Path::new("/home/me/work"),
                icon: Some(&icon),
                description: name,
                terminal,
            };
            let file = launcher_path(t.path(), name);
            create_shortcut(&file, &launcher).unwrap();
            assert!(file.exists(), "{}", file.display());
        }
        std::fs::write(
            t.path().join("other.desktop"),
            "[Desktop Entry]\nName=Other\n",
        )
        .unwrap();
        let found = shortcuts_with(t.path(), MARKER);
        assert_eq!(found.len(), 2, "{found:?}");
        if MAC {
            let run = t
                .path()
                .join("Claude Code - Acme.app/Contents/Resources/run.command");
            assert!(
                std::fs::read_to_string(run)
                    .unwrap()
                    .contains("exec '/opt/cs/bin/severance' 'run' 'acme'")
            );
        } else {
            let text = std::fs::read_to_string(t.path().join("claude-code-acme.desktop")).unwrap();
            assert!(
                text.contains("Exec=/opt/cs/bin/severance run acme\n"),
                "{text}"
            );
            assert!(text.contains("Terminal=true\n") && text.contains("Path=/home/me/work\n"));
        }
        for f in found {
            remove_launcher(&f);
        }
        assert!(shortcuts_with(t.path(), MARKER).is_empty());
    }

    #[test]
    fn picks_a_linux_terminal_with_the_folder() {
        let t = tempfile::tempdir().unwrap();
        let bin = t.path().join("bin");
        std::fs::create_dir_all(&bin).unwrap();
        write_executable(&bin.join("gnome-terminal"), "#!/bin/sh\n").unwrap();
        let path = bin.as_os_str();
        let w = Path::new("/w");
        let exe = Path::new("/x/severance");
        let cmd = linux_terminal_command(w, exe, "acme", path, None).unwrap();
        let args: Vec<String> = cmd
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            args,
            [
                "--working-directory=/w",
                "--",
                "/x/severance",
                "run",
                "acme"
            ]
        );
        write_executable(&bin.join("myterm"), "#!/bin/sh\n").unwrap();
        let cmd = linux_terminal_command(w, exe, "acme", path, Some("myterm")).unwrap();
        assert!(cmd.get_program().to_string_lossy().ends_with("myterm"));
        assert!(linux_terminal_command(w, exe, "acme", "".as_ref(), None).is_none());
    }
}
