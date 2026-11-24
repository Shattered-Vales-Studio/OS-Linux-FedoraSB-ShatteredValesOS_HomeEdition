# Branding sources (Home Edition)

Home Edition's artwork is rendered by Core Edition's renderer with Core's
fonts, logo and wallpaper generator, so every edition shares one look.
This folder holds only what makes Home different:

| File | What it is |
|---|---|
| `brand.env` | A copy of Core's `branding/brand.env` with Home's edition block: name, id, image name, repository, wordmark lines and the edition blue (contrast ratios beside it) |
| `icons/shatteredvales-family-setup.glyph` | SVG elements of the Family Setup launcher glyph, drawn on Core's dark tile |

`just branding` fetches Core into `build/core` (git-ignored; set `CORE_REF`
to render with a Core branch) and renders. Never hand-edit the generated
files; change this folder and re-render. When Core's `brand.env` gains a
value, copy it here too.

## Generated outputs

Only the artwork that names the edition is written into `files/system`;
wallpapers, account pictures, logo icons, the boot-menu frame and fonts
and the terminal logo come from Core's image.

| Output | Used by |
|---|---|
| `usr/share/shatteredvales/lockscreen-header.png` | Logo and "Shattered Vales OS / Home Edition" above the lock clock |
| `usr/share/plymouth/themes/shatteredvales/watermark.png` | Boot splash |
| `usr/share/pixmaps/shatteredvales-gdm-logo.png` | Login screen logo (mark, OS name, edition) |
| `usr/share/pixmaps/fedora_logo_med.png`, `fedora_whitelogo_med.png` | Settings > About lockup with the blue edition line (light and dark mode) |
| `usr/share/shatteredvales/grub-theme/logo.png`, `theme.txt` | Boot menu logo and its placement |
| `usr/share/icons/hicolor/scalable/apps/shatteredvales-family-setup.svg` | Family Setup launcher |
| `usr/share/shatteredvales/brand.env` | Build scripts inside the image |
