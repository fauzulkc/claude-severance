//! Auto-switch by folder: a small block in the PowerShell profiles that makes `claude` pick the account for the
//! current folder. Marked with start and end lines so it can be replaced or taken out cleanly.

use anyhow::Result;
use std::path::{Path, PathBuf};

pub const START: &str = "# >>> claude-severance >>>";
pub const END: &str = "# <<< claude-severance <<<";

/// Windows PowerShell's and PowerShell 7's profile for the current user
pub fn powershell_profiles() -> Vec<PathBuf> {
    let Some(docs) = crate::platform::documents_dir() else {
        return Vec::new();
    };
    vec![
        docs.join("WindowsPowerShell")
            .join("Microsoft.PowerShell_profile.ps1"),
        docs.join("PowerShell")
            .join("Microsoft.PowerShell_profile.ps1"),
    ]
}

/// The block for a profile: `claude` runs `severance run auto` when Claude Severance is installed
pub fn powershell_block(exe: &Path) -> String {
    let p = exe.display().to_string().replace('\'', "''");
    format!(
        "{START}\r\nif (Test-Path '{p}') {{ function claude {{ & '{p}' run auto @args }} }}\r\n{END}"
    )
}

/// `text` without the block between `start` and `end` (and the line break before it)
pub fn strip(text: &str, start: &str, end: &str) -> String {
    let mut out = text.to_string();
    while let Some(s) = out.find(start) {
        let Some(e_rel) = out[s..].find(end) else {
            break;
        };
        let mut a = s;
        let mut b = s + e_rel + end.len();
        if out[..a].ends_with("\r\n") {
            a -= 2;
        } else if out[..a].ends_with('\n') {
            a -= 1;
        }
        if out[b..].starts_with("\r\n") {
            b += 2;
        } else if out[b..].starts_with('\n') {
            b += 1;
        }
        let joiner = if a > 0 && b < out.len() { "\r\n" } else { "" };
        out.replace_range(a..b, joiner);
    }
    out
}

fn read_profile(file: &Path) -> Option<(String, bool)> {
    let bytes = std::fs::read(file).ok()?;
    let bom = bytes.starts_with(&[0xEF, 0xBB, 0xBF]);
    let text = String::from_utf8_lossy(if bom { &bytes[3..] } else { &bytes }).into_owned();
    Some((text, bom))
}

/// Profiles are written as UTF-8 with a BOM, which Windows PowerShell 5.1 needs to read anything beyond ASCII
fn write_profile(file: &Path, text: &str) -> Result<()> {
    if let Some(d) = file.parent() {
        std::fs::create_dir_all(d)?;
    }
    let mut bytes = vec![0xEF, 0xBB, 0xBF];
    bytes.extend_from_slice(text.as_bytes());
    std::fs::write(file, bytes)?;
    Ok(())
}

pub fn remove_from(files: &[PathBuf], start: &str, end: &str) -> Result<()> {
    for f in files {
        let Some((text, _)) = read_profile(f) else {
            continue;
        };
        let new = strip(&text, start, end);
        if new != text {
            write_profile(f, new.trim_end())?;
        }
    }
    Ok(())
}

pub fn add_to(files: &[PathBuf], exe: &Path) -> Result<()> {
    remove_from(files, START, END)?;
    let block = powershell_block(exe);
    for f in files {
        let text = read_profile(f).map(|(t, _)| t).unwrap_or_default();
        let joined = if text.trim().is_empty() {
            block.clone()
        } else {
            format!("{}\r\n\r\n{block}", text.trim_end())
        };
        write_profile(f, &joined)?;
    }
    Ok(())
}

pub fn present_in(files: &[PathBuf]) -> bool {
    files
        .iter()
        .any(|f| read_profile(f).is_some_and(|(t, _)| t.contains(START)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds_replaces_and_removes_the_block_keeping_the_rest() {
        let t = tempfile::tempdir().unwrap();
        let f = t.path().join("WindowsPowerShell").join("profile.ps1");
        std::fs::create_dir_all(f.parent().unwrap()).unwrap();
        std::fs::write(&f, "Set-Alias g git\r\n# 1.x block\r\n# >>> claude-severance >>>\r\nold\r\n# <<< claude-severance <<<\r\nImport-Module posh").unwrap();
        let files = vec![f.clone(), t.path().join("PowerShell").join("profile.ps1")];
        let exe =
            Path::new("C:\\Users\\o'brien\\AppData\\Local\\ClaudeSeverance\\bin\\severance.exe");
        add_to(&files, exe).unwrap();
        let (text, bom) = read_profile(&f).unwrap();
        assert!(bom);
        assert_eq!(text.matches(START).count(), 1);
        assert!(!text.contains("\r\nold\r\n"));
        assert!(text.contains("Import-Module posh") && text.starts_with("Set-Alias g git"));
        assert!(
            text.contains("& 'C:\\Users\\o''brien\\AppData"),
            "quote doubled: {text}"
        );
        assert!(present_in(&files));
        assert!(files[1].exists(), "PowerShell 7 profile created");
        remove_from(&files, START, END).unwrap();
        let (text, _) = read_profile(&f).unwrap();
        assert!(!text.contains(START));
        assert_eq!(text, "Set-Alias g git\r\n# 1.x block\r\nImport-Module posh");
        assert!(!present_in(&files));
    }
}
