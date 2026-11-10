//! The Claude Severance manager window: edit accounts and where their launchers go, then save through the same
//! install steps as `severance`. `--preview` opens it on sample accounts in a throwaway folder; `--sandbox <dir>`
//! (or `SEVERANCE_SANDBOX`) on a folder of your choice. Neither changes anything else.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use base64::Engine;
use serde::{Deserialize, Serialize};
use severance_core::account::{Launchers, PALETTE};
use severance_core::alias::{self, SystemProbe};
use severance_core::install::{self, Host, Request, Sandbox, System};
use severance_core::{Account, Config, Paths, claude, hooks, icon, platform};
use std::path::PathBuf;
use tauri::{Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_dialog::DialogExt;

/// The real computer, or a sandbox folder
struct Ctx {
    paths: Paths,
    sandbox: Option<PathBuf>,
}

impl Ctx {
    fn host(&self) -> Box<dyn Host> {
        match &self.sandbox {
            Some(d) => Box::new(Sandbox::new(d)),
            None => Box::new(System),
        }
    }

    /// Desktop shortcuts and auto-switch as they are now (or the defaults, before the first install)
    fn current(&self) -> (bool, bool) {
        let host = self.host();
        if !self.paths.config().exists() {
            return (true, true);
        }
        let desktop = host
            .desktop_dir()
            .is_some_and(|d| !host.shortcuts_with(&d, install::MARKER).is_empty());
        (desktop, hooks::present_in(&host.profile_files()))
    }
}

fn err(e: impl std::fmt::Display) -> String {
    format!("{e:#}")
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct View {
    version: &'static str,
    sandbox: bool,
    installed: bool,
    palette: Vec<&'static str>,
    platform_launchers: bool,
    auto_switch: bool,
    accounts: Vec<AccountView>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AccountView {
    account: Account,
    sign_in: SignInView,
    check: &'static str,
    logo_data: Option<String>,
}

#[derive(Serialize)]
struct SignInView {
    email: String,
    org: String,
}

fn data_url(img: &image::RgbaImage) -> Option<String> {
    let mut png = Vec::new();
    image::DynamicImage::ImageRgba8(img.clone())
        .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
        .ok()?;
    Some(format!(
        "data:image/png;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(png)
    ))
}

#[tauri::command]
fn state(ctx: State<'_, Ctx>) -> Result<View, String> {
    let (desktop, auto_switch) = ctx.current();
    let accounts = install::current_or_first_accounts(&ctx.paths).map_err(err)?;
    let cfg = Config::new(accounts.clone());
    let statuses = claude::status(&cfg, &ctx.paths);
    let views = accounts
        .into_iter()
        .zip(statuses)
        .map(|(mut a, s)| {
            a.launchers = Some(a.launchers_or_default(desktop));
            let logo_data = a
                .logo_path(&ctx.paths)
                .and_then(|p| icon::read_image(&p).ok())
                .and_then(|i| data_url(&icon::contain(&i, 96)));
            AccountView {
                account: a,
                sign_in: SignInView {
                    email: s.signed_in,
                    org: s.org,
                },
                check: s.check,
                logo_data,
            }
        })
        .collect();
    Ok(View {
        version: severance_core::VERSION,
        sandbox: ctx.sandbox.is_some(),
        installed: ctx.paths.config().exists(),
        palette: PALETTE.to_vec(),
        platform_launchers: cfg!(windows),
        auto_switch,
        accounts: views,
    })
}

#[tauri::command]
async fn check_alias(
    ctx: State<'_, Ctx>,
    alias: String,
    id: String,
    accounts: Vec<Account>,
) -> Result<Option<String>, String> {
    Ok(alias::check(
        &alias,
        &id,
        &accounts,
        &SystemProbe::new(&ctx.paths),
    ))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Picked {
    path: String,
    data_url: String,
}

#[tauri::command]
async fn pick_logo(app: tauri::AppHandle) -> Result<Option<Picked>, String> {
    let Some(file) = app
        .dialog()
        .file()
        .set_title("Choose a logo")
        .add_filter("Images", &icon::LOGO_TYPES)
        .blocking_pick_file()
    else {
        return Ok(None);
    };
    let path = file.into_path().map_err(err)?;
    let img = icon::read_image(&path)
        .map_err(|_| "That file isn't an image this can use.".to_string())?;
    let data_url = data_url(&icon::contain(&img, 96)).ok_or("Couldn't show that image.")?;
    Ok(Some(Picked {
        path: path.display().to_string(),
        data_url,
    }))
}

#[tauri::command]
async fn pick_folder(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let folder = app
        .dialog()
        .file()
        .set_title("Choose a folder")
        .blocking_pick_folder();
    Ok(folder
        .and_then(|f| f.into_path().ok())
        .map(|p| p.display().to_string()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SaveRequest {
    accounts: Vec<Account>,
    removed_ids: Vec<String>,
    logo_sources: Vec<(String, String)>,
}

#[derive(Serialize)]
struct SaveReport {
    notes: Vec<String>,
}

#[tauri::command]
async fn save(
    app: tauri::AppHandle,
    ctx: State<'_, Ctx>,
    req: SaveRequest,
) -> Result<SaveReport, String> {
    let (desktop, auto_switch) = ctx.current();
    let exe = std::env::current_exe().map_err(err)?;
    let source_dir = exe
        .parent()
        .ok_or("couldn't find this program's folder")?
        .to_path_buf();
    let request = Request {
        accounts: req.accounts,
        logo_sources: req
            .logo_sources
            .into_iter()
            .map(|(id, p)| (id, PathBuf::from(p)))
            .collect(),
        removed_ids: req.removed_ids,
        desktop_shortcuts: desktop,
        auto_switch,
        allow_scripts: false,
        install_desktop_app: false,
        install_code: false,
        source_dir,
    };
    let host = ctx.host();
    let probe = SystemProbe::new(&ctx.paths);
    let report = install::install(&ctx.paths, host.as_ref(), &probe, request, &mut |s| {
        let _ = app.emit("step", s);
    })
    .map_err(err)?;
    Ok(SaveReport {
        notes: report.notes,
    })
}

#[tauri::command]
fn open_launcher(ctx: State<'_, Ctx>, kind: String, id: String) -> Result<Option<String>, String> {
    let cfg = Config::load(&ctx.paths).map_err(err)?;
    let a = cfg.get(&id).map_err(err)?;
    let what = if kind == "terminal" {
        "terminal"
    } else {
        "desktop app"
    };
    if ctx.sandbox.is_some() {
        return Ok(Some(format!(
            "Preview: would open the {what} for {}.",
            a.name
        )));
    }
    if kind == "terminal" {
        platform::open_terminal(a, &ctx.paths)
    } else {
        platform::start_desktop(a, &ctx.paths)
    }
    .map_err(err)?;
    Ok(None)
}

/// A throwaway folder with sample accounts, for looking at the window
fn preview_sandbox() -> anyhow::Result<PathBuf> {
    use severance_core::account::Places;
    let dir = std::env::temp_dir().join(format!("claude-severance-preview-{}", std::process::id()));
    let paths = Sandbox::new(&dir).paths();
    let mut accounts = vec![
        Account::new("Personal", "me@example.com", &[], true, &[], 0),
        Account::new(
            "Acme",
            "me@acme.example",
            &["D:\\work\\acme".into()],
            false,
            &["personal"],
            1,
        ),
        Account::new(
            "Globex",
            "me@globex.example",
            &[],
            false,
            &["personal", "acme"],
            2,
        ),
        Account::new(
            "Initech",
            "",
            &[],
            false,
            &["personal", "acme", "globex"],
            3,
        ),
    ];
    accounts[1].alias = "acme-cc".into();
    accounts[2].alias = "gx".into();
    accounts[1].launchers = Some(Launchers {
        app: Places::BOTH,
        terminal: Places::BOTH,
    });
    Config::new(accounts).save(&paths)?;
    for (id, email, org) in [
        ("acme", "me@acme.example", "Acme"),
        ("globex", "other@globex.example", "Globex"),
    ] {
        let d = paths.code_dir(id);
        std::fs::create_dir_all(&d)?;
        std::fs::write(
            d.join(".claude.json"),
            format!(
                r#"{{"oauthAccount":{{"emailAddress":"{email}","organizationName":"{org}"}}}}"#
            ),
        )?;
    }
    Ok(dir)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let sandbox = if args.iter().any(|a| a == "--preview") {
        Some(preview_sandbox().expect("a preview folder"))
    } else {
        args.iter()
            .position(|a| a == "--sandbox")
            .and_then(|i| args.get(i + 1))
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("SEVERANCE_SANDBOX").map(PathBuf::from))
    };
    let paths = match &sandbox {
        Some(d) => Sandbox::new(d).paths(),
        None => Paths::detect().expect("your home folder"),
    };

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(Ctx { paths, sandbox })
        .invoke_handler(tauri::generate_handler![
            state,
            check_alias,
            pick_logo,
            pick_folder,
            save,
            open_launcher
        ])
        .setup(|app| {
            let window =
                WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                    .title("Claude Severance")
                    .inner_size(560.0, 720.0)
                    .min_inner_size(480.0, 560.0)
                    .decorations(false)
                    .shadow(true)
                    .center()
                    .build()?;
            if let Some(icon) = app.default_window_icon().cloned() {
                let _ = window.set_icon(icon);
            }
            let _ = app.get_webview_window("main");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("the Claude Severance window");
}
