# Releasing

## Versions and tags

- Semantic versioning. The single source of truth is `$script:Version` in `src/Severance.psm1` for 1.x, and `version` under `[workspace.package]` in the root `Cargo.toml` for 2.x (the Rust rewrite, see [docs/PLATFORMS-PLAN.md](docs/PLATFORMS-PLAN.md)). The release workflow refuses a tag that doesn't match it.
- `v1.*` tags build the PowerShell zip; `v2.*` and later build the Rust binaries for Windows (x64, Arm64), Linux (x86_64, aarch64) and macOS (universal).
- Stable releases are tagged `vX.Y.Z`; previews are `vX.Y.Z-preview.N`. Tags are annotated (`git tag -a`).
- `CHANGELOG.md` has a `## [Unreleased]` section. At release time it is renamed to `## [X.Y.Z] - YYYY-MM-DD`, and that section becomes the release notes.
- Previews are published as GitHub pre-releases, so `releases/latest` always points at a stable build.

## Cutting a release

1. Make sure `main` is green in CI.
2. Set the version (`src/Severance.psm1` for 1.x, the root `Cargo.toml` for 2.x, then `cargo update --workspace` so `Cargo.lock` agrees), and move `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] - <date>`, with a fresh empty `## [Unreleased]` above it. Update the compare links at the bottom.
3. Commit: `release: vX.Y.Z`.
4. Tag and push:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main vX.Y.Z
   ```

5. The **Release** workflow then:
   - checks the tag against the module version, and that the CHANGELOG has the section;
   - for 1.x: runs the Pester tests, renders every setup screen, and builds `ClaudeSeverance-X.Y.Z.zip` and its `.sha256`, plus a versionless `ClaudeSeverance.zip` so `releases/latest/download/ClaudeSeverance.zip` always gives the newest;
   - for 2.x: runs `cargo test` on each platform and builds `ClaudeSeverance-X.Y.Z-<platform>` archives (`.zip` on Windows, `.tar.gz` elsewhere), each with a `.sha256`. A preview's notes come from `## [X.Y.Z-preview.N]`, else `## [X.Y.Z]`, else `## [Unreleased]`;
   - attaches a build provenance attestation (`gh attestation verify <file> --repo fauzulkc/claude-severance`);
   - creates the GitHub release with the CHANGELOG section as notes, or adds the files to it if it already exists.
6. Check the release page: the assets, the notes, and that `latest` moved (stable only).
7. Run the update over a real install (`Install.cmd`, update screen) and check every account is still signed in.

A failed run can be re-run from the Actions tab; uploads replace what's already there.

## The first public release (v1.1.0)

### Decide first

- [x] **Name: kept as "Claude Severance"** (decided 2026-11-10), with the not-affiliated note in the README and LICENSE. Known risk: Anthropic's trademark guidelines say its marks may be used only as specifically permitted, and their only approved third-party pattern is "*YourName* Powered by Claude"; a tool called "Claude Remote" renamed in March 2026 after a trademark complaint. If Anthropic asks, rename promptly: the fallback is "Severance for Claude". The install folder and commands don't depend on the product name, so a rename doesn't break installs.
- [x] **Licence:** MIT, copyright Fauzul Kabir Chowdhury, as in `LICENSE`.
- [x] **Visibility:** public from the first push. Commits use the GitHub no-reply address.

### Repository settings (by hand, on GitHub)

- [ ] Description: "Run your personal and org Claude accounts side by side on Windows: separate Claude Desktop windows and Claude Code configs, each with its own login."
- [ ] Topics: `claude`, `claude-code`, `claude-desktop`, `windows`, `powershell`, `multi-account`, `developer-tools`.
- [ ] Social preview: upload `assets/social-preview.png` (Settings > General).
- [ ] Turn on Issues and Discussions (Q&A, Ideas); turn off Wiki and Projects.
- [ ] Private vulnerability reporting on (Settings > Security), as `SECURITY.md` promises.
- [ ] Branch protection on `main`: pull requests, the `CI` checks required, no force-push.
- [ ] Actions: "Read and write" workflow permissions are not needed; the release job asks for its own.

### Checks before tagging

- [ ] CI green on `windows-latest`.
- [ ] Every screenshot in `docs/screenshots` is current (`tools\capture-screens.ps1`).
- [ ] No personal data: `git grep -i` for your email, real account names and local paths returns nothing outside `LICENSE`.
- [ ] `README.md`, `docs/ARCHITECTURE.md` and `docs/DESIGN.md` describe the release as shipped.

### After it's out

- [ ] Pin the release in Discussions with what it does and the not-affiliated note.
- [ ] Later channels, each its own small job that skips when its secret is missing: winget (`wingetcreate`), Scoop bucket, Homebrew tap for the Unix ports.
- [ ] Optional: an hourly VirusTotal check of the release zip (unsigned PowerShell gets flagged sometimes), opening an issue when something trips.

## Channels and secrets

| Channel | When | Secret |
|---|---|---|
| GitHub Releases | every tag | none (the workflow's own token) |
| Build attestations | every tag | none (OIDC) |
| winget | stable tags, once listed | `WINGET_TOKEN` |
| Homebrew tap | once 2.x ships for macOS and Linux | `HOMEBREW_TAP_TOKEN` |
| macOS notarization | once there's an Apple Developer account | `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` |

A channel whose secret isn't set prints a notice and skips, so a release never fails because of a channel that isn't set up yet.
