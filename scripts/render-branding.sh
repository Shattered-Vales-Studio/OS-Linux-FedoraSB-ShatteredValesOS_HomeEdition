#!/usr/bin/env bash
#
# render-branding.sh
#
# Purpose:
#   Generates every branded image in the OS from branding/source and
#   branding/brand.env, and stages them under files/system. The artwork
#   reproduces the website's look: the logo and an uppercase Cinzel wordmark
#   filled with the gold-foil gradient, a soft gold glow, and the radial
#   page-background gradient. Rendering runs in a Fedora container so the
#   output is identical on macOS and Linux and no image tools need to be
#   installed on the host.
#
# Inputs:
#   branding/brand.env, branding/source/logo.svg,
#   branding/source/logo-symbolic.svg, branding/source/fonts/*.ttf
#
# Usage:
#   scripts/render-branding.sh            (from the repo root, or `just branding`)
#
# Requirements:
#   docker (OrbStack works) or podman on the host.
#
# Exit codes:
#   0 on success, 1 if a required source file is missing or rendering fails.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT

# container_cli
#   Prints the available container runtime.
#   Arguments: none
#   Output: "docker" or "podman" on stdout
#   Returns: 1 if neither docker nor podman is installed
container_cli() {
    if command -v docker >/dev/null; then echo docker
    elif command -v podman >/dev/null; then echo podman
    else echo "docker or podman is required" >&2; return 1
    fi
}

