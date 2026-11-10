//! `severancew open <account>`: opens Claude Desktop for an account with no console window. The "Claude - <name>"
//! shortcuts run this. A problem is shown in a message box, since there's no terminal to print it in.
#![cfg_attr(windows, windows_subsystem = "windows")]

use severance_core::{Config, Paths, platform};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.as_slice() {
        [cmd, account] if cmd == "open" => open(account),
        _ => Err(anyhow::anyhow!("Usage: severancew open <account>")),
    };
    if let Err(e) = result {
        show_error(&format!("{e:#}"));
        std::process::exit(1);
    }
}

fn open(key: &str) -> anyhow::Result<()> {
    let paths = Paths::detect()?;
    let cfg = Config::load(&paths)?;
    platform::start_desktop(cfg.find(key)?, &paths)
}

#[cfg(windows)]
fn show_error(text: &str) {
    use windows::Win32::UI::WindowsAndMessaging::{MB_ICONWARNING, MB_OK, MessageBoxW};
    use windows::core::HSTRING;
    // SAFETY: a plain message box with no owner window
    unsafe {
        MessageBoxW(
            None,
            &HSTRING::from(text),
            &HSTRING::from("Claude Severance"),
            MB_OK | MB_ICONWARNING,
        );
    }
}

#[cfg(not(windows))]
fn show_error(text: &str) {
    eprintln!("{text}");
}
