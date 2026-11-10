//! Reading and writing JSON files the way 1.x did: UTF-8 without a BOM, missing or blank files read as nothing.

use anyhow::{Context, Result};
use serde_json::Value;
use std::path::Path;

/// `Ok(None)` when the file is missing or blank. A leading BOM is ignored.
pub fn read(path: &Path) -> Result<Option<Value>> {
    let text = match std::fs::read_to_string(path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e).with_context(|| format!("couldn't read {}", path.display())),
    };
    let text = text.trim_start_matches('\u{feff}');
    if text.trim().is_empty() {
        return Ok(None);
    }
    let v = serde_json::from_str(text)
        .with_context(|| format!("{} isn't valid JSON", path.display()))?;
    Ok(Some(v))
}

/// Pretty-printed, creating the folder first. Written to a temporary file and renamed, so a crash never leaves half a file.
pub fn write(path: &Path, value: &impl serde::Serialize) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)
            .with_context(|| format!("couldn't create {}", dir.display()))?;
    }
    let mut text = serde_json::to_string_pretty(value)?;
    text.push('\n');
    let tmp = path.with_extension("json.tmp-severance");
    std::fs::write(&tmp, text).with_context(|| format!("couldn't write {}", tmp.display()))?;
    std::fs::rename(&tmp, path).with_context(|| format!("couldn't replace {}", path.display()))?;
    Ok(())
}
