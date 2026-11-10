//! macOS and Linux: phase 4 of docs/PLATFORMS-PLAN.md. Until then, Claude Code accounts work (commands, the badge,
//! auto-switch is not wired yet) and anything Desktop-related says it isn't available here yet.

use crate::{Account, Paths};
use anyhow::{Result, bail};
use std::path::{Path, PathBuf};

const LATER: &str = "isn't available on this platform yet (see docs/PLATFORMS-PLAN.md)";

pub fn start_menu_dir() -> Option<PathBuf> {
    None
}

pub fn ignore_ctrl_c() {}

pub fn enable_ansi() {}

pub fn resolve_claude_exe() -> Result<PathBuf> {
    bail!("Finding Claude Desktop {LATER}.")
}

pub fn start_desktop(_account: &Account, _paths: &Paths) -> Result<()> {
    bail!("Opening Claude Desktop for an account {LATER}.")
}

pub fn set_user_path_entry(_dir: &Path, _add: bool) -> Result<()> {
    Ok(())
}

pub fn set_user_env(_name: &str, _value: Option<&str>) -> Result<()> {
    Ok(())
}

/// (policy, scope) that applies to PowerShell profile scripts; there are none to block here
pub fn profile_execution_policy() -> (String, String) {
    ("Unrestricted".into(), "Default".into())
}

pub fn allow_profile_scripts() -> Result<()> {
    Ok(())
}

pub fn create_shortcut(
    _lnk: &Path,
    _target: &Path,
    _args: &str,
    _workdir: &Path,
    _icon: Option<&Path>,
    _description: &str,
) -> Result<()> {
    bail!("Launchers {LATER}.")
}

pub fn shortcuts_with(_dir: &Path, _marker: &str) -> Vec<PathBuf> {
    Vec::new()
}

pub struct UninstallEntry<'a> {
    pub version: &'a str,
    pub root: &'a Path,
    pub icon: Option<&'a Path>,
    pub exe: &'a Path,
    pub size_kb: u32,
}

pub fn register_uninstall(_e: &UninstallEntry) -> Result<()> {
    Ok(())
}

pub fn unregister_uninstall() {}

pub fn installed_version() -> Option<String> {
    None
}

pub fn remove_later(_dir: &Path) {}

pub fn unblock(_file: &Path) {}

pub fn install_desktop_app() -> Result<()> {
    bail!("Installing Claude Desktop {LATER}.")
}

pub fn install_claude_code() -> Result<()> {
    bail!("Installing Claude Code from here {LATER}. Get it from claude.ai/download.")
}

pub fn has_winget() -> bool {
    false
}

pub fn open_terminal(_account: &Account, _paths: &Paths) -> Result<()> {
    bail!("Opening a terminal for an account {LATER}.")
}
