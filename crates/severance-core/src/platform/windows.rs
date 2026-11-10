//! Windows: the user PATH and Apps & Features entry in the registry, shortcuts through the shell's COM object,
//! Claude Desktop from the Microsoft Store or the classic installer. Nothing here needs administrator rights.

use crate::{Account, Paths};
use anyhow::{Context, Result, anyhow, bail};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use winreg::RegKey;
use winreg::enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ, KEY_WRITE, REG_EXPAND_SZ};

const UNINSTALL_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeSeverance";
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub fn windows_powershell() -> PathBuf {
    let root = std::env::var_os("SystemRoot")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\Windows"));
    root.join(r"System32\WindowsPowerShell\v1.0\powershell.exe")
}

/// `Start Menu\Programs\Claude Severance`
pub fn start_menu_dir() -> Option<PathBuf> {
    use windows::Win32::System::Com::CoTaskMemFree;
    use windows::Win32::UI::Shell::{FOLDERID_Programs, KF_FLAG_DEFAULT, SHGetKnownFolderPath};
    // SAFETY: the returned buffer is ours to free, once, after copying it out
    let programs = unsafe {
        let p = SHGetKnownFolderPath(&FOLDERID_Programs, KF_FLAG_DEFAULT, None).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as *const _));
        s?
    };
    Some(PathBuf::from(programs).join("Claude Severance"))
}

/// Ctrl+C goes to the Claude Code session this process started; this process just waits for it to end
pub fn ignore_ctrl_c() {
    use windows::Win32::System::Console::SetConsoleCtrlHandler;
    // SAFETY: no handler routine, only the ignore flag for this process
    unsafe {
        let _ = SetConsoleCtrlHandler(None, true);
    }
}

/// Lets colour codes through on older consoles (Windows Terminal always does)
pub fn enable_ansi() {
    use windows::Win32::System::Console::{
        CONSOLE_MODE, ENABLE_VIRTUAL_TERMINAL_PROCESSING, GetConsoleMode, GetStdHandle,
        STD_OUTPUT_HANDLE, SetConsoleMode,
    };
    // SAFETY: plain console calls on this process's own output handle
    unsafe {
        if let Ok(h) = GetStdHandle(STD_OUTPUT_HANDLE) {
            let mut mode = CONSOLE_MODE::default();
            if GetConsoleMode(h, &mut mode).is_ok() {
                let _ = SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
            }
        }
    }
}

// ---------------- Claude Desktop ----------------

/// The Microsoft Store install of Claude: its folder and the id Windows starts it by
struct StoreApp {
    dir: PathBuf,
    app_user_model_id: String,
}

fn store_app() -> Option<StoreApp> {
    use windows::Management::Deployment::PackageManager;
    let pm = PackageManager::new().ok()?;
    let packages = pm
        .FindPackagesByUserSecurityId(&windows::core::HSTRING::new())
        .ok()?;
    let mut best: Option<((u16, u16, u16, u16), StoreApp)> = None;
    for p in packages {
        let Ok(id) = p.Id() else { continue };
        let name = id.Name().map(|s| s.to_string()).unwrap_or_default();
        let publisher = id.Publisher().map(|s| s.to_string()).unwrap_or_default();
        if !name.to_lowercase().contains("claude")
            || !publisher.to_lowercase().contains("anthropic")
        {
            continue;
        }
        let Ok(v) = id.Version() else { continue };
        let version = (v.Major, v.Minor, v.Build, v.Revision);
        let Ok(dir) = p.InstalledPath().map(|s| PathBuf::from(s.to_string())) else {
            continue;
        };
        let family = id.FamilyName().map(|s| s.to_string()).unwrap_or_default();
        let app = manifest_app_id(&dir).unwrap_or_else(|| "Claude".into());
        if best.as_ref().is_none_or(|(bv, _)| version > *bv) {
            best = Some((
                version,
                StoreApp {
                    dir,
                    app_user_model_id: format!("{family}!{app}"),
                },
            ));
        }
    }
    best.map(|(_, a)| a)
}

