//! One account: its id, name, letter, colour, logo, command and folders.

use crate::Paths;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{Map, Value};
use std::path::PathBuf;

/// Account colours: muted mid-century tones (blue, mustard, green, rust, plum, rose, teal, orange)
pub const PALETTE: [&str; 8] = [
    "#3E6FA3", "#C08A2E", "#3E7A5A", "#B4442E", "#6C5B9E", "#B5577A", "#2F8A86", "#C46A2B",
];

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Account {
    pub id: String,
    #[serde(default, deserialize_with = "string_or_null")]
    pub name: String,
    #[serde(default, deserialize_with = "string_or_null")]
    pub label: String,
    #[serde(default, deserialize_with = "string_or_null")]
    pub color: String,
    /// A file name in the logos folder, or empty for the lettered shell
    #[serde(default, deserialize_with = "string_or_null")]
    pub logo: String,
    /// The terminal command; empty means the default, claude-<id>
    #[serde(default, deserialize_with = "string_or_null")]
    pub alias: String,
    /// The email this account should be signed in with (for the wrong-account warning)
    #[serde(default, deserialize_with = "string_or_null")]
    pub email: String,
    #[serde(default, deserialize_with = "bool_or_null")]
    pub main: bool,
    /// Folders whose Claude Code sessions belong to this account
    #[serde(default, deserialize_with = "strings_lenient")]
    pub paths: Vec<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl Account {
    /// A new account the way setup makes one: id from the name, first letter, a palette colour.
    pub fn new(
        name: &str,
        email: &str,
        paths: &[String],
        main: bool,
        existing_ids: &[&str],
        index: usize,
    ) -> Self {
        Self {
            id: new_id(name, existing_ids),
            name: name.trim().to_string(),
            label: new_label(name),
            color: PALETTE[index % PALETTE.len()].to_string(),
            email: email.trim().to_string(),
            main,
            paths: paths
                .iter()
                .filter(|p| !p.trim().is_empty())
                .cloned()
                .collect(),
            ..Self::default()
        }
    }

    /// The letter shown on the account's shell
    pub fn label(&self) -> String {
        if self.label.trim().is_empty() {
            self.id.to_uppercase()
        } else {
            self.label.clone()
        }
    }

    /// The account's terminal command, lowercased; claude-<id> unless renamed
    pub fn alias(&self) -> String {
        let a = self.alias.trim();
        if a.is_empty() {
            default_alias(&self.id)
        } else {
            a.to_lowercase()
        }
    }

    /// Name of its Start menu and desktop shortcut, without characters Windows refuses in file names
    pub fn shortcut_name(&self) -> String {
        let clean: String = self
            .name
            .chars()
            .filter(|c| !r#"\/:*?"<>|"#.contains(*c))
            .collect();
        format!("Claude - {clean}")
    }

    /// `CLAUDE_CONFIG_DIR` for this account, or `None` for the main account (variable unset, stock `~/.claude`)
    pub fn code_env(&self, paths: &Paths) -> Option<PathBuf> {
        (!self.main).then(|| paths.code_dir(&self.id))
    }

    /// The folder holding this account's Claude Code config
    pub fn code_dir(&self, paths: &Paths) -> PathBuf {
        self.code_env(paths)
            .unwrap_or_else(|| paths.main_code_dir())
    }

    /// Claude Code's state file (`.claude.json`) for this account, which holds who it is signed in as
    pub fn state_file(&self, paths: &Paths) -> PathBuf {
        match self.code_env(paths) {
            Some(d) => d.join(".claude.json"),
            None => paths.main_state_file(),
        }
    }

    /// Claude Desktop's data folder, or `None` for the main account (the app's normal data)
    pub fn desktop_dir(&self, paths: &Paths) -> Option<PathBuf> {
        (!self.main).then(|| paths.desktop_dir(&self.id))
    }

    /// The account's logo file, when it has one and it's still there
    pub fn logo_path(&self, paths: &Paths) -> Option<PathBuf> {
        let name = std::path::Path::new(self.logo.trim()).file_name()?;
        let p = paths.logos().join(name);
        p.is_file().then_some(p)
    }
}

pub fn default_alias(id: &str) -> String {
    format!("claude-{id}")
}

/// A lowercase slug of the name, numbered when it clashes; never empty and never "auto"
pub fn new_id(name: &str, existing: &[&str]) -> String {
    let lower = name.to_lowercase();
    let mut base = String::new();
    for c in lower.chars() {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            base.push(c);
        } else if !base.ends_with('-') {
            base.push('-');
        }
    }
    let mut base = base.trim_matches('-').to_string();
    if base.is_empty() || base == "auto" {
        base = "account".into();
    }
    let mut id = base.clone();
    let mut n = 2;
    while existing.contains(&id.as_str()) {
        id = format!("{base}{n}");
        n += 1;
    }
    id
}

/// The first letter or digit of the name, uppercased, or "?"
pub fn new_label(name: &str) -> String {
    name.chars()
        .find(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase().to_string())
        .unwrap_or_else(|| "?".into())
}

/// Windows PowerShell writes null for empty strings sometimes; read it as empty
pub(crate) fn string_or_null<'de, D: Deserializer<'de>>(d: D) -> Result<String, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::String(s) => s,
        Value::Null => String::new(),
        other => other.to_string(),
    })
}

