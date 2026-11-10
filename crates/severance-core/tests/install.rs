//! The whole install in a sandbox: an update over a 1.x install, adding and removing an account, and uninstall.
//! Nothing here touches the real computer.

use serde_json::{Value, json};
use severance_core::alias::CommandProbe;
use severance_core::install::{self, Request, Sandbox};
use severance_core::{Account, Config, Paths, jsonfile, platform::exe_name};
use std::path::{Path, PathBuf};

struct NoClash;
impl CommandProbe for NoClash {
    fn find(&self, _name: &str) -> Option<String> {
        None
    }
}

fn shim(paths: &Paths, alias: &str) -> PathBuf {
    paths.bin().join(if cfg!(windows) {
        format!("{alias}.cmd")
    } else {
        alias.to_string()
    })
}

fn read(p: &Path) -> String {
    std::fs::read_to_string(p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
}

/// The state 1.1 leaves behind: its scripts in bin, a shim, a shortcut, the profile hook and the 1.x badge
fn make_1x_install(sb: &Sandbox, paths: &Paths) {
    let bin = paths.bin();
    std::fs::create_dir_all(bin.join("fonts")).unwrap();
    for f in [
        "Severance.psm1",
        "SetupWindow.ps1",
        "claude-account.ps1",
        "statusline.ps1",
        "severance.ps1",
    ] {
        std::fs::write(bin.join(f), "# 1.x").unwrap();
    }
    std::fs::write(bin.join("fonts").join("IBMPlexSans-Regular.ttf"), "font").unwrap();
    std::fs::write(
        bin.join("severance.cmd"),
        "@powershell -File \"%~dp0severance.ps1\" %*",
    )
    .unwrap();
    std::fs::write(
        bin.join("claude-acme.cmd"),
        "@echo off\r\npowershell -File \"%~dp0claude-account.ps1\" acme %*\r\n",
    )
    .unwrap();
    std::fs::write(
        bin.join("notes.txt"),
        "not ours to delete? it's in bin, so it goes with bin",
    )
    .unwrap();
    let cfg = json!({
        "version": 1, "defaultCodeProfile": "ask",
        "accounts": [
            {"id": "personal", "name": "Personal", "label": "P", "color": "#3E6FA3", "logo": "", "alias": "claude-personal",
             "email": "me@example.com", "main": true, "paths": []},
            {"id": "acme", "name": "Acme", "label": "A", "color": "#C08A2E", "logo": "", "alias": "claude-acme",
             "email": "me@acme.example", "main": false, "paths": ["D:\\work\\acme"]}
        ]
    });
    jsonfile::write(&paths.config(), &cfg).unwrap();
    // the extra account is signed in; its login must survive the update untouched
    let acme = paths.code_dir("acme");
    std::fs::create_dir_all(&acme).unwrap();
    std::fs::write(acme.join(".credentials.json"), "TOKEN").unwrap();
    std::fs::write(
        acme.join(".claude.json"),
        r#"{"oauthAccount":{"emailAddress":"me@acme.example"}}"#,
    )
    .unwrap();
    // the main account: its own settings with the 1.x badge, and a CLAUDE.md new accounts start from
    let main = paths.main_code_dir();
    std::fs::create_dir_all(main.join("commands")).unwrap();
    std::fs::write(main.join("CLAUDE.md"), "house rules").unwrap();
    std::fs::write(main.join("commands").join("ship.md"), "ship it").unwrap();
    std::fs::write(main.join(".credentials.json"), "MAIN TOKEN").unwrap();
    let old_badge = "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/me/AppData/Local/ClaudeSeverance/bin/statusline.ps1\"";
    jsonfile::write(
        &main.join("settings.json"),
        &json!({"model": "opus", "statusLine": {"type": "command", "command": old_badge}}),
    )
    .unwrap();
    // a 1.x desktop shortcut and profile hook
    std::fs::create_dir_all(sb.dir.join("Desktop")).unwrap();
    std::fs::write(sb.dir.join("Desktop").join("Claude - Acme.lnk"), "powershell.exe -File C:\\Users\\me\\AppData\\Local\\ClaudeSeverance\\bin\\Launch-Desktop.ps1").unwrap();
    std::fs::write(sb.dir.join("Desktop").join("Notes.lnk"), "notepad.exe").unwrap();
    let profile = &sb.profile_files_for_test()[0];
    std::fs::create_dir_all(profile.parent().unwrap()).unwrap();
    std::fs::write(profile, "Set-Alias g git\r\n# >>> claude-severance >>>\r\nif (Test-Path 'x\\claude-account.ps1') { }\r\n# <<< claude-severance <<<\r\n").unwrap();
}

trait ProfileFiles {
    fn profile_files_for_test(&self) -> Vec<PathBuf>;
}
impl ProfileFiles for Sandbox {
    fn profile_files_for_test(&self) -> Vec<PathBuf> {
        install::Host::profile_files(self)
    }
}

/// A folder holding stand-ins for the two programs being installed
fn programs(dir: &Path) -> PathBuf {
    let src = dir.join("new-build");
    std::fs::create_dir_all(&src).unwrap();
    for p in ["severance", "severancew"] {
        std::fs::write(src.join(exe_name(p)), format!("{p} 2.0")).unwrap();
    }
    src
}

fn request(accounts: Vec<Account>, source_dir: PathBuf) -> Request {
    Request {
        accounts,
        logo_sources: Vec::new(),
        removed_ids: Vec::new(),
        desktop_shortcuts: true,
        auto_switch: true,
        allow_scripts: false,
        install_desktop_app: false,
        install_code: false,
        source_dir,
    }
}

#[test]
fn updates_a_1x_install_then_adds_removes_and_uninstalls() {
    let t = tempfile::tempdir().unwrap();
    let sb = Sandbox::new(t.path());
    let paths = sb.paths();
    make_1x_install(&sb, &paths);
    let src = programs(t.path());
    let mut steps = Vec::new();

    // ---- update to 2.0 with the same accounts, plus Globex with a logo and its own command ----
    let mut accounts = Config::load(&paths).unwrap().accounts;
    let mut globex = Account::new("Globex", "", &[], false, &["personal", "acme"], 2);
    globex.alias = "gx".into();
    accounts.push(globex);
    let mut req = request(accounts, src.clone());
    let logo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/logo/png/mark-256.png");
    req.logo_sources.push(("globex".into(), logo));
    let report = install::install(&paths, &sb, &NoClash, req, &mut |s| {
        steps.push(s.to_string())
    })
    .unwrap();
    assert!(report.auto_switch);
    assert!(report.notes.is_empty(), "{:?}", report.notes);
    assert!(steps.iter().any(|s| s == "Set up Globex"), "{steps:?}");

    let bin = paths.bin();
    // 2.0's programs in, 1.x's scripts out
    assert_eq!(read(&bin.join(exe_name("severance"))), "severance 2.0");
    assert!(bin.join(exe_name("severancew")).exists());
    for gone in [
        "Severance.psm1",
        "claude-account.ps1",
        "severance.cmd",
        "fonts",
    ] {
        assert!(!bin.join(gone).exists(), "{gone} should be gone");
    }
    assert!(bin.join("assets").join("severance.ico").exists());
    // a command per account; the 1.x shim replaced
    for (alias, id) in [
        ("claude-personal", "personal"),
        ("claude-acme", "acme"),
        ("gx", "globex"),
    ] {
        let text = read(&shim(&paths, alias));
        assert!(text.contains(&format!("run {id}")), "{alias}: {text}");
    }
    // logins untouched
    assert_eq!(
        read(&paths.code_dir("acme").join(".credentials.json")),
        "TOKEN"
    );
    assert_eq!(
        read(&paths.main_code_dir().join(".credentials.json")),
        "MAIN TOKEN"
    );
    // the new account starts from the main account's files, but never its login
    let gx = paths.code_dir("globex");
    assert_eq!(read(&gx.join("CLAUDE.md")), "house rules");
    assert_eq!(read(&gx.join("commands").join("ship.md")), "ship it");
    assert!(!gx.join(".credentials.json").exists());
    // the badge moved to 2.0's command everywhere, other settings kept
    let main_settings = jsonfile::read(&paths.main_code_dir().join("settings.json"))
        .unwrap()
        .unwrap();
    assert_eq!(main_settings["model"], "opus");
    let cmd = main_settings["statusLine"]["command"].as_str().unwrap();
    assert!(
        cmd.ends_with("statusline") && cmd.contains(&exe_name("severance")),
        "{cmd}"
    );
    let acme_settings = jsonfile::read(&paths.code_dir("acme").join("settings.json"))
        .unwrap()
        .unwrap();
    assert_eq!(
        acme_settings["statusLine"]["command"],
        main_settings["statusLine"]["command"]
    );
    // logo copied in, icons made
    let cfg = Config::load(&paths).unwrap();
    assert_eq!(cfg.get("globex").unwrap().logo, "globex.png");
    assert_eq!(cfg.get("globex").unwrap().alias, "gx");
    assert_eq!(
        cfg.get("acme").unwrap().paths,
        vec!["D:\\work\\acme".to_string()]
    );
    for id in ["personal", "acme", "globex"] {
        assert!(bin.join(format!("icon-{id}.ico")).exists());
    }
    // shortcuts: the 1.x one replaced, someone else's kept, one per account on the desktop and in the Start menu
    let desktop = t.path().join("Desktop");
    assert!(desktop.join("Notes.lnk").exists());
    let acme_lnk = read(&desktop.join("Claude - Acme.lnk"));
    assert!(
        acme_lnk.contains("open acme") && acme_lnk.contains(&exe_name("severancew")),
        "{acme_lnk}"
    );
    let start = t.path().join("Start Menu").join("Claude Severance");
    for name in [
        "Claude - Personal",
        "Claude - Acme",
        "Claude - Globex",
        "Claude Severance - Manage accounts",
        "Uninstall Claude Severance",
    ] {
        assert!(start.join(format!("{name}.lnk")).exists(), "{name}");
    }
    // one auto-switch block, now calling 2.0
    let profile = read(&sb.profile_files_for_test()[0]);
    assert_eq!(profile.matches("# >>> claude-severance >>>").count(), 1);
    assert!(
        profile.contains("run auto") && !profile.contains("claude-account.ps1"),
        "{profile}"
    );
    assert!(profile.contains("Set-Alias g git"));
    let log = sb.log();
    assert!(
        log.contains(&format!("PATH add {}", bin.display())),
        "{log}"
    );
    assert!(
        log.contains(&format!("APPS register {}", severance_core::VERSION)),
        "{log}"
    );

    // ---- a clashing command changes nothing ----
    let before = read(&paths.config());
    let mut bad = cfg.accounts.clone();
    bad[1].alias = "gx".into();
    let e = install::install(
        &paths,
        &sb,
        &NoClash,
        request(bad, src.clone()),
        &mut |_| {},
    )
    .err()
    .unwrap();
    assert!(
        e.to_string().contains("already the command for Globex"),
        "{e}"
    );
    assert_eq!(read(&paths.config()), before);

    // ---- remove Globex: zipped first, then gone ----
    let keep: Vec<Account> = cfg
        .accounts
        .iter()
        .filter(|a| a.id != "globex")
        .cloned()
        .collect();
    let mut req = request(keep, src.clone());
    req.removed_ids = vec!["globex".into()];
    let report = install::install(&paths, &sb, &NoClash, req, &mut |_| {}).unwrap();
    assert!(
        report
            .notes
            .iter()
            .any(|n| n.starts_with("Backup of removed accounts")),
        "{:?}",
        report.notes
    );
    assert!(!paths.code_dir("globex").exists());
    assert!(!shim(&paths, "gx").exists());
    assert!(!paths.logos().join("globex.png").exists());
    assert!(!start.join("Claude - Globex.lnk").exists());
    assert_eq!(std::fs::read_dir(paths.backups()).unwrap().count(), 1);

    // ---- uninstall, keeping the accounts' data ----
    let removal = install::uninstall(&paths, &sb, false, &mut |_| {}).unwrap();
    assert!(removal.kept_data && removal.left.is_none());
    assert_eq!(removal.main_name, "Personal");
    assert_eq!(removal.extras, vec!["Acme".to_string()]);
    assert!(!bin.exists());
    assert!(paths.config().exists());
    assert_eq!(
        read(&paths.code_dir("acme").join(".credentials.json")),
        "TOKEN"
    );
    assert!(!desktop.join("Claude - Acme.lnk").exists() && desktop.join("Notes.lnk").exists());
    assert!(!start.exists());
    let profile = read(&sb.profile_files_for_test()[0]);
    assert!(!profile.contains("claude-severance") && profile.contains("Set-Alias g git"));
    let main_settings: Value = jsonfile::read(&paths.main_code_dir().join("settings.json"))
        .unwrap()
        .unwrap();
    assert!(main_settings.get("statusLine").is_none());
    assert_eq!(main_settings["model"], "opus");
    let log = sb.log();
    assert!(
        log.contains(&format!("PATH remove {}", bin.display())) && log.contains("APPS unregister"),
        "{log}"
    );
}

#[test]
fn a_first_install_makes_a_personal_main_account_from_who_is_signed_in() {
    let t = tempfile::tempdir().unwrap();
    let sb = Sandbox::new(t.path());
    let paths = sb.paths();
    std::fs::create_dir_all(&paths.home).unwrap();
    std::fs::write(
        paths.main_state_file(),
        r#"{"oauthAccount":{"emailAddress":"me@example.com"}}"#,
    )
    .unwrap();
    let accounts = install::current_or_first_accounts(&paths).unwrap();
    assert_eq!(accounts.len(), 1);
    assert_eq!(
        (
            accounts[0].name.as_str(),
            accounts[0].email.as_str(),
            accounts[0].main
        ),
        ("Personal", "me@example.com", true)
    );
    let src = programs(t.path());
    install::install(&paths, &sb, &NoClash, request(accounts, src), &mut |_| {}).unwrap();
    assert!(shim(&paths, "claude-personal").exists());
    // the main account keeps Claude's normal folders: no extra data folders for it
    assert!(!paths.code_dir("personal").exists() && !paths.desktop_dir("personal").exists());
}

#[test]
fn uninstall_with_data_zips_and_removes_everything() {
    let t = tempfile::tempdir().unwrap();
    let sb = Sandbox::new(t.path());
    let paths = sb.paths();
    make_1x_install(&sb, &paths);
    let src = programs(t.path());
    let accounts = Config::load(&paths).unwrap().accounts;
    install::install(&paths, &sb, &NoClash, request(accounts, src), &mut |_| {}).unwrap();
    let removal = install::uninstall(&paths, &sb, true, &mut |_| {}).unwrap();
    assert!(!removal.kept_data);
    let zip = removal.backup.expect("a backup");
    assert!(zip.exists());
    assert!(!paths.root.exists());
    // the main account is never touched beyond the badge
    assert_eq!(
        read(&paths.main_code_dir().join(".credentials.json")),
        "MAIN TOKEN"
    );
}

#[test]
fn each_account_gets_the_launchers_it_asks_for() {
    use severance_core::account::{Launchers, Places};
    let t = tempfile::tempdir().unwrap();
    let sb = Sandbox::new(t.path());
    let paths = sb.paths();
    let src = programs(t.path());
    let work = t.path().join("work");
    std::fs::create_dir_all(&work).unwrap();
    let main = Account::new("Personal", "", &[], true, &[], 0);
    let mut acme = Account::new(
        "Acme",
        "",
        &[work.display().to_string()],
        false,
        &["personal"],
        1,
    );
    acme.launchers = Some(Launchers {
        app: Places::BOTH,
        terminal: Places::BOTH,
    });
    // a 1.x account: no launchers yet, so it gets the defaults (and the desktop app shortcut, since asked for)
    install::install(
        &paths,
        &sb,
        &NoClash,
        request(vec![main, acme.clone()], src.clone()),
        &mut |_| {},
    )
    .unwrap();

    let desktop = t.path().join("Desktop");
    let start = t.path().join("Start Menu").join("Claude Severance");
    let lnk = |dir: &Path, name: &str| dir.join(format!("{name}.lnk"));
    let term = read(&lnk(&start, "Claude Code - Acme"));
    assert!(
        term.contains("run acme") && term.contains(&exe_name("severance")),
        "{term}"
    );
    assert!(lnk(&desktop, "Claude Code - Acme").exists());
    assert!(lnk(&desktop, "Claude - Acme").exists());
    assert!(
        lnk(&start, "Claude Code - Personal").exists(),
        "terminal in the Start menu by default"
    );
    assert!(
        !lnk(&desktop, "Claude Code - Personal").exists(),
        "but not on the desktop"
    );
    assert!(lnk(&desktop, "Claude - Personal").exists());
    let cfg = Config::load(&paths).unwrap();
    assert_eq!(
        cfg.get("personal").unwrap().launchers,
        Some(Launchers::defaults(true)),
        "defaults are saved"
    );

    // turn Acme's off: they go, the others stay
    let mut accounts = cfg.accounts.clone();
    accounts[1].launchers = Some(Launchers {
        app: Places::START_MENU,
        terminal: Places::NONE,
    });
    install::install(&paths, &sb, &NoClash, request(accounts, src), &mut |_| {}).unwrap();
    assert!(
        !lnk(&desktop, "Claude - Acme").exists() && !lnk(&desktop, "Claude Code - Acme").exists()
    );
    assert!(!lnk(&start, "Claude Code - Acme").exists());
    assert!(lnk(&start, "Claude - Acme").exists());
    assert!(lnk(&desktop, "Claude - Personal").exists());
}