/// The first `<Application Id="...">` of a package's manifest
fn manifest_app_id(dir: &Path) -> Option<String> {
    let xml = std::fs::read_to_string(dir.join("AppxManifest.xml")).ok()?;
    let re = regex::Regex::new(r#"<Application\s[^>]*\bId="([^"]+)""#).ok()?;
    re.captures(&xml).map(|c| c[1].to_string())
}

fn find_file(dir: &Path, name: &str, depth: usize) -> Option<PathBuf> {
    walkdir::WalkDir::new(dir)
        .max_depth(depth)
        .into_iter()
        .filter_map(Result::ok)
        .find(|e| {
            e.file_type().is_file() && e.file_name().to_string_lossy().eq_ignore_ascii_case(name)
        })
        .map(|e| e.into_path())
}

/// Claude.exe of the Store install or the classic installer, found again every time so app updates don't break
/// anything
pub fn resolve_claude_exe() -> Result<PathBuf> {
    if let Some(app) = store_app() {
        let direct = app.dir.join(r"app\Claude.exe");
        if direct.is_file() {
            return Ok(direct);
        }
        if let Some(f) = find_file(&app.dir, "Claude.exe", 4) {
            return Ok(f);
        }
    }
    let local = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .context("no %LOCALAPPDATA%")?;
    let squirrel = local.join("AnthropicClaude");
    let mut versions: Vec<(Vec<u32>, PathBuf)> = std::fs::read_dir(&squirrel)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            let v = name.strip_prefix("app-")?;
            let nums: Vec<u32> = v
                .split(|c: char| !c.is_ascii_digit() && c != '.')
                .next()?
                .split('.')
                .filter_map(|n| n.parse().ok())
                .collect();
            Some((nums, e.path()))
        })
        .collect();
    versions.sort();
    if let Some((_, dir)) = versions.last()
        && let Some(f) = find_file(dir, "claude.exe", 1)
    {
        return Ok(f);
    }
    bail!("Claude Desktop is not installed.")
}

/// Opens Claude Desktop for an account. The main account starts exactly as the Start menu starts it; an extra
/// account gets its own data folder and Claude Code config.
pub fn start_desktop(account: &Account, paths: &Paths) -> Result<()> {
    if account.main {
        if let Some(app) = store_app() {
            std::process::Command::new("explorer.exe")
                .arg(format!("shell:AppsFolder\\{}", app.app_user_model_id))
                .spawn()
                .context("couldn't start Claude")?;
        } else {
            std::process::Command::new(resolve_claude_exe()?)
                .spawn()
                .context("couldn't start Claude")?;
        }
        return Ok(());
    }
    let exe = resolve_claude_exe()?;
    let data = paths.desktop_dir(&account.id);
    let code = paths.code_dir(&account.id);
    std::fs::create_dir_all(&data)?;
    std::fs::create_dir_all(&code)?;
    let mut cmd = std::process::Command::new(&exe);
    if let Some(dir) = exe.parent() {
        cmd.current_dir(dir);
    }
    // the Code tab of this window keeps its sessions and settings in this account
    cmd.env("CLAUDE_CONFIG_DIR", &code)
        .env_remove("ANTHROPIC_API_KEY");
    cmd.raw_arg(format!("--user-data-dir=\"{}\"", data.display()));
    cmd.spawn()
        .with_context(|| format!("couldn't start {}", exe.display()))?;
    Ok(())
}

// ---------------- environment ----------------

fn hkcu_open(path: &str) -> Result<RegKey> {
    let (k, _) =
        RegKey::predef(HKEY_CURRENT_USER).create_subkey_with_flags(path, KEY_READ | KEY_WRITE)?;
    Ok(k)
}

fn to_wide(s: &str) -> Vec<u8> {
    s.encode_utf16()
        .chain(std::iter::once(0))
        .flat_map(u16::to_le_bytes)
        .collect()
}

/// Adds `dir` to (or removes it from) the user PATH, keeping `%VARS%` in the other entries unexpanded
pub fn set_user_path_entry(dir: &Path, add: bool) -> Result<()> {
    let key = hkcu_open("Environment")?;
    let current: String = key.get_value("Path").unwrap_or_default();
    let want = crate::paths::comparable(dir);
    let mut parts: Vec<String> = current
        .split(';')
        .filter(|p| !p.is_empty() && crate::paths::comparable(Path::new(p)) != want)
        .map(String::from)
        .collect();
    if add {
        parts.push(crate::paths::expand(&dir.to_string_lossy()));
    }
    let value = parts.join(";");
    if value != current {
        key.set_raw_value(
            "Path",
            &winreg::RegValue {
                vtype: REG_EXPAND_SZ,
                bytes: to_wide(&value).into(),
            },
        )?;
        broadcast_environment_change();
    }
    Ok(())
}

