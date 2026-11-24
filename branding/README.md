# Branding sources (Home Edition)

Everything visual in the image is generated from this folder by
`just branding`. Never hand-edit the generated PNGs under `files/system`.

## Required inputs

| File | What it is |
|---|---|
| `brand.env` | Colors, fonts, wordmark text |
| `source/logo.svg` | Full-color logo mark (square-ish, transparent background) |
| `source/logo-symbolic.svg` | Single-color white version for the top-bar menu |
| `source/fonts/brand-regular.ttf` | Body font file matching `BRAND_FONT_FAMILY` |
| `source/fonts/brand-bold.ttf` | Bold weight for the wordmark |

## Generated outputs

| Output | Used by |
|---|---|
| `usr/share/backgrounds/shatteredvales/wallpaper.png` | Desktop and lock background |
| `usr/share/shatteredvales/lockscreen-header.png` | Logo + two-line name above the lock clock (on a tall transparent canvas; see `shell-overrides.css.in`) |
| `usr/share/shatteredvales/avatar.png` | Default account picture for everyday accounts, gold (first login, Family Setup) |
| `usr/share/shatteredvales/avatar-admin.png` | Default account picture for administrators, red foil (`BRAND_ADMIN_FOIL_STOPS`) |
| `usr/share/pixmaps/fedora_logo_med.png`, `fedora_whitelogo_med.png` | Settings > About lockup with the blue edition line (light and dark mode) |
| `usr/share/icons/hicolor/scalable/apps/shatteredvales-{update,family-setup}.svg` | System Update and Family Setup launchers |
| `usr/share/plymouth/themes/shatteredvales/watermark.png` | Boot splash |
| `usr/share/pixmaps/shatteredvales-gdm-logo.png` | Login screen logo (mark, OS name, edition) |
| `usr/share/pixmaps/shatteredvales-logo-symbolic.svg` | Logo Menu button |
| `usr/share/icons/hicolor/*/apps/shatteredvales-logo.*` | Settings > About, notifications |
| `usr/share/shatteredvales/brand.env` | Build scripts inside the image |
