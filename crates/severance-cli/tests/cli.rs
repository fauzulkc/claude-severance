//! The `severance` program itself, in a sandbox folder: install, add, rename, run, the status line, remove, uninstall.

use std::path::Path;
use std::process::{Command, Output};

fn severance(sandbox: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_severance"))
        .args(args)
        .env("SEVERANCE_SANDBOX", sandbox)
        .env_remove("CLAUDE_CONFIG_DIR")
        .output()
        .expect("severance runs")
}

fn ok(sandbox: &Path, args: &[&str]) -> String {
    let out = severance(sandbox, args);
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.status.success(), "severance {args:?} failed:\n{text}");
    text
}

fn fails(sandbox: &Path, args: &[&str]) -> String {
    let out = severance(sandbox, args);
    assert!(!out.status.success(), "severance {args:?} should fail");
    String::from_utf8_lossy(&out.stderr).into_owned()
}

#[test]
fn the_whole_command_line_in_a_sandbox() {
    let t = tempfile::tempdir().unwrap();
    let sb = t.path();

    assert!(fails(sb, &["list"]).contains("isn't set up yet"));
    let out = ok(sb, &["install", "--no-desktop-shortcuts"]);
    assert!(out.contains("done  Set up Personal"), "{out}");
    let out = ok(
        sb,
        &[
            "add",
            "Acme",
            "Corp",
            "--email",
            "me@acme.example",
            "--alias",
            "zz9-acme",
        ],
    );
    assert!(
        out.contains("Adding Acme Corp, with the command zz9-acme"),
        "{out}"
    );
    assert!(fails(sb, &["add", "acme corp"]).contains("already an account called"));
    assert!(
        fails(sb, &["add", "Globex", "--alias", "zz9-acme"])
            .contains("already the command for Acme Corp")
    );
    assert!(fails(sb, &["add", "Globex", "--alias", "dir"]).contains("taken by Windows or Claude"));
    assert!(fails(sb, &["remove", "personal", "--yes"]).contains("main account and stays"));

    let list = ok(sb, &["list"]);
    assert!(
        list.contains("Acme Corp") && list.contains("zz9-acme"),
        "{list}"
    );

    ok(sb, &["alias", "acme", "zz9-ac"]);
    let shim = sb
        .join("ClaudeSeverance")
        .join("bin")
        .join(if cfg!(windows) {
            "zz9-ac.cmd"
        } else {
            "zz9-ac"
        });
    assert!(
        std::fs::read_to_string(&shim)
            .unwrap()
            .contains("run acme-corp")
    );

    // what an account's command runs (the sandbox prints instead of starting Claude Code)
    let run = ok(sb, &["run", "acme-corp", "--resume", "abc"]);
    assert!(
        run.contains("Acme Corp") && run.contains(r#"["--resume", "abc"]"#),
        "{run}"
    );
    assert!(fails(sb, &["run", "nobody"]).contains("Unknown account"));

    // the status line, as Claude Code calls it
    let mut child = Command::new(env!("CARGO_BIN_EXE_severance"))
        .arg("statusline")
        .env("SEVERANCE_SANDBOX", sb)
        .env(
            "CLAUDE_CONFIG_DIR",
            sb.join("ClaudeSeverance").join("code").join("acme-corp"),
        )
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    use std::io::Write;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(br#"{"model":{"display_name":"Opus"}}"#)
        .unwrap();
    let line = String::from_utf8(child.wait_with_output().unwrap().stdout).unwrap();
    assert!(line.contains(" A ") && line.contains("Opus"), "{line}");

    let out = ok(sb, &["remove", "acme", "--yes"]);
    assert!(
        out.contains("Backed up and removed Acme Corp") || out.contains("done"),
        "{out}"
    );
    assert!(!shim.exists());

    let out = ok(sb, &["uninstall", "--yes"]);
    assert!(out.contains("Personal stays your normal Claude"), "{out}");
    assert!(!sb.join("ClaudeSeverance").join("bin").exists());

    assert!(ok(sb, &["version"]).contains(env!("CARGO_PKG_VERSION")));
}
