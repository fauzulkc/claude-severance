//! Install, update, account changes and uninstall: one ordered list of steps, each reported as it finishes.
//!
//! Everything that reaches outside Claude Severance's own folder (shortcuts, the user PATH, Settings > Apps, the
//! PowerShell profiles, closing Claude windows) goes through [`Host`], so tests run the whole install in a sandbox.

use crate::alias::{self, CommandProbe};
use crate::{Account, Config, Paths, backup, claude, hooks, icon, platform, settings};
use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};

/// Marks everything this tool puts outside its folder (shortcut targets, arguments)
pub const MARKER: &str = "ClaudeSeverance";

/// The manager window's program, installed next to `severance` when the build has it
pub const MANAGER: &str = "ClaudeSeverance";

struct Shortcut<'a> {
    name: String,
    target: &'a Path,
    args: String,
    workdir: PathBuf,
    description: String,
}

/// Files 1.x kept in `bin` that 2.0 replaces
const OLD_SCRIPTS: &[&str] = &[
    "Severance.psm1",
    "Setup.ps1",
    "SetupWindow.ps1",
    "Setup-Console.ps1",
    "Uninstall.ps1",
    "Launch-Desktop.ps1",
    "claude-account.ps1",
    "statusline.ps1",
    "severance.ps1",
    "severance.cmd",
];

/// Claude Code files a new extra account starts with, copied from the main account
const SHARED: &[&str] = &[
    "CLAUDE.md",
    "settings.json",
    "commands",
    "agents",
    "skills",
    "hooks",
    "output-styles",
];

static APP_ICON: &[u8] = include_bytes!("../../../src/assets/severance.ico");

/// What the install changes outside Claude Severance's own folder
pub trait Host {
    fn desktop_installed(&self) -> bool;
    fn install_desktop_app(&self) -> Result<()>;
    fn install_claude_code(&self) -> Result<()>;
    fn claude_code_installed(&self, paths: &Paths) -> bool;
    fn desktop_dir(&self) -> Option<PathBuf>;
    fn start_menu_dir(&self) -> Option<PathBuf>;
    fn create_shortcut(
        &self,
        lnk: &Path,
        target: &Path,
        args: &str,
        workdir: &Path,
        icon: Option<&Path>,
        description: &str,
    ) -> Result<()>;
    fn shortcuts_with(&self, dir: &Path, marker: &str) -> Vec<PathBuf>;
    fn set_user_path_entry(&self, dir: &Path, add: bool) -> Result<()>;
    fn set_user_env(&self, name: &str, value: Option<&str>) -> Result<()>;
    fn profile_files(&self) -> Vec<PathBuf>;
    /// (policy, scope) for PowerShell profile scripts
    fn profile_execution_policy(&self) -> (String, String);
    fn allow_profile_scripts(&self) -> Result<()>;
    fn register_uninstall(
        &self,
        version: &str,
        root: &Path,
        icon: Option<&Path>,
        exe: &Path,
        size_kb: u32,
    ) -> Result<()>;
    fn unregister_uninstall(&self);
    fn stop_desktop(&self, paths: &Paths, id: Option<&str>);
    fn remove_later(&self, dir: &Path);
}

/// The real computer
pub struct System;

