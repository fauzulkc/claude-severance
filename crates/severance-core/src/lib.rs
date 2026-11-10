//! Claude Severance core: accounts, their commands, icons, Claude Code settings, and the install steps.
//!
//! Nothing here draws UI. The `severance` command and (later) the setup window both call into this crate.
//! Every function that touches the disk takes a [`Paths`], so tests can point it at a temporary folder.

pub mod account;
pub mod alias;
pub mod backup;
pub mod claude;
pub mod color;
pub mod config;
pub mod hooks;
pub mod icon;
pub mod install;
pub mod jsonfile;
pub mod paths;
pub mod platform;
pub mod settings;

pub use account::Account;
pub use config::Config;
pub use paths::Paths;

/// The version of this build, from the workspace `Cargo.toml`.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