# render_inside
#   Body executed inside the container. Kept as a single function (with
#   nested helpers) so it can be shipped into the container with
#   `declare -f` and the whole pipeline stays readable in one file.
#   Arguments: none
#   Returns: non-zero on any rendering failure
render_inside() {
    set -euo pipefail
    dnf -y -q install ImageMagick librsvg2-tools grub2-tools-extra chafa \
        python3-numpy python3-pillow python3-scipy >/dev/null
    cd /work
    # shellcheck source=/dev/null
    source branding/brand.env

    local src=branding/source out=files/system
    local tmp; tmp="$(mktemp -d)"
    local -a stops
    read -r -a stops <<<"${BRAND_FOIL_STOPS}"
    local hex="${BRAND_ACCENT#\#}"
    local BRAND_ACCENT_RGB_CSV
    BRAND_ACCENT_RGB_CSV="$(printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}")"

    local f
    for f in "${src}/logo.svg" "${src}/logo-symbolic.svg" \
             "${BRAND_FONT_FILE}" "${BRAND_FONT_BOLD_FILE}" "${BRAND_DISPLAY_FONT_FILE}"; do
        [[ -f "${f}" ]] || { echo "Missing ${f}" >&2; exit 1; }
    done

    # foil_svg
    #   Writes a copy of the logo whose fill is the foil gradient. The
    #   gradient spans the full 0..viewBox width, matching the site, where
    #   the gradient covers the logo element's whole box through a mask.
    #   Arguments: $1 output path, $2 optional space-separated stop colours
    #              (default: the gold BRAND_FOIL_STOPS)
    #   Returns: 0 on success
    foil_svg() {
        local width offsets="" i n
        local -a use=("${stops[@]}")
        if [[ -n "${2:-}" ]]; then
            read -r -a use <<<"$2"
        fi
        n=${#use[@]}
        width="$(grep -oE 'viewBox="[^"]+"' "${src}/logo.svg" | awk '{print $3}')"
        for (( i = 0; i < n; i++ )); do
            offsets+="<stop offset=\"$(( i * 100 / (n - 1) ))%\" stop-color=\"${use[i]}\"/>"
        done
        sed -e '/^<!--/d' \
            -e "s|<g>|<defs><linearGradient id=\"foil\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"${width}\" y2=\"0\">${offsets}</linearGradient></defs><g>|" \
            -e "s|fill=\"${BRAND_ACCENT}\"|fill=\"url(#foil)\"|gI" \
            "${src}/logo.svg" > "$1"
        grep -q 'url(#foil)' "$1" || { echo "logo.svg fill is not ${BRAND_ACCENT}" >&2; return 1; }
    }

    # tile_icon
    #   Writes a scalable app icon: a rounded tile filled with the site's
    #   page gradient and a thin gold edge, with a line glyph stroked in the
    #   foil gradient, on a 128x128 canvas.
    #   Arguments: $1 icon name, $2 SVG elements for the glyph (unstyled;
    #              stroke and fill come from the enclosing group)
    #   Returns: 0 on success
    tile_icon() {
        local offsets="" i n=${#stops[@]}
        for (( i = 0; i < n; i++ )); do
            offsets+="<stop offset=\"$(( i * 100 / (n - 1) ))%\" stop-color=\"${stops[i]}\"/>"
        done
        cat > "${out}/usr/share/icons/hicolor/scalable/apps/$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="foil" gradientUnits="userSpaceOnUse" x1="24" y1="24" x2="104" y2="104">${offsets}</linearGradient>
    <radialGradient id="page" cx="64" cy="64" r="80" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="${BRAND_BG_GLOW}"/><stop offset="100%" stop-color="${BRAND_BG}"/>
    </radialGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="26" fill="url(#page)" stroke="${BRAND_ACCENT}" stroke-opacity="0.45" stroke-width="2"/>
  <g fill="none" stroke="url(#foil)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">$2</g>
</svg>
SVG
    }

    # foilify
    #   Replaces the colour of every opaque pixel in a PNG with the foil
    #   gradient, keeping its alpha. Used for rasterised text, which cannot
    #   carry an SVG gradient through ImageMagick's label renderer.
    #   Arguments: $1 input PNG, $2 output PNG
    #   Returns: 0 on success
    foilify() {
        local size
        size="$(magick identify -format '%wx%h' "$1")"
        magick "${stops[@]/#/xc:}" +append -filter Triangle -resize "${size}!" \
            \( "$1" -alpha extract \) -alpha off -compose CopyOpacity -composite "$2"
    }

    # glow
    #   Adds the site's soft gold halo (drop-shadow 0 0 14px at 14% gold)
    #   behind a transparent PNG. The canvas grows so the halo is not cut.
    #   Arguments: $1 input PNG, $2 output PNG, $3 blur radius in px
    #   Returns: 0 on success
    glow() {
        magick "$1" \( +clone -background "${BRAND_ACCENT}" -shadow "14x$3+0+0" \) \
            +swap -background none -layers merge +repage "$2"
    }

    # wordmark
    #   Renders the two-line name in uppercase Cinzel Bold with the site's
    #   0.1em letter spacing: "SHATTERED VALES OS" in the gold foil, and
    #   "HOME EDITION" below it in the edition blue (10.4:1 on the black
    #   lock and boot backgrounds), the same pairing as Settings > About.
    #   Arguments: $1 point size, $2 output PNG
    #   Returns: 0 on success
    wordmark() {
        local pt="$1" kern
        kern="$(awk -v p="${pt}" 'BEGIN { printf "%.1f", p * 0.1 }')"
        magick -background none -fill white -font "${BRAND_DISPLAY_FONT_FILE}" \
            -pointsize "${pt}" -kerning "${kern}" label:"${BRAND_NAME_LINE1^^}" -trim +repage \
            "${tmp}/wm-line0-white.png"
        foilify "${tmp}/wm-line0-white.png" "${tmp}/wm-line0.png"
        magick -background none -fill "${BRAND_EDITION_BLUE_DARK}" -font "${BRAND_DISPLAY_FONT_FILE}" \
            -pointsize "${pt}" -kerning "${kern}" label:"${BRAND_NAME_LINE2^^}" -trim +repage \
            "${tmp}/wm-line1.png"
        magick "${tmp}/wm-line0.png" \( -size "1x$(( pt / 4 ))" xc:none \) "${tmp}/wm-line1.png" \
            -background none -gravity center -append "$2"
    }

    mkdir -p "${out}/usr/share/backgrounds/shatteredvales" \
             "${out}/usr/share/shatteredvales" \
             "${out}/usr/share/plymouth/themes/shatteredvales" \
             "${out}/usr/share/pixmaps" \
             "${out}/usr/share/icons/hicolor/scalable/apps"

    foil_svg "${tmp}/logo-foil.svg"
    foil_svg "${tmp}/logo-admin.svg" "${BRAND_ADMIN_FOIL_STOPS}"
    rsvg-convert -h 1024 "${tmp}/logo-admin.svg" -o "${tmp}/logo-admin-1024.png"
    local h
    for h in 1024 512 256 192; do
        rsvg-convert -h "${h}" "${tmp}/logo-foil.svg" -o "${tmp}/logo-${h}.png"
    done

    # Lock screen header: logo above the wordmark, at the top of a tall
    # transparent canvas. GNOME Shell's St toolkit only accepts pixel values
    # for background-position and otherwise centres the image on the clock,
    # so the canvas is exactly the clock's min-height in
    # shell-overrides.css.in (480x920): centred, its top edge meets the top
    # of the clock and the header sits above the time. Rendered at 2x so it
    # stays sharp on HiDPI displays.
    wordmark 72 "${tmp}/wm-lock.png"
    magick "${tmp}/logo-256.png" -trim +repage "${tmp}/logo-lock.png"
    magick "${tmp}/logo-lock.png" \( -size 1x28 xc:none \) "${tmp}/wm-lock.png" \
        -background none -gravity center -append "${tmp}/lock-raw.png"
    glow "${tmp}/lock-raw.png" "${tmp}/lock-glow.png" 14
    magick "${tmp}/lock-glow.png" -resize 960x440 -background none -gravity center \
        -extent 960x440 -gravity north -extent 960x1840 \
        "${out}/usr/share/shatteredvales/lockscreen-header.png"

    # Boot splash watermark. Plymouth draws it 1:1 on the framebuffer, so
    # it is sized for a 1080p panel and stays proportionate on 4K.
    wordmark 56 "${tmp}/wm-boot.png"
    magick "${tmp}/logo-512.png" -trim +repage -resize x300 "${tmp}/logo-boot.png"
    magick "${tmp}/logo-boot.png" \( -size 1x36 xc:none \) "${tmp}/wm-boot.png" \
        -background none -gravity center -append "${tmp}/boot-raw.png"
    glow "${tmp}/boot-raw.png" "${out}/usr/share/plymouth/themes/shatteredvales/watermark.png" 14

    # 4K wallpaper: the site's radial page gradient (glow colour at the
    # centre fading to the background at 70% of the half-diagonal) with a quiet
    # foil logo. Rendered at 16 bits and dithered to 8 so the dark gradient
    # does not band on 8-bit panels.
    magick -size 3840x2160 -depth 16 \
        -define gradient:radii=1542,1542 "radial-gradient:${BRAND_BG_GLOW}-${BRAND_BG}" \
        \( "${tmp}/logo-1024.png" -trim +repage -resize x900 \
           -channel A -evaluate multiply 0.35 +channel \) \
        -gravity center -composite \
        -attenuate 0.6 +noise Uniform -dither FloydSteinberg -depth 8 \
        "${out}/usr/share/backgrounds/shatteredvales/wallpaper.png"

    # Login screen logo: GDM shows it at roughly 48px tall under the user
    # list (rendered at 2x), so it is the mark beside two lines: the OS name
    # in foil and the edition in the dark-mode edition blue, which suits
    # the login screen's black background.
    magick -background none -fill white -font "${BRAND_DISPLAY_FONT_FILE}" \
        -pointsize 96 -kerning 9.6 label:"${BRAND_OS_NAME^^}" -trim +repage "${tmp}/gdm-text-white.png"
    foilify "${tmp}/gdm-text-white.png" "${tmp}/gdm-text.png"
    magick -background none -fill "${BRAND_EDITION_BLUE_DARK}" -font "${BRAND_FONT_BOLD_FILE}" \
        -pointsize 60 -kerning 12 label:"${BRAND_EDITION^^}" -trim +repage "${tmp}/gdm-edition.png"
    magick "${tmp}/gdm-text.png" \( -size 1x22 xc:none \) "${tmp}/gdm-edition.png" \
        -background none -gravity west -append "${tmp}/gdm-lines.png"
    magick "${tmp}/logo-256.png" -trim +repage -resize x220 "${tmp}/logo-gdm.png"
    magick "${tmp}/logo-gdm.png" \( -size 36x1 xc:none \) "${tmp}/gdm-lines.png" \
        -background none -gravity center +append -resize x96 +repage \
        "${out}/usr/share/pixmaps/shatteredvales-gdm-logo.png"

    # Default account pictures: the logo on the site's page gradient, gold
    # for everyday accounts and red for administrators, so the user list
    # shows at a glance which accounts can change the computer. GNOME crops
    # account pictures to a circle, so the mark stays inside the inscribed
    # circle with room to spare.
    local avatar logo
    for avatar in avatar:logo-1024.png avatar-admin:logo-admin-1024.png; do
        logo="${avatar#*:}"
        magick -size 512x512 -define gradient:radii=256,256 \
            "radial-gradient:${BRAND_BG_GLOW}-${BRAND_BG}" \
            \( "${tmp}/${logo}" -trim +repage -resize 300x300 \) \
            -gravity center -composite "${out}/usr/share/shatteredvales/${avatar%%:*}.png"
    done

    cp "${src}/logo-symbolic.svg" "${out}/usr/share/pixmaps/shatteredvales-logo-symbolic.svg"
    cp "${tmp}/logo-foil.svg" "${out}/usr/share/icons/hicolor/scalable/apps/shatteredvales-logo.svg"
    local size
    for size in 48 64 128 256; do
        mkdir -p "${out}/usr/share/icons/hicolor/${size}x${size}/apps"
        rsvg-convert -w "${size}" -h "${size}" -a "${tmp}/logo-foil.svg" \
            -o "${out}/usr/share/icons/hicolor/${size}x${size}/apps/shatteredvales-logo.png"
    done

    # Settings > About logo. Fedora builds GNOME Settings with
    # -Ddistributor_logo pointing at these two fedora-logos files (light and
    # dark mode), so it ignores os-release LOGO; replacing the files is the
    # only way to brand the page. Fedora's name is plain text; its logo
    # artwork is not reused.
    #
    # GtkPicture draws the file at its pixel size and has no way to take a
    # HiDPI version, so on 125-150% displays GNOME stretches it. To stay
    # legible when stretched it uses large, slightly thickened lettering, a
    # widely tracked bold subtitle and a light sharpen after downscaling,
    # at 400x150 (still inside the About page's column). The edition line
    # uses the edition blue and the subtitle the brand text colour for each
    # mode, all AAA on libadwaita's backgrounds (ratios in brand.env).
    magick -background none -fill white -font "${BRAND_DISPLAY_FONT_FILE}" \
        -pointsize 96 -kerning 9.6 label:"${BRAND_OS_NAME^^}" -trim +repage \
        -morphology Dilate Disk:1.5 "${tmp}/about-name-white.png"
    foilify "${tmp}/about-name-white.png" "${tmp}/about-name.png"
    magick "${tmp}/logo-256.png" -trim +repage -resize x240 "${tmp}/logo-about.png"
    local mode colour blue file
    for mode in light dark; do
        if [[ "${mode}" == light ]]; then
            colour="${BRAND_BG}" blue="${BRAND_EDITION_BLUE_LIGHT}" file=fedora_logo_med.png
        else
            colour="${BRAND_TEXT}" blue="${BRAND_EDITION_BLUE_DARK}" file=fedora_whitelogo_med.png
        fi
        magick -background none -fill "${blue}" -font "${BRAND_FONT_BOLD_FILE}" \
            -pointsize 66 -kerning 12 label:"${BRAND_EDITION^^}" -trim +repage "${tmp}/about-edition-${mode}.png"
        magick -background none -fill "${colour}" -font "${BRAND_FONT_BOLD_FILE}" \
            -pointsize 50 -kerning 10 label:"BASED ON FEDORA" -trim +repage "${tmp}/about-sub-${mode}.png"
        magick "${tmp}/about-name.png" \( -size 1x24 xc:none \) "${tmp}/about-edition-${mode}.png" \
            \( -size 1x20 xc:none \) "${tmp}/about-sub-${mode}.png" \
            -background none -gravity west -append "${tmp}/about-text-${mode}.png"
        magick "${tmp}/logo-about.png" \( -size 40x1 xc:none \) "${tmp}/about-text-${mode}.png" \
            -background none -gravity center +append \
            -resize 384x138 -unsharp 0x0.6+0.6+0 \
            -gravity center -extent 400x150 +repage "${out}/usr/share/pixmaps/${file}"
    done

    # Boot menu (GRUB theme), installed into /boot by
    # shatteredvales-grub-theme.service. Laid out for 1920x1080 and
    # stretched to the screen: the site's page gradient, the Home Edition
    # logo lockup, Lato menu items in the muted text colour and the selected
    # entry in gold inside a thin gold frame. Contrast (AAA): items
    # ${BRAND_TEXT_MUTED} on ${BRAND_BG} 8.1:1; selected ${BRAND_ACCENT} on the
    # frame's 10% gold fill 7.7:1. Fonts are converted to GRUB's PF2 format,
    # and every image is written as 8-bit RGBA (PNG32:): GRUB's PNG reader
    # rejects 16-bit and palette PNGs, and one bad image makes it drop the
    # whole theme for the plain menu.
    local grub="${out}/usr/share/shatteredvales/grub-theme" logo_w piece size
    mkdir -p "${grub}"
    magick -size 1920x1080 -define gradient:radii=1100,1100 \
        "radial-gradient:${BRAND_BG_GLOW}-${BRAND_BG}" -depth 8 "PNG32:${grub}/background.png"
    # Home Edition: the name in foil over HOME EDITION in the edition blue
    # (10.4:1 on the background), beside the mark.
    magick "${tmp}/about-name.png" \( -size 1x24 xc:none \) "${tmp}/about-edition-dark.png" \
        -background none -gravity west -append "${tmp}/grub-text.png"
    magick "${tmp}/logo-about.png" \( -size 48x1 xc:none \) "${tmp}/grub-text.png" \
        -background none -gravity center +append -resize x140 +repage -depth 8 "PNG32:${grub}/logo.png"
    logo_w="$(magick identify -format '%w' "${grub}/logo.png")"
    # Nine-slice selection frame: 2 px gold edges at 60% over a 10% gold fill.
    magick -size 1x1 "xc:rgba(${BRAND_ACCENT_RGB_CSV},0.10)" "PNG32:${grub}/select_c.png"
    for piece in n s; do magick -size 1x2 "xc:rgba(${BRAND_ACCENT_RGB_CSV},0.60)" "PNG32:${grub}/select_${piece}.png"; done
    for piece in w e; do magick -size 2x1 "xc:rgba(${BRAND_ACCENT_RGB_CSV},0.60)" "PNG32:${grub}/select_${piece}.png"; done
    for piece in nw ne sw se; do magick -size 2x2 "xc:rgba(${BRAND_ACCENT_RGB_CSV},0.60)" "PNG32:${grub}/select_${piece}.png"; done
    for size in 20 28; do
        grub2-mkfont -s "${size}" -o "${grub}/lato-regular-${size}.pf2" "${BRAND_FONT_FILE}"
    done
    grub2-mkfont -s 28 -o "${grub}/lato-bold-28.pf2" "${BRAND_FONT_BOLD_FILE}"
    cat > "${grub}/theme.txt" <<THEME
# Shattered Vales OS boot menu (GRUB theme). Generated by
# scripts/render-branding.sh from branding/; do not edit by hand.
title-text: ""
desktop-image: "background.png"
desktop-image-scale-method: "stretch"
desktop-color: "${BRAND_BG}"
terminal-font: "Lato Regular 20"

+ image {
  left = 50%-$(( logo_w / 2 ))
  top = 16%
  file = "logo.png"
}

+ boot_menu {
  left = 50%-420
  width = 840
  top = 40%
  height = 38%
  item_font = "Lato Regular 28"
  selected_item_font = "Lato Bold 28"
  item_color = "${BRAND_TEXT_MUTED}"
  selected_item_color = "${BRAND_ACCENT}"
  item_height = 56
  item_padding = 18
  item_spacing = 10
  icon_width = 0
  icon_height = 0
  item_icon_space = 20
  selected_item_pixmap_style = "select_*.png"
  scrollbar = false
}

+ label {
  id = "__timeout__"
  left = 0
  width = 100%
  top = 82%
  align = "center"
  font = "Lato Regular 20"
  color = "${BRAND_TEXT_MUTED}"
  text = "Starting in %d seconds"
}

+ label {
  left = 0
  width = 100%
  top = 88%
  align = "center"
  font = "Lato Regular 20"
  color = "${BRAND_TEXT_MUTED}"
  text = "Arrow keys to choose an earlier version, Enter to start"
}
THEME
    # Loaded from /boot/grub2/custom.cfg. Falls back to the plain menu when
    # the fonts cannot be read or the firmware has no graphics mode.
    cat > "${grub}/theme.cfg" <<'CFG'
# Shattered Vales OS boot menu theme. Installed by
# shatteredvales-grub-theme.service and sourced from /boot/grub2/custom.cfg.
set sv_theme="$prefix/themes/shatteredvales"
if loadfont "$sv_theme/lato-regular-20.pf2"; then
  loadfont "$sv_theme/lato-regular-28.pf2"
  loadfont "$sv_theme/lato-bold-28.pf2"
  insmod gfxterm
  insmod gfxmenu
  insmod png
  load_video
  set gfxmode=1920x1080,1920x1200,auto
  terminal_output gfxterm
  set theme="$sv_theme/theme.txt"
  export theme
fi
CFG

    # Launcher icons for the edition's own tools: a dark tile in the site's
    # surface colours with a gold-foil line glyph, so they are recognisable
    # in the app grid while matching the logo. Glyphs are generic shapes
    # (two people, update arrows), never third-party logos.
    tile_icon "shatteredvales-family-setup" \
        '<circle cx="50" cy="44" r="12"/><path d="M28 96c0-16 10-27 22-27s22 11 22 27"/><circle cx="84" cy="52" r="9"/><path d="M76 73c2-1 5-2 8-2 10 0 16 10 16 23"/>'
    tile_icon "shatteredvales-update" \
        '<path d="M88 50a28 28 0 0 0-50-6"/><path d="M36 30v14h14"/><path d="M40 78a28 28 0 0 0 50 6"/><path d="M92 98V84H78"/>'

    # Terminal logo for fastfetch: the gold-foil mark as 24-bit colour
    # quadrant blocks, pre-rendered so the image needs no image libraries
    # and every monospace font can draw it. The strokes are thickened first
    # because the mark's fine lines vanish at 36 columns. --polite keeps
    # chafa from adding cursor and screen control sequences that would
    # break fastfetch's layout.
    mkdir -p "${out}/usr/share/shatteredvales/fastfetch"
    rsvg-convert -w 600 -h 600 "${src}/logo.svg" -o "${tmp}/logo-term.png"
    magick "${tmp}/logo-term.png" -trim +repage -morphology Dilate Disk:3 "${tmp}/logo-term.png"
    chafa --polite on --format symbols --colors full --symbols quad \
        --bg "${BRAND_BG}" --size 36x18 "${tmp}/logo-term.png" \
        > "${out}/usr/share/shatteredvales/fastfetch/logo.txt"

    cp branding/brand.env "${out}/usr/share/shatteredvales/brand.env"
    rm -rf "${tmp}"

    # Alternative 4K wallpapers (space, Earth, vale, circuit) for Settings >
    # Appearance. They are painted procedurally from the brand palette, so
    # they live in their own generator rather than as ImageMagick steps.
    python3 branding/wallpapers/generate.py --env branding/brand.env \
        --out "${out}/usr/share/backgrounds/shatteredvales"
    echo "Branding rendered into ${out}"
}

# main
#   Runs render_inside in a throwaway Fedora container with the repo
#   mounted at /work.
#   Arguments: none
#   Returns: the container's exit status
main() {
    local cli; cli="$(container_cli)"
    "${cli}" run --rm -v "${ROOT}:/work:Z" registry.fedoraproject.org/fedora:latest \
        bash -c "$(declare -f render_inside); render_inside"
}

main "$@"
