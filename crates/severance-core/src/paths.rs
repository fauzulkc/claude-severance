//! Where Claude Severance keeps things.

use anyhow::{Context, Result};
use std::path::{Path, PathBuf};

/// The folders everything else is built from. `root` holds accounts.json, the extra accounts' data, logos and `bin`;
/// `home` is the user's home folder (the main account's `~/.claude` lives there).
#[derive(Clone, Debug)]
pub struct Paths {
    pub root: PathBuf,
    pub home: PathBuf,
}

impl Paths {
    pub fn new(root: impl Into<PathBuf>, home: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            home: home.into(),
        }
    }

    /// The real locations for this user: `%LOCALAPPDATA%\ClaudeSeverance` on Windows (the same as 1.x),
    /// `~/Library/Application Support/Claude Severance` on macOS, `$XDG_DATA_HOME/claude-severance` on Linux.
    pub fn detect() -> Result<Self> {
        let home = dirs::home_dir().context("couldn't find your home folder")?;
        let root = if cfg!(windows) {
            let local = std::env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .or_else(dirs::data_local_dir)
                .context("couldn't find %LOCALAPPDATA%")?;
            local.join("ClaudeSeverance")
        } else if cfg!(target_os = "macos") {
            home.join("Library")
                .join("Application Support")
                .join("Claude Severance")
        } else {
            dirs::data_dir()
                .unwrap_or_else(|| home.join(".local").join("share"))
                .join("claude-severance")
        };
        Ok(Self { root, home })
    }

    pub fn bin(&self) -> PathBuf {
        self.root.join("bin")
    }
    pub fn config(&self) -> PathBuf {
        self.root.join("accounts.json")
    }
    pub fn logos(&self) -> PathBuf {
        self.root.join("logos")
    }
    /// `CLAUDE_CONFIG_DIR` of an extra account
    pub fn code_dir(&self, id: &str) -> PathBuf {
        self.root.join("code").join(id)
    }
    /// Claude Desktop `--user-data-dir` of an extra account
    pub fn desktop_dir(&self, id: &str) -> PathBuf {
        self.root.join("desktop").join(id)
    }
    pub fn desktop_root(&self) -> PathBuf {
        self.root.join("desktop")
    }
    /// The main account's Claude Code folder, `~/.claude`
    pub fn main_code_dir(&self) -> PathBuf {
        self.home.join(".claude")
    }
    /// The main account's Claude Code state file, `~/.claude.json`
    pub fn main_state_file(&self) -> PathBuf {
        self.home.join(".claude.json")
    }
    pub fn backups(&self) -> PathBuf {
        self.home.join("Claude Severance backups")
    }
}

/// Expands `%VAR%` (Windows) and a leading `~`, and drops trailing separators, so paths compare cleanly.
pub fn expand(p: &str) -> String {
    let mut s = p.trim().to_string();
    if s.starts_with('~')
        && let Some(h) = dirs::home_dir()
    {
        s = format!("{}{}", h.display(), &s[1..]);
    }
    if cfg!(windows) {
        let re = regex::Regex::new(r"%([^%]+)%").expect("valid regex");
        s = re
            .replace_all(&s, |c: &regex::Captures| {
                std::env::var(&c[1]).unwrap_or_else(|_| c[0].to_string())
            })
            .into_owned();
    }
    while s.len() > 1 && (s.ends_with('\\') || s.ends_with('/')) && !s.ends_with(":\\") {
        s.pop();
    }
    s
}

/// Lowercased with `\` separators on Windows (paths there are case-insensitive), unchanged elsewhere.
pub fn comparable(p: &Path) -> String {
    let s = expand(&p.to_string_lossy());
    if cfg!(windows) {
        s.replace('/', "\\").to_lowercase()
    } else {
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expand_trims_trailing_separators() {
        assert_eq!(expand("C:\\Work\\"), "C:\\Work");
        assert_eq!(expand("/home/x/"), "/home/x");
    }
}
