//! Claude Code's settings.json: the account badge in the status line, and the update channel all accounts share.
//! Every other setting is kept as it is, in its order.

use crate::{Config, Paths, jsonfile};
use anyhow::{Result, bail};
use serde_json::{Map, Value, json};
use std::path::Path;

/// The command Claude Code runs for the status line
pub fn status_line_command(paths: &Paths) -> String {
    let exe = paths.bin().join(crate::platform::exe_name("severance"));
    format!(
        "\"{}\" statusline",
        exe.display().to_string().replace('\\', "/")
    )
}

/// A status line this tool (or 1.x, or the older ClaudeProfiles) put there
pub fn is_ours(status_line: &Value) -> bool {
    let c = status_line
        .get("command")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_lowercase();
    c.contains("statusline") && (c.contains("severance") || c.contains("claudeprofiles"))
}

fn read_object(path: &Path) -> Result<Map<String, Value>> {
    match jsonfile::read(path)? {
        None => Ok(Map::new()),
        Some(Value::Object(m)) => Ok(m),
        Some(_) => bail!("{} isn't a JSON object", path.display()),
    }
}

/// What `set_status_line` did
#[derive(Debug, PartialEq)]
pub enum Badge {
    Added,
    Unchanged,
    /// The user has a status line of their own, which is kept (no badge there)
    KeptTheirs,
}

/// Adds the account badge to a settings.json. Never replaces a status line of the user's own. The first time it
/// changes a file it keeps a copy next to it, `settings.json.bak-severance`.
pub fn set_status_line(settings: &Path, paths: &Paths) -> Result<Badge> {
    let mut obj = read_object(settings)?;
    if let Some(existing) = obj.get("statusLine")
        && !is_ours(existing)
    {
        return Ok(Badge::KeptTheirs);
    }
    let want = json!({ "type": "command", "command": status_line_command(paths), "padding": 0 });
    if obj.get("statusLine") == Some(&want) {
        return Ok(Badge::Unchanged);
    }
    let bak = settings.with_file_name("settings.json.bak-severance");
    if settings.exists() && !bak.exists() {
        std::fs::copy(settings, &bak)?;
    }
    obj.insert("statusLine".into(), want);
    jsonfile::write(settings, &obj)?;
    Ok(Badge::Added)
}

/// Takes the badge out again, if it is ours
pub fn remove_status_line(settings: &Path) -> Result<()> {
    let Ok(mut obj) = read_object(settings) else {
        return Ok(());
    };
    if obj.get("statusLine").is_some_and(is_ours) {
        obj.shift_remove("statusLine");
        jsonfile::write(settings, &obj)?;
    }
    Ok(())
}

/// All accounts share one Claude Code program, so they must agree on how it updates. Copies your normal Claude Code's
/// `autoUpdatesChannel` and `minimumVersion` to every extra account. Returns a note for each file it couldn't change.
pub fn sync_update_settings(cfg: &Config, paths: &Paths) -> Vec<String> {
    let Ok(main) = read_object(&paths.main_code_dir().join("settings.json")) else {
        return Vec::new();
    };
    let keys = ["autoUpdatesChannel", "minimumVersion"];
    let mut notes = Vec::new();
    for a in cfg.accounts.iter().filter(|a| !a.main) {
        let path = a.code_dir(paths).join("settings.json");
        let result = (|| -> Result<()> {
            let mut o = read_object(&path)?;
            let mut changed = false;
            for k in keys {
                match main.get(k) {
                    Some(v) if o.get(k) != Some(v) => {
                        o.insert(k.into(), v.clone());
                        changed = true;
                    }
                    None if o.contains_key(k) => {
                        o.shift_remove(k);
                        changed = true;
                    }
                    _ => {}
                }
            }
            if changed {
                jsonfile::write(&path, &o)?;
            }
            Ok(())
        })();
        if let Err(e) = result {
            notes.push(format!(
                "Couldn't match update settings in {}: {e}",
                path.display()
            ));
        }
    }
    notes
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Account;

    fn sandbox() -> (tempfile::TempDir, Paths) {
        let t = tempfile::tempdir().unwrap();
        let paths = Paths::new(t.path().join("ClaudeSeverance"), t.path().join("home"));
        (t, paths)
    }

    #[test]
    fn adds_the_badge_keeps_other_settings_and_backs_up_once() {
        let (t, paths) = sandbox();
        let f = t.path().join("settings.json");
        std::fs::write(&f, r#"{"model":"opus","permissions":{"allow":["Bash"]}}"#).unwrap();
        assert_eq!(set_status_line(&f, &paths).unwrap(), Badge::Added);
        assert_eq!(set_status_line(&f, &paths).unwrap(), Badge::Unchanged);
        let v: Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        assert_eq!(v["model"], "opus");
        assert!(is_ours(&v["statusLine"]));
        let keys: Vec<&String> = v.as_object().unwrap().keys().collect();
        assert_eq!(keys, ["model", "permissions", "statusLine"], "order kept");
        assert!(t.path().join("settings.json.bak-severance").exists());
        remove_status_line(&f).unwrap();
        let v: Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        assert!(v.get("statusLine").is_none());
    }

    #[test]
    fn keeps_a_status_line_of_your_own() {
        let (t, paths) = sandbox();
        let f = t.path().join("settings.json");
        std::fs::write(
            &f,
            r#"{"statusLine":{"type":"command","command":"my-line.sh"}}"#,
        )
        .unwrap();
        assert_eq!(set_status_line(&f, &paths).unwrap(), Badge::KeptTheirs);
        remove_status_line(&f).unwrap();
        assert!(std::fs::read_to_string(&f).unwrap().contains("my-line.sh"));
    }

    #[test]
    fn recognises_the_1x_badge() {
        let old = json!({"command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/x/AppData/Local/ClaudeSeverance/bin/statusline.ps1\""});
        assert!(is_ours(&old));
    }

    #[test]
    fn copies_the_update_channel_to_extra_accounts() {
        let (_t, paths) = sandbox();
        let main = Account {
            id: "me".into(),
            main: true,
            ..Account::default()
        };
        let acme = Account {
            id: "acme".into(),
            ..Account::default()
        };
        let cfg = Config::new(vec![main, acme]);
        jsonfile::write(
            &paths.main_code_dir().join("settings.json"),
            &json!({"autoUpdatesChannel": "stable"}),
        )
        .unwrap();
        jsonfile::write(
            &paths.code_dir("acme").join("settings.json"),
            &json!({"minimumVersion": "1.0", "x": 1}),
        )
        .unwrap();
        assert!(sync_update_settings(&cfg, &paths).is_empty());
        let v = jsonfile::read(&paths.code_dir("acme").join("settings.json"))
            .unwrap()
            .unwrap();
        assert_eq!(v, json!({"x": 1, "autoUpdatesChannel": "stable"}));
    }
}
