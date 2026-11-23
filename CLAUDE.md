# CLAUDE.md — Shattered Vales OS Home Edition

You are working on Shattered Vales OS **Home Edition**: a custom Fedora
Atomic (Silverblue) image for family computers, built with BlueBuild,
published to GHCR, and installed on home machines (mini-PCs, desktops,
laptops). It shares its branding and update tooling with the studio
edition (`Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS`) but
has none of its developer tooling. Read this whole file before making
changes.

## Who it is for

Non-technical people, often older parents whose adult children set the
computer up and look after it remotely. Every change should keep the
system feeling as simple as a phone:

- A flat app grid with **no app folders** and a short dock.
- Few apps out of the box; more are one click away in Software.
- Plain-language text in every window, notification and document.
- Streaming services appear only as browser bookmarks (the managed
  *Streaming* folder), never as app-grid icons.
- An everyday account for each person and a separate administrator
  account, made in Family Setup (`files/system/usr/libexec/shatteredvales/family-setup`).

## How the system works

- `recipes/recipe-base.yml` and `recipes/recipe-nvidia.yml` differ **only** in
  `name`, `description` and `base-image`. Every other change goes in
  `recipes/common/*.yml` so the two images can never drift.
- `files/system/` is copied to `/` in the image. `files/scripts/` holds
  build-time scripts run by `type: script` modules.
- `branding/` is the single source for colors, fonts and artwork. Gold,
  black and the fonts mirror tokens in the website's `assets/css/variables.css`;
  the edition blue and the administrator red are edition-specific and their
  contrast ratios are documented in `branding/brand.env`. Check contrast for
  any new color pairing before using it (AAA 7:1 for text). `just branding`
  renders PNGs into `files/system`. Never hand-edit those generated files;
  change `branding/` and re-render.
- Brand values reach the image through `/usr/share/shatteredvales/brand.env`
  (a copy made by the renderer). Templates use `@BRAND_*@` placeholders that
  build scripts substitute.
- Installer USB sticks are built by the separate `Shattered-Vales-Studio/OS-Installer`
  repository.

## Commands

| Command | Purpose |
|---|---|
| `just branding` | Render artwork from `branding/` |
| `just validate` | Schema-check recipes |
| `just build [base\|nvidia]` | Build an image locally (linux/amd64) |
| `just test [base\|nvidia]` | Smoke-test a local build |
| `just lint` | shellcheck every script, compile-check Family Setup |
| `just keys` | Create the cosign key pair (one time) |

## Testing limits

- The Mac can **build** and **inspect** images, not boot them. Real boot
  testing (Plymouth, GDM, lock screen, GNOME Initial Setup, Family Setup,
  NVIDIA) needs an x86_64 machine or a VM (GNOME Boxes or virt-manager on a
  Linux machine).
- When you change anything visual or anything in Family Setup, tell the
  user exactly what to check on real hardware, since you cannot see it.
- `family-setup --self-test` builds every page without changing anything;
  run it in a graphical session after editing the app.
- `bootc container lint` fails with "Function not implemented (os error 38)"
  under amd64 emulation on Apple Silicon, even on the untouched base image.
  It is an emulator limitation, not an image fault; CI runs it natively.
  Never weaken the gate.

## Rules

- Keep the two recipes identical apart from `name`, `description` and `base-image`.
- No developer tooling, app grid folders or SSH server. `verify-image.sh`
  fails the build if studio packages (`FORBIDDEN_RPMS`), an app-folders
  dconf file or an enabled `sshd` appear.
- Tailscale is installed but never signed in by the image, the installer or
  any script. Whoever looks after a machine signs it in to their own
  tailnet (see `files/system/usr/share/shatteredvales/docs/Getting Remote Help.html`).
  Never commit Tailscale keys, password hashes or `cosign.key`.
- Never bake self-updating tools into `/usr`; it is read-only. Per-person
  setup goes in `files/system/usr/libexec/shatteredvales/first-login.sh` as
  a versioned step (`run_step <name>-v1 <function>`). Bump the suffix to
  force a step to run again for everyone.
- `verify-image.sh` is the release gate. When adding software, add it to
  `REQUIRED_RPMS` or `REQUIRED_PATHS` there.
- GNOME Shell CSS selectors, extension settings and AccountsService's D-Bus
  API can change between releases. On every Fedora major bump, re-check
  `files/system/usr/share/shatteredvales/theme/shell-overrides.css.in`, the
  dconf extension keys and Family Setup, and test on hardware before merging.
- Builds from `main` publish only `:testing` (`alt-tags` in both recipes).
  `:latest` moves only through `.github/workflows/promote.yml`, which
  verifies the signature and re-tags by digest. Never make CI push `:latest`
  directly; that would skip the canary week for every family machine.
- System-wide defaults that people may override go in `/etc` config files
  (dconf `local.d`, browser policies, `mimeapps.list`), never into home folders.
- The repository is public: anyone may build and use this edition.

## Code standards (organization policy)

- Every script starts with a header block stating its purpose, inputs, usage
  and exit codes. Every function has a doc comment describing what it does,
  its arguments and its return value (docstrings in Python).
- Inline comments explain **why**, never restate what the code does.
- Never write change-tracking comments ("added", "updated per request",
  "new logic"). Code is always written as a clean final artifact.
- Shell: `set -euo pipefail` (except where failures are deliberately
  tolerated, which must be commented), quoted expansions, shellcheck-clean.
