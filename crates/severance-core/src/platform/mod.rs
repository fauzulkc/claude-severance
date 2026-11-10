//! What differs per operating system: `windows.rs`, and `unix.rs` for macOS and Linux.

use std::path::{Path, PathBuf};

/// One launcher: a Windows shortcut, a Linux `.desktop` file or a macOS `.app`
pub struct Launcher<'a> {
    /// The name people see, "Claude - Acme"
    pub name: &'a str,
    pub target: &'a Path,
    pub args: &'a str,
    pub workdir: &'a Path,
    pub icon: Option<&'a Path>,
    pub description: &'a str,
    /// Opens a terminal window running `target` (Windows does this by itself for a console program)
    pub terminal: bool,
}

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use self::windows::*;

#[cfg(not(windows))]
mod unix;
#[cfg(not(windows))]
pub use self::unix::*;

/// `name.exe` on Windows, `name` elsewhere
pub fn exe_name(name: &str) -> String {
    if cfg!(windows) {
        format!("{name}.exe")
    } else {
        name.to_string()
    }
}

/// The user's Documents folder (PowerShell profiles live there)
pub fn documents_dir() -> Option<PathBuf> {
    dirs::document_dir()
}

/// The user's desktop
pub fn desktop_dir() -> Option<PathBuf> {
    dirs::desktop_dir()
}

/// A running Claude Desktop window's process
#[derive(Debug, Clone)]
pub struct DesktopProcess {
    pub pid: u32,
    pub command_line: String,
}

/// Claude Desktop processes (the Store app or the classic install), with their command lines
pub fn desktop_processes() -> Vec<DesktopProcess> {
    use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};
    let Ok(mut sys) = System::new() else {
        return Vec::new();
    };
    sys.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing()
            .with_cmd(UpdateKind::Always)
            .with_exe(UpdateKind::Always),
    );
    sys.processes()
        .values()
        .filter(|p| {
            let name = p.name().to_string_lossy().to_lowercase();
            let exe = p
                .exe()
                .map(|e| e.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            (name == "claude.exe"
                && (exe.contains("\\windowsapps\\") || exe.contains("\\anthropicclaude\\")))
                || (cfg!(target_os = "macos") && exe.contains("/claude.app/contents/macos/"))
                || (cfg!(target_os = "linux")
                    && (name == "claude-desktop" || exe.contains("claude-desktop")))
        })
        .map(|p| DesktopProcess {
            pid: p.pid().as_u32(),
            command_line: p
                .cmd()
                .iter()
                .map(|a| a.to_string_lossy())
                .collect::<Vec<_>>()
                .join(" "),
        })
        .collect()
}

/// Whether a Claude Desktop command line belongs to `dir` (the account's `--user-data-dir`, or the folder of all of
/// them): the path, followed by a quote, a space, a separator or the end
pub fn command_line_uses(command_line: &str, dir: &Path) -> bool {
    let line = command_line.to_lowercase().replace('/', "\\");
    let want = dir.to_string_lossy().to_lowercase().replace('/', "\\");
    let mut from = 0;
    while let Some(i) = line[from..].find(&want) {
        let end = from + i + want.len();
        match line[end..].chars().next() {
            None | Some('"' | '\\' | ' ' | '\t') => return true,
            _ => from = end,
        }
    }
    false
}

/// Closes the Claude Desktop windows of one extra account, or of every extra account when `id` is `None`
pub fn stop_desktop(paths: &crate::Paths, id: Option<&str>) {
    let dir = match id {
        Some(id) => paths.desktop_dir(id),
        None => paths.desktop_root(),
    };
    let mut stopped = false;
    let Ok(mut sys) = sysinfo::System::new() else {
        return;
    };
    sys.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
    for p in desktop_processes()
        .into_iter()
        .filter(|p| command_line_uses(&p.command_line, &dir))
    {
        if let Some(proc_) = sys.process(sysinfo::Pid::from_u32(p.pid)) {
            stopped |= proc_.kill();
        }
    }
    if stopped {
        std::thread::sleep(std::time::Duration::from_secs(2));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_an_accounts_data_folder_exactly() {
        let dir =
            std::path::Path::new("C:\\Users\\me\\AppData\\Local\\ClaudeSeverance\\desktop\\acme");
        assert!(command_line_uses(
            r#"Claude.exe --user-data-dir="C:\Users\me\AppData\Local\ClaudeSeverance\desktop\acme""#,
            dir
        ));
        assert!(command_line_uses(
            r"Claude.exe --user-data-dir=c:\users\me\appdata\local\claudeseverance\desktop\acme --type=gpu",
            dir
        ));
        assert!(!command_line_uses(
            r"Claude.exe --user-data-dir=C:\Users\me\AppData\Local\ClaudeSeverance\desktop\acme2",
            dir
        ));
        assert!(!command_line_uses("Claude.exe", dir));
    }
}
