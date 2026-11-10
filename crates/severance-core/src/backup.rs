//! Zips extra accounts' data before it is removed: their Claude Code folder (never the login, `.credentials.json`)
//! and their Claude Desktop MCP config.

use crate::Paths;
use anyhow::{Context, Result};
use std::io::Write;
use std::path::{Path, PathBuf};
use zip::write::SimpleFileOptions;

/// Files that are never copied anywhere
pub const NEVER: &[&str] = &[".credentials.json"];

/// Zips the accounts into `Claude Severance backups/backup <date>.zip`. `Ok(None)` when there was nothing to keep.
pub fn backup_accounts(paths: &Paths, ids: &[String]) -> Result<Option<PathBuf>> {
    let mut entries: Vec<(String, PathBuf)> = Vec::new();
    for id in ids {
        let code = paths.code_dir(id);
        if code.is_dir() {
            for e in walkdir::WalkDir::new(&code)
                .into_iter()
                .filter_map(Result::ok)
            {
                if !e.file_type().is_file()
                    || NEVER.contains(&e.file_name().to_string_lossy().as_ref())
                {
                    continue;
                }
                let rel = e.path().strip_prefix(&code).expect("walked inside code");
                entries.push((
                    format!("{id}/claude-code/{}", zip_name(rel)),
                    e.path().to_path_buf(),
                ));
            }
        }
        let mcp = paths.desktop_dir(id).join("claude_desktop_config.json");
        if mcp.is_file() {
            entries.push((
                format!("{id}/claude-desktop/claude_desktop_config.json"),
                mcp,
            ));
        }
    }
    if entries.is_empty() {
        return Ok(None);
    }
    let dir = paths.backups();
    std::fs::create_dir_all(&dir)?;
    let stamp = chrono::Local::now().format("%Y-%m-%d_%H%M%S");
    let zip_path = dir.join(format!("backup {stamp}.zip"));
    let file = std::fs::File::create(&zip_path)
        .with_context(|| format!("couldn't create {}", zip_path.display()))?;
    let mut zip = zip::ZipWriter::new(file);
    let opts = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    for (name, path) in entries {
        let data = std::fs::read(&path)
            .with_context(|| format!("Backup failed: couldn't read {}", path.display()))?;
        zip.start_file(name, opts)?;
        zip.write_all(&data)?;
    }
    zip.finish()?;
    Ok(Some(zip_path))
}

fn zip_name(rel: &Path) -> String {
    rel.components()
        .map(|c| c.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zips_data_without_the_login() {
        let t = tempfile::tempdir().unwrap();
        let paths = Paths::new(t.path().join("root"), t.path().join("home"));
        let code = paths.code_dir("acme");
        std::fs::create_dir_all(code.join("projects")).unwrap();
        std::fs::write(code.join("CLAUDE.md"), "memory").unwrap();
        std::fs::write(code.join("projects").join("a.jsonl"), "history").unwrap();
        std::fs::write(code.join(".credentials.json"), "secret").unwrap();
        std::fs::create_dir_all(paths.desktop_dir("acme")).unwrap();
        std::fs::write(
            paths.desktop_dir("acme").join("claude_desktop_config.json"),
            "{}",
        )
        .unwrap();
        std::fs::write(paths.desktop_dir("acme").join("Cookies"), "session").unwrap();

        let z = backup_accounts(&paths, &["acme".into(), "gone".into()])
            .unwrap()
            .unwrap();
        let mut archive = zip::ZipArchive::new(std::fs::File::open(z).unwrap()).unwrap();
        let mut names: Vec<String> = archive
            .file_names()
            .map(|n| n.unwrap().into_owned())
            .collect();
        names.sort();
        assert_eq!(
            names,
            [
                "acme/claude-code/CLAUDE.md",
                "acme/claude-code/projects/a.jsonl",
                "acme/claude-desktop/claude_desktop_config.json"
            ]
        );
        let _ = archive.by_name("acme/claude-code/CLAUDE.md").unwrap();
    }

    #[test]
    fn nothing_to_keep_means_no_zip() {
        let t = tempfile::tempdir().unwrap();
        let paths = Paths::new(t.path().join("root"), t.path().join("home"));
        assert_eq!(backup_accounts(&paths, &["acme".into()]).unwrap(), None);
        assert!(!paths.backups().exists());
    }
}
