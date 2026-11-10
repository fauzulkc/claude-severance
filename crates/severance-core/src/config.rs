//! accounts.json: schema version 1, the same file 1.x reads and writes.

use crate::{Account, Paths, jsonfile};
use anyhow::{Result, anyhow, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Config {
    #[serde(default = "one")]
    pub version: u32,
    /// The account for an unmapped folder: an account id, or "ask"
    #[serde(
        rename = "defaultCodeProfile",
        default = "ask",
        deserialize_with = "crate::account::string_or_null"
    )]
    pub default_code_profile: String,
    #[serde(default)]
    pub accounts: Vec<Account>,
    /// Anything a newer or older version wrote that this one doesn't know, kept as it is
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

fn one() -> u32 {
    1
}
fn ask() -> String {
    "ask".into()
}

impl Config {
    pub fn new(accounts: Vec<Account>) -> Self {
        Self {
            version: 1,
            default_code_profile: ask(),
            accounts,
            extra: Map::new(),
        }
    }

    /// The same checks, and the same sentences, as 1.x.
    pub fn validate(&self) -> Result<()> {
        if self.accounts.is_empty() {
            bail!("accounts.json has no accounts.");
        }
        let re = regex::Regex::new("^[a-z0-9][a-z0-9-]*$").expect("valid regex");
        for a in &self.accounts {
            if !re.is_match(&a.id) || a.id == "auto" {
                bail!(
                    "Account id '{}' is invalid: use lowercase letters, digits and dashes, and not 'auto'.",
                    a.id
                );
            }
        }
        let mut ids: Vec<&str> = self.accounts.iter().map(|a| a.id.as_str()).collect();
        ids.sort_unstable();
        ids.dedup();
        if ids.len() != self.accounts.len() {
            bail!("Account ids must be unique.");
        }
        if self.accounts.iter().filter(|a| a.main).count() != 1 {
            bail!("Exactly one account must be the main account.");
        }
        Ok(())
    }

    pub fn load(paths: &Paths) -> Result<Self> {
        let Some(v) = jsonfile::read(&paths.config())? else {
            bail!("Claude Severance isn't set up yet. Run 'severance install'.");
        };
        let cfg: Config =
            serde_json::from_value(v).map_err(|e| anyhow!("accounts.json can't be read: {e}"))?;
        cfg.validate()?;
        Ok(cfg)
    }

    /// `Ok(None)` when there's no accounts.json yet
    pub fn load_if_present(paths: &Paths) -> Result<Option<Self>> {
        if !paths.config().exists() {
            return Ok(None);
        }
        Self::load(paths).map(Some)
    }

    pub fn save(&self, paths: &Paths) -> Result<()> {
        self.validate()?;
        jsonfile::write(&paths.config(), self)
    }

    pub fn main(&self) -> &Account {
        self.accounts
            .iter()
            .find(|a| a.main)
            .expect("validated: exactly one main account")
    }

    pub fn get(&self, id: &str) -> Result<&Account> {
        self.accounts.iter().find(|a| a.id == id).ok_or_else(|| {
            let known: Vec<&str> = self.accounts.iter().map(|a| a.id.as_str()).collect();
            anyhow!("Unknown account '{id}'. Known: {}", known.join(", "))
        })
    }

    /// An account by its id, name or command, ignoring case; or by the start of one id or name when only one
    /// account matches it
    pub fn find(&self, key: &str) -> Result<&Account> {
        let k = key.trim().to_lowercase();
        if let Some(a) = self
            .accounts
            .iter()
            .find(|a| a.id == k || a.name.to_lowercase() == k || a.alias() == k)
        {
            return Ok(a);
        }
        let starts: Vec<&Account> = if k.is_empty() {
            Vec::new()
        } else {
            self.accounts
                .iter()
                .filter(|a| a.id.starts_with(&k) || a.name.to_lowercase().starts_with(&k))
                .collect()
        };
        match starts.as_slice() {
            [one] => Ok(one),
            [] => bail!("No account called {key}. Run 'severance list' to see them."),
            many => {
                let names: Vec<&str> = many.iter().map(|a| a.name.as_str()).collect();
                bail!("{key} could be {}. Say which.", names.join(" or "))
            }
        }
    }