impl Host for System {
    fn desktop_installed(&self) -> bool {
        platform::resolve_claude_exe().is_ok()
    }
    fn install_desktop_app(&self) -> Result<()> {
        platform::install_desktop_app()
    }
    fn install_claude_code(&self) -> Result<()> {
        platform::install_claude_code()
    }
    fn claude_code_installed(&self, paths: &Paths) -> bool {
        claude::find_cli(paths).is_some()
    }
    fn desktop_dir(&self) -> Option<PathBuf> {
        // launchers elsewhere are phase 4 of docs/PLATFORMS-PLAN.md
        if cfg!(windows) {
            platform::desktop_dir()
        } else {
            None
        }
    }
    fn start_menu_dir(&self) -> Option<PathBuf> {
        platform::start_menu_dir()
    }
    fn create_shortcut(
        &self,
        lnk: &Path,
        target: &Path,
        args: &str,
        workdir: &Path,
        icon: Option<&Path>,
        description: &str,
    ) -> Result<()> {
        platform::create_shortcut(lnk, target, args, workdir, icon, description)
    }
    fn shortcuts_with(&self, dir: &Path, marker: &str) -> Vec<PathBuf> {
        platform::shortcuts_with(dir, marker)
    }
    fn set_user_path_entry(&self, dir: &Path, add: bool) -> Result<()> {
        platform::set_user_path_entry(dir, add)
    }
    fn set_user_env(&self, name: &str, value: Option<&str>) -> Result<()> {
        platform::set_user_env(name, value)
    }
    fn profile_files(&self) -> Vec<PathBuf> {
        if cfg!(windows) {
            hooks::powershell_profiles()
        } else {
            Vec::new()
        }
    }
    fn profile_execution_policy(&self) -> (String, String) {
        platform::profile_execution_policy()
    }
    fn allow_profile_scripts(&self) -> Result<()> {
        platform::allow_profile_scripts()
    }
    fn register_uninstall(
        &self,
        version: &str,
        root: &Path,
        icon: Option<&Path>,
        exe: &Path,
        size_kb: u32,
    ) -> Result<()> {
        platform::register_uninstall(&platform::UninstallEntry {
            version,
            root,
            icon,
            exe,
            size_kb,
        })
    }
    fn unregister_uninstall(&self) {
        platform::unregister_uninstall()
    }
    fn stop_desktop(&self, paths: &Paths, id: Option<&str>) {
        platform::stop_desktop(paths, id)
    }
    fn remove_later(&self, dir: &Path) {
        platform::remove_later(dir)
    }
}

/// A pretend computer inside one folder, for tests and `severance --sandbox <dir>`: shortcuts are small text files,
/// and PATH, environment and Settings > Apps changes are written to `host.log`. Claude counts as installed.
pub struct Sandbox {
    pub dir: PathBuf,
}

impl Sandbox {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }
    /// The `Paths` that go with this sandbox
    pub fn paths(&self) -> Paths {
        Paths::new(self.dir.join("ClaudeSeverance"), self.dir.join("home"))
    }
    pub fn log(&self) -> String {
        std::fs::read_to_string(self.dir.join("host.log")).unwrap_or_default()
    }
    fn note(&self, line: &str) {
        use std::io::Write;
        let _ = std::fs::create_dir_all(&self.dir);
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.dir.join("host.log"))
        {
            let _ = writeln!(f, "{line}");
        }
    }
}

impl Host for Sandbox {
    fn desktop_installed(&self) -> bool {
        true
    }
    fn install_desktop_app(&self) -> Result<()> {
        self.note("install Claude Desktop");
        Ok(())
    }
    fn install_claude_code(&self) -> Result<()> {
        self.note("install Claude Code");
        Ok(())
    }
    fn claude_code_installed(&self, _paths: &Paths) -> bool {
        true
    }
    fn desktop_dir(&self) -> Option<PathBuf> {
        Some(self.dir.join("Desktop"))
    }
    fn start_menu_dir(&self) -> Option<PathBuf> {
        Some(self.dir.join("Start Menu").join("Claude Severance"))
    }
    fn create_shortcut(
        &self,
        lnk: &Path,
        target: &Path,
        args: &str,
        _workdir: &Path,
        icon: Option<&Path>,
        _description: &str,
    ) -> Result<()> {
        if let Some(d) = lnk.parent() {
            std::fs::create_dir_all(d)?;
        }
        let icon = icon.map(|i| i.display().to_string()).unwrap_or_default();
        std::fs::write(lnk, format!("{}\n{args}\n{icon}\n", target.display()))?;
        Ok(())
    }
    fn shortcuts_with(&self, dir: &Path, marker: &str) -> Vec<PathBuf> {
        std::fs::read_dir(dir)
            .into_iter()
            .flatten()
            .filter_map(Result::ok)
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == "lnk"))
            .filter(|p| std::fs::read_to_string(p).is_ok_and(|t| t.contains(marker)))
            .collect()
    }
    fn set_user_path_entry(&self, dir: &Path, add: bool) -> Result<()> {
        self.note(&format!(
            "PATH {} {}",
            if add { "add" } else { "remove" },
            dir.display()
        ));
        Ok(())
    }
    fn set_user_env(&self, name: &str, value: Option<&str>) -> Result<()> {
        self.note(&format!("ENV {name}={}", value.unwrap_or("")));
        Ok(())
    }
    fn profile_files(&self) -> Vec<PathBuf> {
        vec![
            self.dir
                .join("Documents")
                .join("WindowsPowerShell")
                .join("Microsoft.PowerShell_profile.ps1"),
        ]
    }
    fn profile_execution_policy(&self) -> (String, String) {
        ("RemoteSigned".into(), "CurrentUser".into())
    }
    fn allow_profile_scripts(&self) -> Result<()> {
        Ok(())
    }
    fn register_uninstall(
        &self,
        version: &str,
        _root: &Path,
        _icon: Option<&Path>,
        exe: &Path,
        _size_kb: u32,
    ) -> Result<()> {
        self.note(&format!("APPS register {version} {}", exe.display()));
        Ok(())
    }
    fn unregister_uninstall(&self) {
        self.note("APPS unregister");
    }
    fn stop_desktop(&self, _paths: &Paths, id: Option<&str>) {
        self.note(&format!(
            "close Claude Desktop {}",
            id.unwrap_or("(all extra accounts)")
        ));
    }
    fn remove_later(&self, dir: &Path) {
        self.note(&format!("remove later {}", dir.display()));
    }
}

