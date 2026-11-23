# Shattered Vales OS Home Edition

A calm, simple computer for the whole family: Fedora Silverblue with the
Shattered Vales black-and-gold look, the everyday apps people need, and
nothing they don't. It updates itself, can't be broken by a bad update (it
can always go back), and lets a family member help over the internet when
asked.

Built nightly by GitHub Actions with [BlueBuild](https://blue-build.org)
and signed with cosign. Anyone is welcome to use it.

| Image | For |
|---|---|
| `ghcr.io/shattered-vales-studio/shatteredvales-os-home` | AMD / Intel graphics, including mini-PCs |
| `ghcr.io/shattered-vales-studio/shatteredvales-os-home-nvidia` | NVIDIA (RTX 20xx / GTX 16xx and newer) |

x86_64 (Intel and AMD) computers only for now; Arm laptops such as
Snapdragon models are not supported yet.

## What's on it

- **Firefox** as the web browser, with a **Streaming** folder on the
  bookmarks bar: Netflix, Disney+, Prime Video, HBO Max, Hulu, Paramount+,
  Peacock, Apple TV+, YouTube, YouTube TV and Movies Anywhere. Firefox plays
  protected video, so these work without extra setup (most services stream
  at HD quality on Linux; Peacock does not officially support Linux).
- **Office and photos** from the Craft App Suite, installed for each person
  at first sign-in: WordCraft (documents), GridCraft (spreadsheets),
  DeckCraft (slides), PdfCraft (PDFs), PhotoCraft (photo editing) and
  LightCraft (camera photos). They open Word, Excel, PowerPoint and PDF
  files. ArtCraft Launcher keeps them up to date and offers the rest of the
  suite.
- **Everyday apps:** photo viewer, video player (and VLC for everything
  else), music player, text editor, calculator, calendar, clocks, weather,
  camera, document scanner, archive manager, and Bitwarden for passwords.
- **More apps** are one click away in **Software**.
- **Simple by design:** one app list with no folders, a short dock at the
  bottom (Firefox, Files, PhotoCraft, WordCraft, VLC, Settings, System
  Update), and larger text offered to each person at first sign-in.

## Accounts: Family Setup

The first time the computer starts, it asks for a language and time zone
and makes the first account. That account is an **administrator**.

When that person first signs in, **Family Setup** explains the two kinds
of account in plain words and helps make the rest, all in one sitting if
you like:

- An **everyday account** for each person. Their files and settings are
  their own.
- One **administrator account** for whoever looks after the computer: it
  installs apps, adds people and fixes problems. If the first account was
  made for a parent's everyday use, Family Setup makes a separate
  administrator account and turns the parent's into an everyday one.

Each person can choose their own password the first time they sign in, or
you can set it for them. Administrators get a red logo picture and everyone
else a gold one, so the sign-in screen shows who is who. Open **Family
Setup** from the app list at any time to add people later.

## Remote help

Tailscale is installed but switched off. Nothing is shared until someone
sets it up. Each person's **Documents** folder has *Getting Remote Help*,
which walks a helper through it: make a free Tailscale account, run
`sudo tailscale up --ssh` on this computer, and sign in. Firefox also has a
*Remote Help (Tailscale)* bookmark. There is no SSH server; remote access
goes through Tailscale only.

## Updates

Updates download in the background and apply the next time the computer
restarts. A reminder appears if one has waited a few days. **System
Update** in the dock checks now and offers to restart; right-click it to
see what is waiting or to **go back to the previous version** if anything
misbehaves.

## Installing

### On a new computer

Use a USB stick made with the installer in
[Shattered-Vales-Studio/OS-Installer](https://github.com/Shattered-Vales-Studio/OS-Installer)
and flashed with balenaEtcher. The Home Edition stick installs offline.

### On a computer already running Fedora Silverblue

No reinstall needed: accounts, files and Flatpak apps all stay. In a
terminal:

```bash
curl -fsSLO https://raw.githubusercontent.com/Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS_HomeEdition/main/sv-migrate.sh
bash sv-migrate.sh
```

(`wget https://raw.githubusercontent.com/Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS_HomeEdition/main/sv-migrate.sh`
works too.) The script picks the right image for the graphics card, removes
add-on packages that would clash (such as RPM Fusion's NVIDIA driver),
shows the plan and asks before changing anything. Add `--dry-run` to only
see the plan. After the restart the computer switches itself to the
signature-verified image.

**NVIDIA computers with Secure Boot on:** after the first restart run
`blujust enroll-secure-boot-key`, restart, choose *Enroll MOK* on the blue
screen and enter the password `bluebuild`.

## Release channels

| Tag | Who runs it | Updated |
|---|---|---|
| `:testing` | One or two test machines | Every build from `main` (nightly) |
| `:latest` | Every other machine | Weekly (Tuesdays) by the *promote-images* workflow, or on demand |
| `:stable-YYYYMMDD` | Nobody directly; rollback points | Each promotion |

Promotion re-tags the already-signed `:testing` image after verifying its
signature. Set the repository variable `PAUSE_PROMOTION` to `true` to hold
promotions; run *promote-images* manually with an older `stable-YYYYMMDD`
tag to roll every machine back.

## Useful commands

| Command | Does |
|---|---|
| `sv-update` | Shows the waiting update; `now` updates immediately, `rollback` goes back |
| `sv-doctor` | Health check for whoever helps; `sv-doctor --copy` copies the report |
| `sv-gpu-image status` | Shows whether the right image for the graphics card is installed |
| `sv-first-login` | Re-runs per-person setup |
| `rpm-ostree rollback` | Boots the previous version |

## Developing

See [CLAUDE.md](CLAUDE.md) for how the image is put together and the
rules for changing it, and [branding/README.md](branding/README.md) for the
artwork. Verify a pulled image with the committed key:

```bash
cosign verify --key cosign.pub ghcr.io/shattered-vales-studio/shatteredvales-os-home:latest
```