    /// The account for a folder: the longest matching folder from any account's `paths`, then `defaultCodeProfile`.
    /// `None` means: ask.
    pub fn account_for_dir(&self, dir: &std::path::Path) -> Option<&Account> {
        let sep = if cfg!(windows) { '\\' } else { '/' };
        let want = format!("{}{sep}", crate::paths::comparable(dir));
        let mut best: Option<(&Account, usize)> = None;
        for a in &self.accounts {
            for raw in a.paths.iter().filter(|p| !p.trim().is_empty()) {
                let root = format!(
                    "{}{sep}",
                    crate::paths::comparable(std::path::Path::new(raw))
                );
                if want.starts_with(&root) && best.is_none_or(|(_, len)| root.len() > len) {
                    best = Some((a, root.len()));
                }
            }
        }
        if let Some((a, _)) = best {
            return Some(a);
        }
        match self.default_code_profile.as_str() {
            "" | "ask" => None,
            id => self.accounts.iter().find(|a| a.id == id),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn acct(id: &str, main: bool) -> Account {
        Account {
            id: id.into(),
            main,
            ..Account::default()
        }
    }

    #[test]
    fn needs_exactly_one_main_account() {
        let e = Config::new(vec![acct("a", false)]).validate().unwrap_err();
        assert!(e.to_string().contains("main"));
    }

    #[test]
    fn refuses_a_bad_id() {
        let e = Config::new(vec![acct("Bad Id", true)])
            .validate()
            .unwrap_err();
        assert!(e.to_string().contains("invalid"));
        let e = Config::new(vec![acct("auto", true)])
            .validate()
            .unwrap_err();
        assert!(e.to_string().contains("invalid"));
    }

    #[test]
    fn refuses_duplicate_ids() {
        let e = Config::new(vec![acct("a", true), acct("a", false)])
            .validate()
            .unwrap_err();
        assert!(e.to_string().contains("unique"));
    }

    #[test]
    fn reads_a_1x_file_and_keeps_unknown_fields() {
        // as Windows PowerShell 5.1's ConvertTo-Json writes it, with a field this version doesn't know
        let text = r##"{
            "version":  1,
            "defaultCodeProfile":  "ask",
            "accounts":  [
                { "id": "personal", "name": "Personal", "label": "P", "color": "#3E6FA3", "logo": "",
                  "alias": "claude-personal", "email": "me@example.com", "main": true, "paths": [] },
                { "id": "acme", "name": "Acme", "label": "A", "color": "#C08A2E", "logo": "acme.png",
                  "alias": "gx", "email": null, "main": false, "paths": "D:\\work\\acme" }
            ],
            "future": { "x": 1 }
        }"##;
        let cfg: Config = serde_json::from_str(text).unwrap();
        cfg.validate().unwrap();
        assert_eq!(cfg.main().id, "personal");
        let acme = cfg.get("acme").unwrap();
        assert_eq!(acme.paths, vec!["D:\\work\\acme".to_string()]);
        assert_eq!(acme.email, "");
        assert_eq!(acme.alias(), "gx");
        let back = serde_json::to_value(&cfg).unwrap();
        assert_eq!(back["future"]["x"], 1);
    }

    #[test]
    fn finds_by_id_name_or_command() {
        let mut a = acct("acme", false);
        a.name = "Acme Corp".into();
        a.alias = "AC-CC".into();
        let cfg = Config::new(vec![acct("personal", true), a]);
        assert_eq!(cfg.find("ACME").unwrap().id, "acme");
        assert_eq!(cfg.find("acme corp").unwrap().id, "acme");
        assert_eq!(cfg.find("ac-cc").unwrap().id, "acme");
        assert_eq!(cfg.find("acm").unwrap().id, "acme", "a unique start");
        assert!(cfg.find("globex").is_err());
        let both = Config::new(vec![acct("acme-us", true), acct("acme-eu", false)]);
        assert!(
            both.find("acme")
                .unwrap_err()
                .to_string()
                .contains("could be")
        );
    }

    #[test]
    fn picks_the_longest_matching_folder() {
        let base = if cfg!(windows) { "C:\\work" } else { "/work" };
        let sep = if cfg!(windows) { "\\" } else { "/" };
        let mut outer = acct("outer", true);
        outer.paths = vec![base.into()];
        let mut inner = acct("inner", false);
        inner.paths = vec![format!("{base}{sep}acme{sep}")];
        let cfg = Config::new(vec![outer, inner]);
        let dir = |s: &str| std::path::PathBuf::from(format!("{base}{s}").replace('/', sep));
        assert_eq!(cfg.account_for_dir(&dir("/acme/app")).unwrap().id, "inner");
        assert_eq!(cfg.account_for_dir(&dir("/acme")).unwrap().id, "inner");
        assert_eq!(cfg.account_for_dir(&dir("/acmeco")).unwrap().id, "outer");
        assert_eq!(cfg.account_for_dir(&dir("")).unwrap().id, "outer");
        let elsewhere = if cfg!(windows) { "D:\\other" } else { "/other" };
        assert!(
            cfg.account_for_dir(std::path::Path::new(elsewhere))
                .is_none()
        );
    }
}