/// What to install
pub struct Request {
    /// Every account, in order. An account's `logo` is the file already stored, or empty.
    pub accounts: Vec<Account>,
    /// New logos to copy in: (account id, image file)
    pub logo_sources: Vec<(String, PathBuf)>,
    /// Accounts to back up and delete
    pub removed_ids: Vec<String>,
    pub desktop_shortcuts: bool,
    pub auto_switch: bool,
    /// Let PowerShell run profile scripts (current user, RemoteSigned) so auto-switch can work
    pub allow_scripts: bool,
    pub install_desktop_app: bool,
    pub install_code: bool,
    /// Folder holding the `severance` and `severancew` programs to install
    pub source_dir: PathBuf,
}

pub struct Report {
    pub accounts: Vec<Account>,
    pub auto_switch: bool,
    pub notes: Vec<String>,
}

fn policy_blocks(policy: &str) -> bool {
    policy.eq_ignore_ascii_case("Restricted") || policy.eq_ignore_ascii_case("AllSigned")
}

fn set_by_group_policy(scope: &str) -> bool {
    scope == "MachinePolicy" || scope == "UserPolicy"
}

/// What `install` will use when the user hasn't chosen: the current accounts, or a first main account named
/// "Personal" signed in as whoever `~/.claude.json` says
pub fn current_or_first_accounts(paths: &Paths) -> Result<Vec<Account>> {
    if let Some(cfg) = Config::load_if_present(paths)? {
        return Ok(cfg.accounts);
    }
    let email = claude::read_sign_in(&paths.main_state_file())
        .map(|s| s.email)
        .unwrap_or_default();
    Ok(vec![Account::new("Personal", &email, &[], true, &[], 0)])
}

