//! Claude itself: who each account is signed in as, finding Claude Code, and running it for an account.
//! Login tokens are never read: only the `oauthAccount` object (email and organisation) of `.claude.json`.

use crate::{Account, Config, Paths, alias::find_on_path};
use anyhow::{Result, bail};
use serde_json::Value;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SignIn {
    pub email: String,
    pub org: String,
}

/// Email and organisation from a Claude Code state file, or `None` when signed out or the file is missing.
/// A long-used `.claude.json` often has keys that differ only by case (project paths); that's fine here.
pub fn read_sign_in(file: &Path) -> Option<SignIn> {
    let v = crate::jsonfile::read(file).ok()??;
    let acct = v.get("oauthAccount")?;
    let s = |k: &str| {
        acct.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let info = SignIn {
        email: s("emailAddress"),
        org: s("organizationName"),
    };
    (!info.email.is_empty() || !info.org.is_empty()).then_some(info)
}

pub fn sign_in(account: &Account, paths: &Paths) -> SignIn {
    read_sign_in(&account.state_file(paths)).unwrap_or_default()
}

/// One row of `severance list`
#[derive(Clone, Debug)]
pub struct Status {
    pub name: String,
    pub kind: &'static str,
    pub command: String,
    pub signed_in: String,
    pub org: String,
    /// "ok", "WRONG ACCOUNT", or empty when there's nothing to compare
    pub check: &'static str,
}

pub fn status(cfg: &Config, paths: &Paths) -> Vec<Status> {
    cfg.accounts
        .iter()
        .map(|a| {
            let s = sign_in(a, paths);
            let check = match (a.email.is_empty(), s.email.is_empty()) {
                (false, false) if a.email.eq_ignore_ascii_case(&s.email) => "ok",
                (false, false) => "WRONG ACCOUNT",
                _ => "",
            };
            Status {
                name: a.name.clone(),
                kind: if a.main { "main" } else { "extra" },
                command: a.alias(),
                signed_in: s.email,
                org: s.org,
                check,
            }
        })
        .collect()
}

/// The account a `CLAUDE_CONFIG_DIR` value belongs to (unset or empty: the main account)
pub fn account_for_config_dir<'a>(
    cfg: &'a Config,
    paths: &Paths,
    config_dir: Option<&str>,
) -> Option<&'a Account> {
    let Some(dir) = config_dir.filter(|d| !d.trim().is_empty()) else {
        return Some(cfg.main());
    };
    let want = crate::paths::comparable(Path::new(dir));
    cfg.accounts
        .iter()
        .find(|a| crate::paths::comparable(&a.code_dir(paths)) == want)
}

/// The real Claude Code program, never one of our own commands. Prefers an .exe on Windows.
pub fn find_cli(paths: &Paths) -> Option<PathBuf> {
    let path_var = std::env::var_os("PATH");
    if cfg!(windows) {
        // claude.exe (native install) before claude.cmd (npm)
        let bin = paths.bin();
        let exe = std::env::split_paths(path_var.as_deref()?)
            .filter(|d| crate::paths::comparable(d) != crate::paths::comparable(&bin))
            .map(|d| d.join("claude.exe"))
            .find(|p| p.is_file());
        if exe.is_some() {
            return exe;
        }
    }
    if let Some(p) = find_on_path("claude", path_var.as_deref(), &paths.bin()) {
        return Some(p);
    }
    let native = paths
        .home
        .join(".local")
        .join("bin")
        .join(if cfg!(windows) {
            "claude.exe"
        } else {
            "claude"
        });
    native.is_file().then_some(native)
}