fn bool_or_null<'de, D: Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::Bool(b) => b,
        Value::String(s) => s.eq_ignore_ascii_case("true"),
        Value::Number(n) => n.as_i64().unwrap_or(0) != 0,
        _ => false,
    })
}

/// A list of strings, a single string (PowerShell unwraps one-item arrays), or null
fn strings_lenient<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<String>, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::Array(items) => items
            .into_iter()
            .filter_map(|v| match v {
                Value::String(s) if !s.trim().is_empty() => Some(s),
                _ => None,
            })
            .collect(),
        Value::String(s) if !s.trim().is_empty() => vec![s],
        _ => Vec::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn label_is_the_first_letter_or_digit() {
        for (name, want) in [
            ("Acme", "A"),
            ("acme corp", "A"),
            ("  9lives", "9"),
            ("--x", "X"),
            ("---", "?"),
            ("", "?"),
        ] {
            assert_eq!(new_label(name), want, "{name:?}");
        }
    }

    #[test]
    fn id_is_a_lowercase_slug() {
        assert_eq!(new_id("Acme Corp!", &[]), "acme-corp");
    }

    #[test]
    fn id_numbers_a_clash() {
        assert_eq!(new_id("Acme", &["acme", "acme2"]), "acme3");
    }

    #[test]
    fn id_is_never_auto_or_empty() {
        assert_eq!(new_id("auto", &[]), "account");
        assert_eq!(new_id("!!!", &[]), "account");
    }

    #[test]
    fn alias_defaults_to_claude_id_and_is_lowercased() {
        let mut a = Account {
            id: "globex".into(),
            ..Account::default()
        };
        assert_eq!(a.alias(), "claude-globex");
        a.alias = "GX".into();
        assert_eq!(a.alias(), "gx");
    }

    #[test]
    fn shortcut_name_drops_characters_windows_refuses() {
        let a = Account {
            name: "Acme: R&D / Labs?".into(),
            ..Account::default()
        };
        assert_eq!(a.shortcut_name(), "Claude - Acme R&D  Labs");
    }

    #[test]
    fn new_account_uses_the_palette_in_turn() {
        let a = Account::new(
            " Globex ",
            " g@x.example ",
            &["".into(), "D:\\gx".into()],
            false,
            &["acme"],
            9,
        );
        assert_eq!(
            (a.id.as_str(), a.name.as_str(), a.label.as_str()),
            ("globex", "Globex", "G")
        );
        assert_eq!(a.color, PALETTE[1]);
        assert_eq!(a.email, "g@x.example");
        assert_eq!(a.paths, vec!["D:\\gx".to_string()]);
    }
}