/// Installs or updates Claude Severance with these accounts. Every command name is checked before anything changes.
pub fn install(
    paths: &Paths,
    host: &dyn Host,
    probe: &dyn CommandProbe,
    req: Request,
    step: &mut dyn FnMut(&str),
) -> Result<Report> {
    let mut notes = Vec::new();
    let bin = paths.bin();

    if req.install_desktop_app {
        host.install_desktop_app()?;
        step("Installed Claude Desktop");
    } else if !host.desktop_installed() {
        bail!(
            "Claude Desktop is not installed. Get it from claude.ai/download, then run setup again."
        );
    }
    if req.install_code {
        if host.install_claude_code().is_ok() && host.claude_code_installed(paths) {
            step("Installed Claude Code");
        } else {
            notes.push("Claude Code didn't install. Desktop accounts work; install Claude Code later and run 'severance repair'.".into());
        }
    }

    // ---- the accounts, checked before anything changes ----
    let old = Config::load_if_present(paths).ok().flatten();
    let mut accounts = Vec::new();
    for a in &req.accounts {
        let mut a = a.clone();
        a.alias = a.alias();
        a.paths.retain(|p| !p.trim().is_empty());
        a.launchers = Some(a.launchers_or_default(req.desktop_shortcuts));
        if let Some((_, src)) = req.logo_sources.iter().find(|(id, _)| *id == a.id) {
            match icon::import_logo(src, &a.id, paths) {
                Ok(name) => a.logo = name,
                Err(e) => {
                    notes.push(format!(
                        "Couldn't use the logo for {} ({e}), so it shows its letter.",
                        a.name
                    ));
                    a.logo.clear();
                }
            }
        }
        if a.logo_path(paths).is_none() {
            a.logo.clear();
            let _ = std::fs::remove_file(paths.logos().join(format!("{}.png", a.id)));
        }
        accounts.push(a);
    }
    for a in &accounts {
        if let Some(why) = alias::check(&a.alias, &a.id, &accounts, probe) {
            bail!("The command for {} can't be {}: {why}", a.name, a.alias);
        }
    }
    let mut cfg = Config::new(accounts);
    if let Some(o) = &old {
        cfg.default_code_profile = o.default_code_profile.clone();
        cfg.extra = o.extra.clone();
    }
    cfg.validate()?;

    let removed: Vec<String> = req
        .removed_ids
        .iter()
        .filter(|id| !id.is_empty() && cfg.get(id).is_err())
        .cloned()
        .collect();
    if !removed.is_empty() {
        let zip = backup::backup_accounts(paths, &removed)?;
        for id in &removed {
            remove_account_data(paths, host, id);
        }
        let names: Vec<String> = removed
            .iter()
            .map(|id| {
                old.as_ref()
                    .and_then(|o| o.get(id).ok())
                    .map(|a| a.name.clone())
                    .unwrap_or_else(|| id.clone())
            })
            .collect();
        step(&format!("Backed up and removed {}", names.join(", ")));
        if let Some(z) = zip {
            notes.push(format!("Backup of removed accounts: {}", z.display()));
        }
    }
    cfg.save(paths)?;

    // ---- files ----
    std::fs::create_dir_all(&bin)?;
    clean_old_copies(&bin);
    for name in ["severance", "severancew"] {
        let file = platform::exe_name(name);
        let from = req.source_dir.join(&file);
        let to = bin.join(&file);
        if !from.is_file() {
            bail!(
                "{} is missing next to this program, so it can't be installed.",
                file
            );
        }
        if crate::paths::comparable(&from) != crate::paths::comparable(&to) {
            replace_file(&from, &to)?;
        }
        platform::unblock(&to);
    }
    // the manager window is optional: a build without it installs the command line only
    let manager = platform::exe_name(MANAGER);
    let from = req.source_dir.join(&manager);
    if from.is_file() {
        let to = bin.join(&manager);
        if crate::paths::comparable(&from) != crate::paths::comparable(&to) {
            replace_file(&from, &to)?;
        }
        platform::unblock(&to);
    }
    for f in OLD_SCRIPTS {
        let _ = std::fs::remove_file(bin.join(f));
    }
    let _ = std::fs::remove_dir_all(bin.join("fonts"));
    let app_icon = bin.join("assets").join("severance.ico");
    std::fs::create_dir_all(bin.join("assets"))?;
    if std::fs::read(&app_icon).ok().as_deref() != Some(APP_ICON) {
        // an icon an open window still uses can't be replaced; the copy there is fine
        if std::fs::write(&app_icon, APP_ICON).is_err() && !app_icon.exists() {
            bail!("couldn't write {}", app_icon.display());
        }
    }
    step("Copied Claude Severance to your PC");

    // ---- clean what an earlier run made ----
    let desktop = host.desktop_dir();
    if let Some(d) = &desktop {
        for lnk in host.shortcuts_with(d, MARKER) {
            let _ = std::fs::remove_file(lnk);
        }
    }
    let start_menu = host.start_menu_dir();
    if let Some(sm) = &start_menu {
        let _ = std::fs::remove_dir_all(sm);
        std::fs::create_dir_all(sm)?;
    }
    for shim in shims(paths) {
        let _ = std::fs::remove_file(shim);
    }
    if let Ok(rd) = std::fs::read_dir(&bin) {
        for e in rd.filter_map(Result::ok) {
            let n = e.file_name().to_string_lossy().to_string();
            if n.starts_with("icon-") && n.ends_with(".ico") {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }

    // ---- accounts ----
    let main_code = cfg.main().code_dir(paths);
    let launcher = bin.join(platform::exe_name("severancew"));
    let exe = bin.join(platform::exe_name("severance"));
    for a in &cfg.accounts {
        let code = a.code_dir(paths);
        let is_new = !code.exists();
        std::fs::create_dir_all(&code)?;
        if let Some(d) = a.desktop_dir(paths) {
            std::fs::create_dir_all(d)?;
        }
        if is_new && !a.main && main_code.exists() {
            for item in SHARED {
                let from = main_code.join(item);
                if from.exists() {
                    copy_all(&from, &code.join(item))?;
                }
            }
        }
        match settings::set_status_line(&code.join("settings.json"), paths) {
            Ok(settings::Badge::KeptTheirs) => notes.push(format!(
                "Kept your own status line for {} (no account badge there).",
                a.name
            )),
            Ok(_) => {}
            Err(_) => notes.push(format!(
                "No account badge for {}: its settings.json couldn't be read.",
                a.name
            )),
        }
        let icon = icon::write_account_icon(a, paths).ok();
        let l = a.launchers_or_default(req.desktop_shortcuts);
        // the app: Claude Desktop for this account, through severancew (no console window)
        let app = Shortcut {
            name: a.shortcut_name(),
            target: &launcher,
            args: format!("open {}", a.id),
            workdir: bin.clone(),
            description: format!("Claude Desktop - {}", a.name),
        };
        // the terminal: this account's Claude Code, in its first folder
        let term = Shortcut {
            name: a.terminal_shortcut_name(),
            target: &exe,
            args: format!("run {}", a.id),
            workdir: a.start_dir(paths),
            description: format!("Claude Code - {}", a.name),
        };
        for (sc, places) in [(&app, l.app), (&term, l.terminal)] {
            for (on, dir) in [(places.desktop, &desktop), (places.start_menu, &start_menu)] {
                if on && let Some(d) = dir {
                    host.create_shortcut(
                        &d.join(format!("{}.lnk", sc.name)),
                        sc.target,
                        &sc.args,
                        &sc.workdir,
                        icon.as_deref(),
                        &sc.description,
                    )?;
                }
            }
        }
        write_shim(&bin, &a.alias(), &a.id)?;
        step(&format!("Set up {}", a.name));
    }

    // ---- Start menu, commands, Settings > Apps ----
    if let Some(sm) = &start_menu {
        let manager = bin.join(platform::exe_name(MANAGER));
        let (target, args) = if manager.is_file() {
            (&manager, "")
        } else {
            (&exe, "setup")
        };
        host.create_shortcut(
            &sm.join("Claude Severance - Manage accounts.lnk"),
            target,
            args,
            &bin,
            Some(&app_icon),
            "Add, rename or remove Claude accounts, and their launchers",
        )?;
        host.create_shortcut(
            &sm.join("Uninstall Claude Severance.lnk"),
            &exe,
            "uninstall",
            &bin,
            Some(&app_icon),
            "Go back to a single Claude",
        )?;
    }
    step("Added the launchers");

    host.set_user_path_entry(&bin, true)?;
    host.set_user_env(
        "CLAUDE_SEVERANCE_HOME",
        Some(&paths.root.display().to_string()),
    )?;
    step("Added each account's command, and severance");

    notes.extend(settings::sync_update_settings(&cfg, paths));
    step("Matched Claude Code update settings across accounts");

    let profiles = host.profile_files();
    let mut auto_on = false;
    if req.auto_switch && !profiles.is_empty() {
        let (mut policy, scope) = host.profile_execution_policy();
        if policy_blocks(&policy) && req.allow_scripts && !set_by_group_policy(&scope) {
            let _ = host.allow_profile_scripts();
            policy = host.profile_execution_policy().0;
        }
        if policy_blocks(&policy) {
            hooks::remove_from(&profiles, hooks::START, hooks::END)?;
            notes.push("Auto-switch is off: PowerShell scripts are blocked on this PC. Use each account's own command.".into());
        } else {
            hooks::add_to(&profiles, &exe)?;
            auto_on = true;
            step("Turned on auto-switch for claude");
        }
    } else {
        hooks::remove_from(&profiles, hooks::START, hooks::END)?;
    }

    let size_kb = dir_size(&bin) / 1024;
    host.register_uninstall(
        crate::VERSION,
        &paths.root,
        Some(&app_icon),
        &exe,
        size_kb as u32,
    )?;
    step("Added Claude Severance to Settings > Apps");

    Ok(Report {
        accounts: cfg.accounts,
        auto_switch: auto_on,
        notes,
    })
}

/// What an uninstall did
pub struct Removal {
    pub backup: Option<PathBuf>,
    /// A folder that was still in use and goes at the next sign-in
    pub left: Option<PathBuf>,
    pub kept_data: bool,
    pub main_name: String,
    pub extras: Vec<String>,
}

/// Removes everything Claude Severance added. Extra accounts' data stays unless `remove_data`, so installing again
/// brings them back signed in; with `remove_data` it is zipped first, without logins.
pub fn uninstall(
    paths: &Paths,
    host: &dyn Host,
    remove_data: bool,
    step: &mut dyn FnMut(&str),
) -> Result<Removal> {
    let cfg = Config::load_if_present(paths).ok().flatten();
    let extras: Vec<Account> = cfg
        .as_ref()
        .map(|c| c.accounts.iter().filter(|a| !a.main).cloned().collect())
        .unwrap_or_default();

    host.stop_desktop(paths, None);
    step("Closed the extra accounts' windows");

    let mut zip = None;
    if remove_data && !extras.is_empty() {
        let ids: Vec<String> = extras.iter().map(|a| a.id.clone()).collect();
        zip = backup::backup_accounts(paths, &ids)?;
        step("Zipped the extra accounts, without their logins");
    }

    let main_settings = paths.main_code_dir().join("settings.json");
    settings::remove_status_line(&main_settings)?;
    let _ = std::fs::remove_file(paths.main_code_dir().join("settings.json.bak-severance"));
    step("Removed the account badge from your main Claude Code");

    if let Some(d) = host.desktop_dir() {
        for lnk in host.shortcuts_with(&d, MARKER) {
            let _ = std::fs::remove_file(lnk);
        }
    }
    if let Some(sm) = host.start_menu_dir() {
        let _ = std::fs::remove_dir_all(sm);
    }
    step("Removed shortcuts and Start menu entries");

    hooks::remove_from(&host.profile_files(), hooks::START, hooks::END)?;
    host.set_user_path_entry(&paths.bin(), false)?;
    host.set_user_env("CLAUDE_SEVERANCE_HOME", None)?;
    step("Removed the commands and auto-switch");

    host.unregister_uninstall();
    step("Removed Claude Severance from Settings > Apps");

    let target = if remove_data {
        paths.root.clone()
    } else {
        paths.bin()
    };
    let mut left = None;
    if target.exists() && remove_tree(&target).is_err() {
        // this program, or a window, is still using a file there
        host.remove_later(&target);
        left = Some(target);
    }
    step(if remove_data {
        "Removed the extra accounts from this PC"
    } else {
        "Removed Claude Severance's files"
    });

    Ok(Removal {
        backup: zip,
        left,
        kept_data: !remove_data && !extras.is_empty(),
        main_name: cfg
            .as_ref()
            .map(|c| c.main().name.clone())
            .unwrap_or_else(|| "Your main account".into()),
        extras: extras.into_iter().map(|a| a.name).collect(),
    })
}

/// Deletes an extra account's Claude Code and Claude Desktop data and its logo (after closing its window)
pub fn remove_account_data(paths: &Paths, host: &dyn Host, id: &str) {
    host.stop_desktop(paths, Some(id));
    let _ = std::fs::remove_dir_all(paths.code_dir(id));
    let _ = std::fs::remove_dir_all(paths.desktop_dir(id));
    let _ = std::fs::remove_file(paths.logos().join(format!("{id}.png")));
}

/// Our command files in `bin`: 2.0's and 1.x's
pub fn shims(paths: &Paths) -> Vec<PathBuf> {
    let Ok(rd) = std::fs::read_dir(paths.bin()) else {
        return Vec::new();
    };
    rd.filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.is_file())
        .filter(|p| {
            let ext = p.extension().map(|e| e.to_string_lossy().to_lowercase());
            let text = std::fs::read_to_string(p).unwrap_or_default();
            match ext.as_deref() {
                Some("cmd") => text.contains("claude-account.ps1") || text.contains(SHIM_MARK),
                None => text.contains(SHIM_MARK),
                _ => false,
            }
        })
        .collect()
}

const SHIM_MARK: &str = "severance-shim";

/// The command file for an account: `<alias>.cmd` on Windows, an executable `<alias>` script elsewhere
fn write_shim(bin: &Path, alias: &str, id: &str) -> Result<()> {
    if cfg!(windows) {
        let text =
            format!("@echo off\r\nrem {SHIM_MARK}\r\n\"%~dp0severance.exe\" run {id} %*\r\n");
        std::fs::write(bin.join(format!("{alias}.cmd")), text)?;
    } else {
        let file = bin.join(alias);
        std::fs::write(
            &file,
            format!(
                "#!/bin/sh\n# {SHIM_MARK}\nexec \"$(dirname \"$0\")/severance\" run {id} \"$@\"\n"
            ),
        )?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o755))?;
        }
    }
    Ok(())
}

