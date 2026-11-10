//! `severance`: list, add, rename and remove Claude accounts, open them, and install or uninstall Claude Severance.
//! Each account's own command (`claude-acme`, say) runs `severance run <id>`; Claude Code's status line runs
//! `severance statusline`.

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use severance_core::alias::{self, SystemProbe};
use severance_core::install::{self, Host, Request, Sandbox, System};
use severance_core::{Account, Config, Paths, account::PALETTE, claude, hooks, platform};
use std::io::{BufRead, IsTerminal, Write};
use std::path::PathBuf;
use std::process::ExitCode;

/// Colour only when writing to a terminal, and never with NO_COLOR set
fn colour(to_terminal: bool) -> bool {
    to_terminal && std::env::var_os("NO_COLOR").is_none_or(|v| v.is_empty())
}

/// Removes colour codes (`ESC [ ... m`)
fn plain(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' && chars.peek() == Some(&'[') {
            chars.next();
            for d in chars.by_ref() {
                if d.is_ascii_alphabetic() {
                    break;
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// `println!`, without colour codes when they wouldn't show
macro_rules! say {
    () => { println!() };
    ($($arg:tt)*) => {{
        let text = format!($($arg)*);
        if colour(std::io::stdout().is_terminal()) { println!("{text}") } else { println!("{}", plain(&text)) }
    }};
}

/// `eprintln!`, the same way
macro_rules! esay {
    ($($arg:tt)*) => {{
        let text = format!($($arg)*);
        if colour(std::io::stderr().is_terminal()) { eprintln!("{text}") } else { eprintln!("{}", plain(&text)) }
    }};
}

#[derive(Parser)]
#[command(
    name = "severance",
    version,
    about = "Run several Claude accounts side by side.",
    disable_help_subcommand = true
)]
struct Cli {
    /// Work inside this folder instead of on this computer (for trying things out; changes nothing else)
    #[arg(long, global = true, value_name = "DIR", env = "SEVERANCE_SANDBOX")]
    sandbox: Option<PathBuf>,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Show every account, its command, and who it is signed in as
    #[command(alias = "status")]
    List,
    /// Add an org account (its command defaults to claude-<name>)
    Add {
        /// The account's name, for example Acme
        #[arg(required = true, num_args = 1..)]
        name: Vec<String>,
        /// The email it should be signed in with
        #[arg(long)]
        email: Option<String>,
        /// Its terminal command
        #[arg(long)]
        alias: Option<String>,
        /// A folder whose Claude Code sessions use this account (repeat for more)
        #[arg(long = "folder", value_name = "PATH")]
        folders: Vec<String>,
        /// An image for its icon (PNG, JPG, BMP, GIF or ICO)
        #[arg(long, value_name = "FILE")]
        logo: Option<PathBuf>,
    },
    /// Remove an account; its memory and history are zipped first, without its login
    Remove {
        /// The account's id, name or command
        account: String,
        /// Don't ask first
        #[arg(long, short)]
        yes: bool,
    },
    /// Rename an account's terminal command
    Alias { account: String, command: String },
    /// Open a terminal running an account's Claude Code
    Terminal { account: String },
    /// Show or change where an account's launchers go: none, desktop, start-menu or both
    Launchers {
        /// The account's id, name or command
        account: String,
        /// The Claude Desktop launcher
        #[arg(long, value_name = "WHERE")]
        app: Option<String>,
        /// The terminal (Claude Code) launcher
        #[arg(long, value_name = "WHERE")]
        terminal: Option<String>,
    },
    /// Open Claude Desktop for an account
    Open { account: String },
    /// Install Claude Severance, or update it, with the current accounts
    Install {
        /// Don't put a shortcut per account on the desktop
        #[arg(long)]
        no_desktop_shortcuts: bool,
        /// Don't make plain `claude` pick the account for the current folder
        #[arg(long)]
        no_auto_switch: bool,
        /// Let PowerShell run your profile script (RemoteSigned, for you only), so auto-switch works
        #[arg(long)]
        allow_scripts: bool,
        /// Install Claude Desktop first, with winget
        #[arg(long)]
        install_desktop: bool,
        /// Install Claude Code first, with Anthropic's installer
        #[arg(long)]
        install_code: bool,
    },
    /// Set everything up again with the current accounts and choices
    Repair,
    /// Add, rename or remove accounts (the setup window arrives in a later 2.0 preview)
    Setup,
    /// Go back to a single Claude
    Uninstall {
        /// Don't ask first
        #[arg(long, short)]
        yes: bool,
        /// Also remove the extra accounts' data (zipped first, without logins)
        #[arg(long)]
        remove_data: bool,
    },
    /// Print the version
    Version,
}

fn main() -> ExitCode {
    platform::enable_ansi();
    let args: Vec<String> = std::env::args().collect();
    // `run` and `statusline` pass everything through untouched, so they skip the argument parser
    let result = match args.get(1).map(String::as_str) {
        Some("run") => run(&args[2..]),
        Some("statusline") => status_line(),
        _ => match Cli::try_parse() {
            Ok(cli) => dispatch(cli).map(|()| 0),
            Err(e) => {
                let _ = e.print();
                return ExitCode::from(if e.use_stderr() { 2 } else { 0 });
            }
        },
    };
    match result {
        Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
        Err(e) => {
            esay!("\x1b[31m{e:#}\x1b[0m");
            ExitCode::FAILURE
        }
    }
}

/// The real computer, or a sandbox folder
struct Ctx {
    paths: Paths,
    host: Box<dyn Host>,
    sandbox: bool,
}

impl Ctx {
    fn new(sandbox: Option<PathBuf>) -> Result<Self> {
        Ok(match sandbox {
            Some(dir) => {
                let sb = Sandbox::new(dir);
                Self {
                    paths: sb.paths(),
                    host: Box::new(sb),
                    sandbox: true,
                }
            }
            None => Self {
                paths: Paths::detect()?,
                host: Box::new(System),
                sandbox: false,
            },
        })
    }
}

fn dispatch(cli: Cli) -> Result<()> {
    let ctx = Ctx::new(cli.sandbox)?;
    if ctx.sandbox {
        say!(
            "\x1b[2mSandbox: {}\x1b[0m",
            ctx.paths.root.parent().unwrap_or(&ctx.paths.root).display()
        );
    }
    match cli.command.unwrap_or(Command::List) {
        Command::List => list(&ctx),
        Command::Add {
            name,
            email,
            alias,
            folders,
            logo,
        } => add(&ctx, &name.join(" "), email, alias, folders, logo),
        Command::Remove { account, yes } => remove(&ctx, &account, yes),
        Command::Alias { account, command } => rename_alias(&ctx, &account, &command),
        Command::Open { account } => open(&ctx, &account),
        Command::Terminal { account } => terminal(&ctx, &account),
        Command::Launchers {
            account,
            app,
            terminal,
        } => launchers(&ctx, &account, app, terminal),
        Command::Install {
            no_desktop_shortcuts,
            no_auto_switch,
            allow_scripts,
            install_desktop,
            install_code,
        } => {
            let accounts = install::current_or_first_accounts(&ctx.paths)?;
            let fresh = Config::load_if_present(&ctx.paths)?.is_none();
            save(
                &ctx,
                accounts,
                Vec::new(),
                Vec::new(),
                Choices {
                    desktop_shortcuts: !no_desktop_shortcuts,
                    auto_switch: !no_auto_switch,
                    allow_scripts,
                    install_desktop,
                    install_code,
                },
            )?;
            if fresh {
                say!("Next: add your org accounts with 'severance add <name>'.");
            }
            Ok(())
        }
        Command::Repair => {
            let cfg = Config::load(&ctx.paths)?;
            save(
                &ctx,
                cfg.accounts,
                Vec::new(),
                Vec::new(),
                Choices::current(&ctx),
            )?;
            say!("\x1b[32mRepaired.\x1b[0m");
            Ok(())
        }
        Command::Setup => {
            let manager = ctx.paths.bin().join(platform::exe_name(install::MANAGER));
            if !ctx.sandbox && manager.is_file() {
                std::process::Command::new(&manager)
                    .spawn()
                    .context("couldn't open the manager window")?;
                return Ok(());
            }
            say!("Manage accounts from here:");
            say!(
                "  severance add <name> [--email <address>] [--alias <command>] [--folder <path>] [--logo <image>]"
            );
            say!("  severance alias <account> <command>");
            say!("  severance launchers <account> [--app <where>] [--terminal <where>]");
            say!("  severance remove <account>");
            say!("  severance repair");
            Ok(())
        }
        Command::Uninstall { yes, remove_data } => uninstall(&ctx, yes, remove_data),
        Command::Version => {
            say!("Claude Severance {}", severance_core::VERSION);
            Ok(())
        }
    }
}

fn list(ctx: &Ctx) -> Result<()> {
    let cfg = Config::load(&ctx.paths)?;
    let rows = claude::status(&cfg, &ctx.paths);
    let headers = ["Account", "Type", "Command", "Signed in", "Org", "Check"];
    let cells: Vec<[String; 6]> = rows
        .iter()
        .map(|r| {
            [
                r.name.clone(),
                r.kind.into(),
                r.command.clone(),
                r.signed_in.clone(),
                r.org.clone(),
                r.check.into(),
            ]
        })
        .collect();
    let mut widths = headers.map(str::len);
    for row in &cells {
        for (w, c) in widths.iter_mut().zip(row) {
            *w = (*w).max(c.chars().count());
        }
    }
    let line = |cols: [&str; 6]| -> String {
        cols.iter()
            .zip(widths)
            .map(|(c, w)| format!("{c:<w$}"))
            .collect::<Vec<_>>()
            .join("  ")
            .trim_end()
            .to_string()
    };
    // the badge is three characters wide, plus two spaces
    say!("     {}", line(headers));
    say!(
        "     {}",
        line(widths.map(|w| "-".repeat(w)).each_ref().map(String::as_str))
    );
    for (row, account) in cells.iter().zip(&cfg.accounts) {
        let text = line(row.each_ref().map(String::as_str));
        let badge = severance_core::color::badge(
            &account.color,
            &account.label().chars().take(1).collect::<String>(),
        );
        let warn = if row[5] == "WRONG ACCOUNT" {
            "\x1b[31m"
        } else {
            ""
        };
        say!("{badge}  {warn}{text}\x1b[0m");
    }
    say!(
        "\x1b[2mseverance add <name> | remove <account> | alias <account> <command> | open <account> | repair | uninstall\x1b[0m"
    );
    Ok(())
}

fn add(
    ctx: &Ctx,
    name: &str,
    email: Option<String>,
    alias: Option<String>,
    folders: Vec<String>,
    logo: Option<PathBuf>,
) -> Result<()> {
    let cfg = Config::load(&ctx.paths)?;
    let name = name.trim();
    if cfg
        .accounts
        .iter()
        .any(|a| a.name.eq_ignore_ascii_case(name))
    {
        bail!("There is already an account called {name}.");
    }
    let ids: Vec<&str> = cfg.accounts.iter().map(|a| a.id.as_str()).collect();
    let mut new = Account::new(
        name,
        email.as_deref().unwrap_or_default(),
        &folders,
        false,
        &ids,
        cfg.accounts.len(),
    );
    if let Some(free) = PALETTE
        .iter()
        .find(|c| !cfg.accounts.iter().any(|a| a.color.eq_ignore_ascii_case(c)))
    {
        new.color = (*free).into();
    }
    new.alias = alias
        .map(|a| a.trim().to_lowercase())
        .unwrap_or_else(|| new.alias());
    if let Some(why) = alias::check(
        &new.alias,
        &new.id,
        &cfg.accounts,
        &SystemProbe::new(&ctx.paths),
    ) {
        bail!(why);
    }
    say!(
        "\x1b[36mAdding {name}, with the command {}\x1b[0m",
        new.alias
    );
    let logos = logo.map(|l| vec![(new.id.clone(), l)]).unwrap_or_default();
    let alias = new.alias.clone();
    let mut accounts = cfg.accounts;
    accounts.push(new);
    save(ctx, accounts, logos, Vec::new(), Choices::current(ctx))?;
    say!(
        "\x1b[36mNext: open 'Claude - {name}' from the {} and sign in, and run {alias} then /login.\x1b[0m",
        platform::MENU_NAME
    );
    Ok(())
}

fn remove(ctx: &Ctx, key: &str, yes: bool) -> Result<()> {
    let cfg = Config::load(&ctx.paths)?;
    let a = cfg.find(key)?.clone();
    if a.main {
        bail!(
            "{} is your main account and stays. To go back to one Claude, run 'severance uninstall'.",
            a.name
        );
    }
    if !yes
        && !confirm(&format!(
            "Remove {}? Its memory and history are zipped to '{}' first, without its login.",
            a.name,
            ctx.paths.backups().display()
        ))?
    {
        say!("Kept.");
        return Ok(());
    }
    let keep = cfg.accounts.into_iter().filter(|x| x.id != a.id).collect();
    save(ctx, keep, Vec::new(), vec![a.id], Choices::current(ctx))
}

fn rename_alias(ctx: &Ctx, key: &str, command: &str) -> Result<()> {
    let mut cfg = Config::load(&ctx.paths)?;
    let id = cfg.find(key)?.id.clone();
    let want = command.trim().to_lowercase();
    let account = cfg.get(&id)?;
    let old = account.alias();
    if old == want {
        say!("{} already uses {want}.", account.name);
        return Ok(());
    }
    if let Some(why) = alias::check(&want, &id, &cfg.accounts, &SystemProbe::new(&ctx.paths)) {
        bail!(why);
    }
    let account = cfg
        .accounts
        .iter_mut()
        .find(|a| a.id == id)
        .expect("found above");
    account.alias = want.clone();
    say!("\x1b[36m{}: {old} is now {want}\x1b[0m", account.name);
    save(
        ctx,
        cfg.accounts,
        Vec::new(),
        Vec::new(),
        Choices::current(ctx),
    )
}

fn terminal(ctx: &Ctx, key: &str) -> Result<()> {
    let cfg = Config::load(&ctx.paths)?;
    let a = cfg.find(key)?;
    if ctx.sandbox {
        say!(
            "Would open a terminal for {} in {}",
            a.name,
            a.start_dir(&ctx.paths).display()
        );
        return Ok(());
    }
    platform::open_terminal(a, &ctx.paths)
}

fn launchers(ctx: &Ctx, key: &str, app: Option<String>, terminal: Option<String>) -> Result<()> {
    use severance_core::account::Places;
    let mut cfg = Config::load(&ctx.paths)?;
    let id = cfg.find(key)?.id.clone();
    let current = Choices::current(ctx);
    let account = cfg
        .accounts
        .iter_mut()
        .find(|a| a.id == id)
        .expect("found above");
    let mut l = account.launchers_or_default(current.desktop_shortcuts);
    let parse = |w: &str| {
        Places::parse(w)
            .with_context(|| format!("{w} isn't a place: use none, desktop, start-menu or both."))
    };
    if app.is_none() && terminal.is_none() {
        say!("{}:", account.name);
        say!("  app       {}", l.app.describe());
        say!("  terminal  {}", l.terminal.describe());
        say!(
            "\x1b[2mChange with: severance launchers {id} --app <where> --terminal <where>  (none, desktop, start-menu, both)\x1b[0m"
        );
        return Ok(());
    }
    if let Some(w) = app {
        l.app = parse(&w)?;
    }
    if let Some(w) = terminal {
        l.terminal = parse(&w)?;
    }
    account.launchers = Some(l);
    say!(
        "\x1b[36m{}: app in {}, terminal in {}\x1b[0m",
        account.name,
        l.app.describe(),
        l.terminal.describe()
    );
    save(ctx, cfg.accounts, Vec::new(), Vec::new(), current)
}

fn open(ctx: &Ctx, key: &str) -> Result<()> {
    let cfg = Config::load(&ctx.paths)?;
    let a = cfg.find(key)?;
    if ctx.sandbox {
        say!(
            "Would open Claude Desktop for {} ({})",
            a.name,
            a.desktop_dir(&ctx.paths)
                .map(|d| d.display().to_string())
                .unwrap_or_else(|| "its normal data".into())
        );
        return Ok(());
    }
    platform::start_desktop(a, &ctx.paths)
}

/// The install choices
struct Choices {
    desktop_shortcuts: bool,
    auto_switch: bool,
    allow_scripts: bool,
    install_desktop: bool,
    install_code: bool,
}

impl Choices {
    /// What's in place now, so a change to the accounts keeps the rest as it is
    fn current(ctx: &Ctx) -> Self {
        let desktop_shortcuts = ctx
            .host
            .desktop_dir()
            .is_some_and(|d| !ctx.host.shortcuts_with(&d, install::MARKER).is_empty());
        let auto_switch = hooks::present_in(&ctx.host.profile_files());
        Self {
            desktop_shortcuts,
            auto_switch,
            allow_scripts: false,
            install_desktop: false,
            install_code: false,
        }
    }
}

/// Saves the accounts the way setup does, printing each finished step
fn save(
    ctx: &Ctx,
    accounts: Vec<Account>,
    logo_sources: Vec<(String, PathBuf)>,
    removed_ids: Vec<String>,
    c: Choices,
) -> Result<()> {
    let exe = std::env::current_exe().context("couldn't find this program")?;
    let source_dir = exe
        .parent()
        .context("couldn't find this program's folder")?
        .to_path_buf();
    let req = Request {
        accounts,
        logo_sources,
        removed_ids,
        desktop_shortcuts: c.desktop_shortcuts,
        auto_switch: c.auto_switch,
        allow_scripts: c.allow_scripts,
        install_desktop_app: c.install_desktop,
        install_code: c.install_code,
        source_dir,
    };
    let probe = SystemProbe::new(&ctx.paths);
    let report = install::install(&ctx.paths, ctx.host.as_ref(), &probe, req, &mut |s| {
        say!("  \x1b[32mdone\x1b[0m  {s}")
    })?;
    for n in &report.notes {
        say!("  \x1b[33m{n}\x1b[0m");
    }
    say!("\x1b[2mOpen a new terminal to use changed commands.\x1b[0m");
    Ok(())
}

fn uninstall(ctx: &Ctx, yes: bool, remove_data: bool) -> Result<()> {
    let what = if remove_data {
        "Remove Claude Severance and the extra accounts (zipped first, without their logins)?"
    } else {
        "Remove Claude Severance? The extra accounts' data stays, so installing again brings them back signed in."
    };
    if !yes && !confirm(what)? {
        say!("Kept.");
        return Ok(());
    }
    let r = install::uninstall(&ctx.paths, ctx.host.as_ref(), remove_data, &mut |s| {
        say!("  \x1b[32mdone\x1b[0m  {s}")
    })?;
    if let Some(z) = &r.backup {
        say!("  Backup: {}", z.display());
    }
    if let Some(l) = &r.left {
        say!(
            "  \x1b[33mSome files were in use and go at your next Windows sign-in: {}\x1b[0m",
            l.display()
        );
    }
    if r.kept_data {
        say!(
            "  Kept the data of {}, in {}.",
            r.extras.join(", "),
            ctx.paths.root.display()
        );
    }
    say!("{} stays your normal Claude, untouched.", r.main_name);
    Ok(())
}

fn confirm(question: &str) -> Result<bool> {
    if !std::io::stdin().is_terminal() {
        bail!("{question} Run it again with --yes to go ahead without asking.");
    }
    print!("{question} [y/N] ");
    std::io::stdout().flush()?;
    let mut answer = String::new();
    std::io::stdin().lock().read_line(&mut answer)?;
    Ok(answer.trim().to_lowercase().starts_with('y'))
}

/// `severance run <id|auto> [claude args...]`: what each account's command runs
fn run(args: &[String]) -> Result<i32> {
    let (sandbox, args) = match args {
        [flag, dir, rest @ ..] if flag == "--sandbox" => (Some(PathBuf::from(dir)), rest),
        _ => (
            std::env::var_os("SEVERANCE_SANDBOX").map(PathBuf::from),
            args,
        ),
    };
    let ctx = Ctx::new(sandbox)?;
    let cfg = Config::load(&ctx.paths)?;
    let Some((key, rest)) = args.split_first() else {
        say!("Usage: <account command> [claude args...]");
        return list(&ctx).map(|()| 1);
    };
    let account = if key == "auto" {
        let here = std::env::current_dir()?;
        match cfg.account_for_dir(&here) {
            Some(a) => a.clone(),
            None => pick_account(&cfg)?,
        }
    } else {
        cfg.get(key)?.clone()
    };
    say!("{}", claude::banner(&account, &ctx.paths));
    if std::io::stdout().is_terminal() {
        print!("\x1b]0;Claude [{}] {}\x07", account.label(), account.name);
        let _ = std::io::stdout().flush();
    }
    if ctx.sandbox {
        say!(
            "Would run Claude Code with {:?}, CLAUDE_CONFIG_DIR={}",
            rest,
            account
                .code_env(&ctx.paths)
                .map(|d| d.display().to_string())
                .unwrap_or_default()
        );
        return Ok(0);
    }
    claude::run(&account, &ctx.paths, rest)
}

/// An unmapped folder: ask instead of guessing, so org work never lands on the wrong account
fn pick_account(cfg: &Config) -> Result<Account> {
    if !std::io::stdin().is_terminal() {
        bail!(
            "This folder isn't mapped to an account. Use the account's own command, or add the folder to it with 'severance setup'."
        );
    }
    say!("This folder isn't mapped to an account. Which account?");
    for (i, a) in cfg.accounts.iter().enumerate() {
        say!("  {}) {}", i + 1, a.name);
    }
    print!("Number: ");
    std::io::stdout().flush()?;
    let mut answer = String::new();
    std::io::stdin().lock().read_line(&mut answer)?;
    let n: usize = answer.trim().parse().unwrap_or(0);
    let Some(a) = n.checked_sub(1).and_then(|i| cfg.accounts.get(i)) else {
        bail!("Cancelled.")
    };
    say!(
        "\x1b[2mTip: add this folder to {} with 'severance add' or the setup window to skip this question.\x1b[0m",
        a.name
    );
    Ok(a.clone())
}

/// What Claude Code's status line runs: session JSON on stdin, one line out. Never fails loudly.
fn status_line() -> Result<i32> {
    let mut raw = String::new();
    let _ = std::io::Read::read_to_string(&mut std::io::stdin(), &mut raw);
    let session: Option<serde_json::Value> = serde_json::from_str(&raw).ok();
    let paths = match std::env::var_os("SEVERANCE_SANDBOX") {
        Some(d) => Sandbox::new(d).paths(),
        None => Paths::detect()?,
    };
    let cfg = Config::load(&paths).ok();
    let dir = std::env::var("CLAUDE_CONFIG_DIR").ok();
    print!(
        "{}",
        claude::status_line(cfg.as_ref(), &paths, dir.as_deref(), session.as_ref())
    );
    Ok(0)
}