/// Sets (or with `None` removes) a user environment variable, as `[Environment]::SetEnvironmentVariable(..., 'User')`
pub fn set_user_env(name: &str, value: Option<&str>) -> Result<()> {
    let key = hkcu_open("Environment")?;
    match value {
        Some(v) => key.set_value(name, &v)?,
        None => {
            let _ = key.delete_value(name);
        }
    }
    broadcast_environment_change();
    Ok(())
}

/// Tells Windows the environment changed, so terminals opened from now on see it
fn broadcast_environment_change() {
    use windows::Win32::Foundation::{LPARAM, WPARAM};
    use windows::Win32::UI::WindowsAndMessaging::{
        HWND_BROADCAST, SMTO_ABORTIFHUNG, SendMessageTimeoutW, WM_SETTINGCHANGE,
    };
    let what: Vec<u16> = "Environment"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    // SAFETY: `what` outlives the call; the timeout bounds it
    unsafe {
        let _ = SendMessageTimeoutW(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            WPARAM(0),
            LPARAM(what.as_ptr() as isize),
            SMTO_ABORTIFHUNG,
            3000,
            None,
        );
    }
}

/// The execution policy that applies to PowerShell profile scripts, and where it's set, as `Get-ExecutionPolicy -List`
/// reports it (Windows PowerShell 5.1)
pub fn profile_execution_policy() -> (String, String) {
    let policies = r"SOFTWARE\Policies\Microsoft\Windows\PowerShell";
    let shell = r"SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell";
    let read = |hive, path: &str| -> Option<String> {
        let k = RegKey::predef(hive)
            .open_subkey_with_flags(path, KEY_READ)
            .ok()?;
        let v: String = k.get_value("ExecutionPolicy").ok()?;
        (!v.is_empty() && !v.eq_ignore_ascii_case("Undefined")).then_some(v)
    };
    let group = |hive| -> Option<String> {
        let k = RegKey::predef(hive)
            .open_subkey_with_flags(policies, KEY_READ)
            .ok()?;
        let enabled: u32 = k.get_value("EnableScripts").ok()?;
        if enabled == 0 {
            Some("Restricted".into())
        } else {
            read(hive, policies)
        }
    };
    for (scope, value) in [
        ("MachinePolicy", group(HKEY_LOCAL_MACHINE)),
        ("UserPolicy", group(HKEY_CURRENT_USER)),
        ("CurrentUser", read(HKEY_CURRENT_USER, shell)),
        ("LocalMachine", read(HKEY_LOCAL_MACHINE, shell)),
    ] {
        if let Some(v) = value {
            return (v, scope.into());
        }
    }
    ("Restricted".into(), "Default".into())
}

/// Lets the user's own profile scripts run: RemoteSigned for the current user only
pub fn allow_profile_scripts() -> Result<()> {
    hkcu_open(r"SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell")?
        .set_value("ExecutionPolicy", &"RemoteSigned")?;
    Ok(())
}

// ---------------- shortcuts ----------------

/// Writes a .lnk through the Windows shell
pub fn create_shortcut(
    lnk: &Path,
    target: &Path,
    args: &str,
    workdir: &Path,
    icon: Option<&Path>,
    description: &str,
) -> Result<()> {
    use windows::Win32::System::Com::{
        CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx,
        IPersistFile,
    };
    use windows::Win32::UI::Shell::{IShellLinkW, ShellLink};
    use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
    use windows::core::{HSTRING, Interface};
    if let Some(d) = lnk.parent() {
        std::fs::create_dir_all(d)?;
    }
    // SAFETY: COM calls on this thread with live arguments; CoInitializeEx may report it was already initialised
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)?;
        link.SetPath(&HSTRING::from(target.as_os_str()))?;
        link.SetArguments(&HSTRING::from(args))?;
        link.SetWorkingDirectory(&HSTRING::from(workdir.as_os_str()))?;
        link.SetDescription(&HSTRING::from(description))?;
        link.SetShowCmd(SW_SHOWNORMAL)?;
        if let Some(i) = icon.filter(|i| i.is_file()) {
            link.SetIconLocation(&HSTRING::from(i.as_os_str()), 0)?;
        }
        let file: IPersistFile = link.cast()?;
        file.Save(&HSTRING::from(lnk.as_os_str()), true)?;
    }
    Ok(())
}