/// Copies `from` over `to`. A program that is running can't be overwritten on Windows, but it can be renamed, so the
/// old one is moved aside first and removed the next time.
fn replace_file(from: &Path, to: &Path) -> Result<()> {
    if std::fs::copy(from, to).is_ok() {
        return Ok(());
    }
    if to.exists() {
        let aside = to.with_extension(format!("old-{}", std::process::id()));
        std::fs::rename(to, &aside).with_context(|| format!("{} is in use", to.display()))?;
    }
    std::fs::copy(from, to).with_context(|| format!("couldn't copy {}", to.display()))?;
    Ok(())
}

/// Removes programs moved aside by an earlier update
fn clean_old_copies(bin: &Path) {
    if let Ok(rd) = std::fs::read_dir(bin) {
        for e in rd.filter_map(Result::ok) {
            if e.path()
                .extension()
                .is_some_and(|x| x.to_string_lossy().starts_with("old-"))
            {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
}

fn copy_all(from: &Path, to: &Path) -> Result<()> {
    if from.is_file() {
        if let Some(d) = to.parent() {
            std::fs::create_dir_all(d)?;
        }
        std::fs::copy(from, to)?;
        return Ok(());
    }
    for e in walkdir::WalkDir::new(from)
        .into_iter()
        .filter_map(Result::ok)
    {
        let rel = e.path().strip_prefix(from).expect("walked inside");
        let dest = to.join(rel);
        if e.file_type().is_dir() {
            std::fs::create_dir_all(&dest)?;
        } else if e.file_type().is_file()
            && !backup::NEVER.contains(&e.file_name().to_string_lossy().as_ref())
        {
            std::fs::copy(e.path(), &dest)?;
        }
    }
    Ok(())
}

/// Deletes a folder, carrying on past files in use; `Err` when something was left
fn remove_tree(dir: &Path) -> Result<()> {
    let mut failed = false;
    for e in walkdir::WalkDir::new(dir)
        .contents_first(true)
        .into_iter()
        .filter_map(Result::ok)
    {
        let r = if e.file_type().is_dir() {
            std::fs::remove_dir(e.path())
        } else {
            std::fs::remove_file(e.path())
        };
        failed |= r.is_err();
    }
    if failed || dir.exists() {
        bail!("some files in {} are in use", dir.display())
    } else {
        Ok(())
    }
}

fn dir_size(dir: &Path) -> u64 {
    walkdir::WalkDir::new(dir)
        .into_iter()
        .filter_map(Result::ok)
        .filter_map(|e| e.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum()
}