/// Runs Claude Code for an account in this terminal and returns its exit code.
/// The account's config folder is set (or, for the main account, unset), and `ANTHROPIC_API_KEY` is removed so the
/// session bills the account's subscription, not the API.
pub fn run(account: &Account, paths: &Paths, args: &[String]) -> Result<i32> {
    let Some(cli) = find_cli(paths) else {
        bail!("Claude Code is not installed. Get it from claude.ai/download, then try again.");
    };
    let mut cmd = std::process::Command::new(&cli);
    cmd.args(args).env_remove("ANTHROPIC_API_KEY");
    match account.code_env(paths) {
        Some(dir) => {
            std::fs::create_dir_all(&dir)?;
            cmd.env("CLAUDE_CONFIG_DIR", dir);
        }
        None => {
            cmd.env_remove("CLAUDE_CONFIG_DIR");
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        // replace this process, so signals and the terminal go straight to Claude Code
        let e = cmd.exec();
        bail!("couldn't start {}: {e}", cli.display());
    }
    #[cfg(not(unix))]
    {
        // Ctrl+C belongs to Claude Code; this process just waits for it
        crate::platform::ignore_ctrl_c();
        let status = cmd
            .status()
            .map_err(|e| anyhow::anyhow!("couldn't start {}: {e}", cli.display()))?;
        Ok(status.code().unwrap_or(1))
    }
}

/// The line printed before a session: the account's badge, name, and who it's signed in as
pub fn banner(account: &Account, paths: &Paths) -> String {
    let s = sign_in(account, paths);
    let mut who = if s.email.is_empty() {
        "not signed in yet - type /login".to_string()
    } else {
        s.email.clone()
    };
    if !s.org.is_empty() {
        who = format!("{who}  ({})", s.org);
    }
    let mut line = format!(
        "{}  {}  |  {who}",
        crate::color::badge(&account.color, &account.label()),
        account.name
    );
    if !account.email.is_empty()
        && !s.email.is_empty()
        && !account.email.eq_ignore_ascii_case(&s.email)
    {
        line.push_str(&format!(
            "\n\x1b[41;97;1m WRONG ACCOUNT: this is meant to be {}. Type /logout then /login. \x1b[0m",
            account.email
        ));
    }
    line
}

/// Claude Code's status line: the account badge and email, then model, folder and context use from the session JSON
/// Claude Code pipes in.
pub fn status_line(
    cfg: Option<&Config>,
    paths: &Paths,
    config_dir: Option<&str>,
    session: Option<&Value>,
) -> String {
    let sep = " \x1b[2m|\x1b[0m ";
    let mut line = match cfg.and_then(|c| account_for_config_dir(c, paths, config_dir)) {
        Some(a) => {
            let s = sign_in(a, paths);
            let mut who = if s.email.is_empty() {
                "not signed in".to_string()
            } else {
                s.email.clone()
            };
            if !s.org.is_empty() {
                who = format!("{who} ({})", s.org);
            }
            let mut l = format!("{} {who}", crate::color::badge(&a.color, &a.label()));
            if !a.email.is_empty() && !s.email.is_empty() && !a.email.eq_ignore_ascii_case(&s.email)
            {
                l.push_str(&format!(
                    " \x1b[41;97;1m WRONG ACCOUNT - expected {} \x1b[0m",
                    a.email
                ));
            }
            l
        }
        None => format!(
            "\x1b[41;97;1m UNMAPPED ACCOUNT \x1b[0m CLAUDE_CONFIG_DIR={}",
            config_dir.unwrap_or_default()
        ),
    };
    if let Some(d) = session {
        if let Some(m) = d.pointer("/model/display_name").and_then(Value::as_str) {
            line.push_str(&format!("{sep}{m}"));
        }
        let dir = d
            .pointer("/workspace/current_dir")
            .or_else(|| d.get("cwd"))
            .and_then(Value::as_str);
        if let Some(leaf) = dir.and_then(|p| Path::new(p).file_name()) {
            line.push_str(&format!("{sep}{}", leaf.to_string_lossy()));
        }
        if let Some(pct) = d
            .pointer("/context_window/used_percentage")
            .and_then(Value::as_f64)
        {
            line.push_str(&format!("{sep}ctx {}%", pct.round()));
        }
    }
    line
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_email_and_org_when_keys_differ_only_by_case() {
        let t = tempfile::tempdir().unwrap();
        let f = t.path().join("state.json");
        std::fs::write(
            &f,
            r#"{"projects":{"D:/Code":{},"d:/code":{}},"oauthAccount":{"emailAddress":"you@acme.example","organizationName":"Acme"}}"#,
        )
        .unwrap();
        assert_eq!(
            read_sign_in(&f),
            Some(SignIn {
                email: "you@acme.example".into(),
                org: "Acme".into()
            })
        );
    }

    #[test]
    fn nothing_when_signed_out_or_missing() {
        let t = tempfile::tempdir().unwrap();
        let f = t.path().join("empty.json");
        std::fs::write(&f, r#"{"projects":{}}"#).unwrap();
        assert_eq!(read_sign_in(&f), None);
        assert_eq!(read_sign_in(&t.path().join("nope.json")), None);
    }

    #[test]
    fn status_line_shows_badge_model_folder_and_context() {
        let t = tempfile::tempdir().unwrap();
        let paths = Paths::new(t.path().join("root"), t.path().join("home"));
        let acme = Account {
            id: "acme".into(),
            name: "Acme".into(),
            label: "A".into(),
            color: "#C08A2E".into(),
            ..Account::default()
        };
        let cfg = Config::new(vec![
            Account {
                id: "me".into(),
                main: true,
                ..Account::default()
            },
            acme,
        ]);
        let dir = paths.code_dir("acme");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join(".claude.json"),
            r#"{"oauthAccount":{"emailAddress":"a@acme.example"}}"#,
        )
        .unwrap();
        let session: Value = serde_json::from_str(
            r#"{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/src/app"},"context_window":{"used_percentage":41.6}}"#,
        )
        .unwrap();
        let line = status_line(Some(&cfg), &paths, dir.to_str(), Some(&session));
        for part in [" A ", "a@acme.example", "Opus", "app", "ctx 42%"] {
            assert!(line.contains(part), "{part:?} in {line:?}");
        }
        let unmapped = status_line(Some(&cfg), &paths, Some("/elsewhere"), None);
        assert!(unmapped.contains("UNMAPPED ACCOUNT"));
    }
}
