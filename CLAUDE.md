# CLAUDE.md — Shattered Vales OS Home Edition

You are working on Shattered Vales OS **Home Edition**: a custom Fedora
Atomic (Silverblue) image for family computers, built with BlueBuild,
published to GHCR, and installed on home machines (mini-PCs, desktops,
laptops). It is built on **Core Edition**
(`Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS_CoreEdition`),
which carries everything the editions share; read Core's CLAUDE.md too.
Read this whole file before making changes.

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

- Both recipes use Core's promoted image (`shatteredvales-os-core(-nvidia)`,
  `image-version: latest`) as their base and only add or replace. Core's
  changes and Fedora releases reach Home at its next build after Core is
  promoted. **Anything that every edition should have belongs in Core**,
  not here; this repository holds only what is Home-specific.
- `recipes/recipe-base.yml` and `recipes/recipe-nvidia.yml` differ **only** in
  `name`, `description` and `base-image`. Every other change goes in
  `recipes/common/*.yml` so the two images can never drift.
- `files/system/` is copied over Core's tree. Home extends Core through its
  drop-ins rather than copies of Core's files:
  - desktop defaults: `etc/dconf/db/local.d/50-shatteredvales-home`
    (overrides Core's `10-…`, the later name wins);
  - per-person setup: `usr/libexec/shatteredvales/first-login.d/50-home.sh`
    (registers `LOGIN_HOOKS`, `STEPS`, `LATE_STEPS` with Core's framework);
  - release gate: `usr/share/shatteredvales/verify.d/home.list` and
    `usr/libexec/shatteredvales/verify.d/*.sh`.
  Firefox's policy and Chromium's managed bookmarks are whole files that
  replace Core's.
- The recipes re-run Core's build steps from the image
  (`/usr/libexec/shatteredvales/build/apply-branding.sh`, then signing and
  `verify-image.sh`), so Home's brand.env, artwork and dconf files apply.
- `branding/` holds Home's `brand.env` (Core's with Home's edition block:
  the edition blue, whose contrast ratios are documented there) and
  `icons/*.glyph`. `just branding` renders with Core's renderer, fonts and
  logo, writing only the edition-specific artwork into `files/system`.
  Never hand-edit those generated files; change `branding/` and re-render.
  Check contrast for any new colour pairing before using it (AAA 7:1).
- Moving a Silverblue machine onto Home uses Core's
  `sv-migrate.sh --edition home`.
- Installer USB sticks are built by the separate `Shattered-Vales-Studio/OS-Installer`
  repository.

## Commands

| Command | Purpose |
|---|---|
| `just branding` | Render Home's artwork with Core's renderer (`CORE_REF=<branch>` optional) |
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
- No developer tooling, app grid folders or SSH server. The release gate
  fails the build if studio packages, an app-folders dconf file or an
  enabled `sshd` appear (`forbid-*` and `service-disabled` rules in
  `verify.d/home.list`).
- Tailscale is installed but never signed in by the image, the installer or
  any script. Whoever looks after a machine signs it in to their own
  tailnet (see `files/system/usr/share/shatteredvales/docs/Getting Remote Help.html`).
  Never commit Tailscale keys, password hashes or `cosign.key`.
- Never bake self-updating tools into `/usr`; it is read-only. Home's
  per-person setup goes in `first-login.d/50-home.sh` as a versioned step
  (`STEPS+=("<name>-v1 <function>")`). Bump the suffix to force a step to
  run again for everyone.
- The release gate is Core's `verify-image.sh`. When adding Home software or
  files, add a rule to `verify.d/home.list`.
- AccountsService's D-Bus API and GNOME's settings can change between
  releases. When Core moves to a new Fedora release, re-check Family Setup
  and Home's dconf keys on Core's `:testing` before Core is promoted.
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
