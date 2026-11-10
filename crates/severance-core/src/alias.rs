//! Each account's terminal command, and the check that it doesn't clash with anything.

use crate::{Account, Paths};
use std::path::{Path, PathBuf};

/// Names the shell or Claude treats specially. Never allowed as an account's command.
pub const RESERVED: &[&str] = &[
    "claude",
    "severance",
    "severancew",
    "claude-account",
    "cmd",
    "powershell",
    "pwsh",
    "wsl",
    "bash",
    "git",
    // cmd.exe built-ins
    "assoc",
    "call",
    "cd",
    "chdir",
    "cls",
    "color",
    "copy",
    "date",
    "del",
    "dir",
    "echo",
    "endlocal",
    "erase",
    "exit",
    "for",
    "ftype",
    "goto",
    "if",
    "md",
    "mkdir",
    "mklink",
    "move",
    "path",
    "pause",
    "popd",
    "prompt",
    "pushd",
    "rd",
    "rem",
    "ren",
    "rename",
    "rmdir",
    "set",
    "setlocal",
    "shift",
    "start",
    "time",
    "title",
    "type",
    "ver",
    "verify",
    "vol", // device names Windows won't use as file names
    "con",
    "prn",
    "aux",
    "nul",
    "com1",
    "com2",
    "com3",
    "com4",
    "lpt1",
    "lpt2",
    "lpt3",
    // POSIX shell built-ins and keywords (bash, zsh, fish)
    "alias",
    "bg",
    "builtin",
    "case",
    "command",
    "do",
    "done",
    "elif",
    "else",
    "esac",
    "eval",
    "exec",
    "export",
    "fc",
    "fg",
    "fi",
    "function",
    "hash",
    "jobs",
    "kill",
    "local",
    "read",
    "readonly",
    "return",
    "source",
    "test",
    "then",
    "trap",
    "ulimit",
    "umask",
    "unalias",
    "unset",
    "until",
    "wait",
    "while",
];

/// Finds an existing command with a given name. The real one searches PATH (and, on Windows, PowerShell's aliases,
/// functions and cmdlets); tests use a fake.
pub trait CommandProbe {
    /// Where the command lives (a file path, or "a PowerShell alias"), or `None` when the name is free
    fn find(&self, name: &str) -> Option<String>;
}

/// `None` when `alias` can be the command of account `id`, else a sentence saying why not.
/// Checks, in order: the shape of the name, reserved names, the other accounts, then commands already on this computer
/// (except our own command files in `bin`).
pub fn check(
    alias: &str,
    id: &str,
    others: &[Account],
    probe: &dyn CommandProbe,
) -> Option<String> {
    let a = alias.trim().to_lowercase();
    if let Some(why) = check_shape(alias) {
        return Some(why);
    }
    if RESERVED.contains(&a.as_str()) {
        return Some(format!(
            "{a} is taken by Windows or Claude itself. Pick another name."
        ));
    }
    if let Some(o) = others.iter().find(|o| o.id != id && o.alias() == a) {
        return Some(format!("{a} is already the command for {}.", o.name));
    }
    probe
        .find(&a)
        .map(|where_| format!("{a} is already a command on this PC ({where_}). Pick another name."))
}

/// Only the shape of the name: letters, digits, dots, dashes and underscores, starting with a letter or digit.
pub fn check_shape(alias: &str) -> Option<String> {
    let a = alias.trim().to_lowercase();
    if a.is_empty() {
        return Some("Give it a command name.".into());
    }
    let re = regex::Regex::new(r"^[a-z0-9][a-z0-9._-]{0,39}$").expect("valid regex");
    if !re.is_match(&a) {
        return Some(format!(
            "{alias} can't be a command: use letters, digits, dots, dashes or underscores, starting with a letter or digit."
        ));
    }
    let ext = regex::Regex::new(r"\.(cmd|bat|exe|ps1|com|sh)$").expect("valid regex");
    if a.ends_with('.') || ext.is_match(&a) {
        return Some(format!(
            "{alias} can't be a command: leave off the dot and extension."
        ));
    }
    None
}

/// Searches PATH, skipping our own `bin` folder. On Windows it also asks Windows PowerShell for an alias, function or
/// cmdlet of that name, since those win over files in PowerShell.
pub struct SystemProbe {
    pub own_bin: PathBuf,
}

impl SystemProbe {
    pub fn new(paths: &Paths) -> Self {
        Self {
            own_bin: paths.bin(),
        }
    }
}

impl CommandProbe for SystemProbe {
    fn find(&self, name: &str) -> Option<String> {
        #[cfg(windows)]
        if let Some(kind) = powershell_command_type(name) {
            return Some(format!("a PowerShell {kind}"));
        }
        find_on_path(name, std::env::var_os("PATH").as_deref(), &self.own_bin)
            .map(|p| p.display().to_string())
    }
}