/// .lnk files in `dir` that mention `marker` (in their target or arguments). Shortcuts made by 1.x name
/// `ClaudeSeverance\bin` in their arguments; 2.0's point at `ClaudeSeverance\bin\severancew.exe`.
pub fn shortcuts_with(dir: &Path, marker: &str) -> Vec<PathBuf> {
    let ascii = marker.to_lowercase().into_bytes();
    let wide: Vec<u8> = marker
        .to_lowercase()
        .encode_utf16()
        .flat_map(u16::to_le_bytes)
        .collect();
    std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("lnk")))
        .filter(|p| {
            let Ok(bytes) = std::fs::read(p) else {
                return false;
            };
            let lower: Vec<u8> = bytes.iter().map(u8::to_ascii_lowercase).collect();
            contains(&lower, &ascii) || contains(&lower, &wide)
        })
        .collect()
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && hay.windows(needle.len()).any(|w| w == needle)
}

// ---------------- Settings > Apps ----------------

pub struct UninstallEntry<'a> {
    pub version: &'a str,
    pub root: &'a Path,
    pub icon: Option<&'a Path>,
    pub exe: &'a Path,
    pub size_kb: u32,
}

pub fn register_uninstall(e: &UninstallEntry) -> Result<()> {
    let k = hkcu_open(UNINSTALL_KEY)?;
    let exe = e.exe.display();
    k.set_value("DisplayName", &"Claude Severance")?;
    k.set_value("DisplayVersion", &e.version)?;
    k.set_value("Publisher", &"Claude Severance")?;
    k.set_value("InstallLocation", &e.root.display().to_string())?;
    k.set_value(
        "DisplayIcon",
        &e.icon.map(|i| i.display().to_string()).unwrap_or_default(),
    )?;
    k.set_value("UninstallString", &format!("\"{exe}\" uninstall"))?;
    k.set_value(
        "QuietUninstallString",
        &format!("\"{exe}\" uninstall --yes"),
    )?;
    k.set_value("ModifyPath", &format!("\"{exe}\" setup"))?;
    k.set_value(
        "URLInfoAbout",
        &"https://github.com/fauzulkc/claude-severance",
    )?;
    k.set_value("NoRepair", &1u32)?;
    k.set_value("EstimatedSize", &e.size_kb)?;
    Ok(())
}

pub fn unregister_uninstall() {
    let _ = RegKey::predef(HKEY_CURRENT_USER).delete_subkey_all(UNINSTALL_KEY);
}

/// The version in Settings > Apps, or `None` when Claude Severance isn't installed
pub fn installed_version() -> Option<String> {
    let k = RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey_with_flags(UNINSTALL_KEY, KEY_READ)
        .ok()?;
    k.get_value::<String, _>("DisplayVersion")
        .ok()
        .filter(|v| !v.is_empty())
}

/// Deletes a folder at the next sign-in, for files that are still in use now
pub fn remove_later(dir: &Path) {
    if let Ok(k) = hkcu_open(r"Software\Microsoft\Windows\CurrentVersion\RunOnce") {
        let _ = k.set_value(
            "ClaudeSeveranceCleanup",
            &format!("cmd.exe /c rmdir /s /q \"{}\"", dir.display()),
        );
    }
}

/// Drops the "downloaded from the internet" mark from a file we installed
pub fn unblock(file: &Path) {
    let mut ads = file.as_os_str().to_owned();
    ads.push(":Zone.Identifier");
    let _ = std::fs::remove_file(PathBuf::from(ads));
}

// ---------------- installing Claude ----------------

pub fn has_winget() -> bool {
    crate::alias::find_on_path("winget", std::env::var_os("PATH").as_deref(), Path::new(""))
        .is_some()
}

pub fn install_desktop_app() -> Result<()> {
    if !has_winget() {
        bail!(
            "Claude Desktop is not installed, and winget is not available to install it. Get it from claude.ai/download, then run setup again."
        );
    }
    let status = std::process::Command::new("winget")
        .args([
            "install",
            "--id",
            "Anthropic.Claude",
            "-e",
            "--silent",
            "--accept-source-agreements",
            "--accept-package-agreements",
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .status()?;
    resolve_claude_exe().map(|_| ()).map_err(|_| {
        anyhow!(
            "Claude Desktop didn't install (winget exit code {}). Get it from claude.ai/download, then run setup again.",
            status.code().unwrap_or(-1)
        )
    })
}

/// Anthropic's own Claude Code installer for Windows
pub fn install_claude_code() -> Result<()> {
    std::process::Command::new(windows_powershell())
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "irm https://claude.ai/install.ps1 | iex",
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .status()?;
    Ok(())
}
