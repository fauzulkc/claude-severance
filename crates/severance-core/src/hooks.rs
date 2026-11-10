//! Auto-switch by folder: a small block in the shell profiles (PowerShell on Windows, bash and zsh elsewhere) that
//! makes `claude` pick the account for the current folder. Marked with start and end lines so it can be replaced or
//! taken out cleanly. The same kind of marked block carries the PATH entry on macOS and Linux.

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

/// bash and zsh start-up files that get the blocks: the platform's own shell's file always (zsh on macOS, bash on
/// Linux), the others when they are there
pub fn posix_profiles(home: &Path) -> Vec<PathBuf> {
    let (own, others): (&str, &[&str]) = if cfg!(target_os = "macos") {
        (".zshrc", &[".bashrc", ".bash_profile"])
    } else {
        (".bashrc", &[".zshrc"])
    };
    let mut files = vec![home.join(own)];
    files.extend(others.iter().map(|f| home.join(f)).filter(|f| f.is_file()));
    files
}

/// `'text'` for sh, with any `'` closed, escaped and reopened
pub fn sh_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

fn is_powershell(file: &Path) -> bool {
    file.extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("ps1"))
}

/// The auto-switch line for a profile: `claude` runs `severance run auto` while Claude Severance is installed
pub fn hook_line(file: &Path, exe: &Path) -> String {
    if is_powershell(file) {
        let p = exe.display().to_string().replace('\'', "''");
        format!("if (Test-Path '{p}') {{ function claude {{ & '{p}' run auto @args }} }}")
    } else {
        let p = sh_quote(&exe.display().to_string());
        format!(
            "claude() {{ if [ -x {p} ]; then {p} run auto \"$@\"; else command claude \"$@\"; fi; }}"
        )
    }
}

/// The line break a file already uses: CRLF for a new PowerShell profile, LF otherwise
fn newline_for(file: &Path, text: &str) -> &'static str {
    if text.contains("\r\n") || (text.trim().is_empty() && is_powershell(file)) {
        "\r\n"
    } else {
        "\n"
    }
}

/// `text` without the block between `start` and `end` (and the line break before it)
pub fn strip(text: &str, start: &str, end: &str) -> String {
    let nl = if text.contains("\r\n") { "\r\n" } else { "\n" };
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
        let joiner = if a > 0 && b < out.len() { nl } else { "" };
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

/// PowerShell profiles are written as UTF-8 with a BOM, which Windows PowerShell 5.1 needs to read anything beyond
/// ASCII. Shell files get no BOM, and end with a line break as shell files do.
fn write_profile(file: &Path, text: &str) -> Result<()> {
    if let Some(d) = file.parent() {
        std::fs::create_dir_all(d)?;
    }
    let ps = is_powershell(file);
    let mut bytes = if ps {
        vec![0xEF, 0xBB, 0xBF]
    } else {
        Vec::new()
    };
    bytes.extend_from_slice(text.as_bytes());
    if !ps && !text.is_empty() && !text.ends_with('\n') {
        bytes.push(b'\n');
    }
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

/// Puts `body` between `start` and `end` at the bottom of each file (replacing an earlier block), or only takes the
/// block out when `body` is `None`
pub fn put_block(
    files: &[PathBuf],
    start: &str,
    end: &str,
    body: Option<&dyn Fn(&Path) -> String>,
) -> Result<()> {
    remove_from(files, start, end)?;
    let Some(body) = body else {
        return Ok(());
    };
    for f in files {
        let text = read_profile(f).map(|(t, _)| t).unwrap_or_default();
        let nl = newline_for(f, &text);
        let block = format!("{start}{nl}{}{nl}{end}", body(f));
        let joined = if text.trim().is_empty() {
            block
        } else {
            format!("{}{nl}{nl}{block}", text.trim_end())
        };
        write_profile(f, &joined)?;
    }
    Ok(())
}

pub fn add_to(files: &[PathBuf], exe: &Path) -> Result<()> {
    let line = |f: &Path| hook_line(f, exe);
    put_block(files, START, END, Some(&line))
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
        let (fresh, _) = read_profile(&files[1]).unwrap();
        assert!(
            fresh.starts_with(START) && fresh.contains(">>>\r\nif (Test-Path"),
            "PowerShell 7 profile created with CRLF: {fresh:?}"
        );
        remove_from(&files, START, END).unwrap();
        let (text, _) = read_profile(&f).unwrap();
        assert!(!text.contains(START));
        assert_eq!(text, "Set-Alias g git\r\n# 1.x block\r\nImport-Module posh");
        assert!(!present_in(&files));
    }

    #[test]
    fn a_shell_profile_gets_a_function_with_lf_and_no_bom() {
        let t = tempfile::tempdir().unwrap();
        let f = t.path().join(".bashrc");
        std::fs::write(&f, "alias ll='ls -l'\n").unwrap();
        let exe = Path::new("/home/o'brien/.local/share/claude-severance/bin/severance");
        add_to(std::slice::from_ref(&f), exe).unwrap();
        let text = String::from_utf8(std::fs::read(&f).unwrap()).unwrap();
        assert!(
            text.starts_with("alias ll='ls -l'\n\n# >>> claude-severance >>>\nclaude() {"),
            "{text}"
        );
        assert!(!text.contains('\r'));
        assert!(
            text.contains(
                r#"'/home/o'\''brien/.local/share/claude-severance/bin/severance' run auto "$@""#
            ),
            "{text}"
        );
        assert!(text.ends_with("# <<< claude-severance <<<\n"));
        remove_from(std::slice::from_ref(&f), START, END).unwrap();
        assert_eq!(std::fs::read_to_string(&f).unwrap(), "alias ll='ls -l'\n");
    }

    #[test]
    fn picks_the_shell_files() {
        let t = tempfile::tempdir().unwrap();
        let own = if cfg!(target_os = "macos") {
            ".zshrc"
        } else {
            ".bashrc"
        };
        assert_eq!(posix_profiles(t.path()), vec![t.path().join(own)]);
        std::fs::write(t.path().join(".zshrc"), "").unwrap();
        std::fs::write(t.path().join(".bashrc"), "").unwrap();
        assert_eq!(posix_profiles(t.path()).len(), 2);
    }
}