/// The first file on `path_var` that runs as `name`, outside `skip_dir`
pub fn find_on_path(
    name: &str,
    path_var: Option<&std::ffi::OsStr>,
    skip_dir: &Path,
) -> Option<PathBuf> {
    let skip = crate::paths::comparable(skip_dir);
    let exts: Vec<String> = if cfg!(windows) {
        let pathext = std::env::var("PATHEXT").unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into());
        std::iter::once(String::new())
            .chain(
                pathext
                    .split(';')
                    .filter(|e| !e.is_empty())
                    .map(str::to_lowercase),
            )
            .collect()
    } else {
        vec![String::new()]
    };
    for dir in std::env::split_paths(path_var?) {
        if dir.as_os_str().is_empty() || crate::paths::comparable(&dir) == skip {
            continue;
        }
        for ext in &exts {
            // on Windows a bare name only runs when it has an extension PATHEXT knows
            if cfg!(windows) && ext.is_empty() {
                continue;
            }
            let p = dir.join(format!("{name}{ext}"));
            if is_runnable(&p) {
                return Some(p);
            }
        }
    }
    None
}

#[cfg(unix)]
fn is_runnable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.metadata()
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_runnable(p: &Path) -> bool {
    p.is_file()
}

/// "alias", "function", "cmdlet"… when Windows PowerShell knows `name` as something other than a program
#[cfg(windows)]
fn powershell_command_type(name: &str) -> Option<String> {
    use std::os::windows::process::CommandExt;
    // name has passed check_shape, so it is only [a-z0-9._-] and safe inside single quotes
    let script = format!(
        "$c = Get-Command -Name '{name}' -All -ErrorAction SilentlyContinue | Where-Object {{ $_.CommandType -ne 'Application' }} | Select-Object -First 1; if ($c) {{ ([string]$c.CommandType).ToLowerInvariant() }}"
    );
    let out = std::process::Command::new(crate::platform::windows_powershell())
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            &script,
        ])
        .creation_flags(0x0800_0000) // CREATE_NO_WINDOW
        .output()
        .ok()?;
    let kind = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (!kind.is_empty()).then_some(kind)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fake;
    impl CommandProbe for Fake {
        fn find(&self, name: &str) -> Option<String> {
            match name {
                "notepad" => Some("C:\\Windows\\system32\\notepad.exe".into()),
                "ls" | "ac" => Some("a PowerShell alias".into()),
                _ => None,
            }
        }
    }

    fn others() -> Vec<Account> {
        vec![
            Account {
                id: "personal".into(),
                name: "Personal".into(),
                ..Account::default()
            },
            Account {
                id: "acme".into(),
                name: "Acme".into(),
                alias: "acme-cc".into(),
                ..Account::default()
            },
        ]
    }

    #[test]
    fn accepts_a_free_name() {
        assert_eq!(
            check("claude-globex-test-zz9", "globex", &others(), &Fake),
            None
        );
    }

    #[test]
    fn refuses_names_that_clash() {
        for (alias, why) in [
            ("", "command name"),
            ("work 2", "letters, digits"),
            ("-x", "letters, digits"),
            ("glx.cmd", "extension"),
            ("claude", "taken by Windows or Claude"),
            ("dir", "taken by Windows or Claude"),
            ("acme-cc", "command for Acme"),
            ("ac", "PowerShell alias"),
            ("claude-personal", "command for Personal"),
            ("notepad", "already a command on this PC"),
            ("ls", "PowerShell alias"),
        ] {
            let got = check(alias, "globex", &others(), &Fake).unwrap_or_default();
            assert!(got.contains(why), "{alias:?}: {got:?}");
        }
    }

    #[test]
    fn an_account_does_not_clash_with_itself() {
        assert_eq!(check("acme-cc", "acme", &others(), &Fake), None);
    }

    #[test]
    fn path_search_skips_our_own_bin() {
        let t = tempfile::tempdir().unwrap();
        let ours = t.path().join("ours");
        let theirs = t.path().join("theirs");
        std::fs::create_dir_all(&ours).unwrap();
        std::fs::create_dir_all(&theirs).unwrap();
        let file = if cfg!(windows) { "tool.cmd" } else { "tool" };
        for d in [&ours, &theirs] {
            std::fs::write(d.join(file), "x").unwrap();
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(d.join(file), std::fs::Permissions::from_mode(0o755))
                    .unwrap();
            }
        }
        let path = std::env::join_paths([&ours, &theirs]).unwrap();
        assert_eq!(
            find_on_path("tool", Some(&path), &ours),
            Some(theirs.join(file))
        );
        let only_ours = std::env::join_paths([&ours]).unwrap();
        assert_eq!(find_on_path("tool", Some(&only_ours), &ours), None);
    }

    /// The real probe, against commands every runner has
    #[test]
    fn system_probe_finds_real_commands() {
        let probe = SystemProbe {
            own_bin: PathBuf::from("/nonexistent-severance-bin"),
        };
        if cfg!(windows) {
            assert!(probe.find("notepad").is_some());
            assert_eq!(probe.find("ls").as_deref(), Some("a PowerShell alias"));
        } else {
            assert!(probe.find("sh").is_some());
        }
        assert_eq!(probe.find("claude-severance-surely-free-zz9"), None);
    }
}
