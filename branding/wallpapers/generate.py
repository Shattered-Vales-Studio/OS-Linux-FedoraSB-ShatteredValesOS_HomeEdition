#!/usr/bin/env python3
"""Procedural 4K wallpapers for Shattered Vales OS.

Purpose:
    Paints the alternative desktop backgrounds offered in Settings >
    Appearance, entirely from code and the brand palette in
    branding/brand.env, so the artwork is original, reproducible and
    re-coloured automatically when the palette changes:

        space.jpg    starfield with a gold nebula
        earth.jpg    a night-side planet at dawn with a gold atmosphere
        vale.jpg     misty forested ridges receding into a lit valley
        circuit.jpg  gold circuit traces over topographic contour lines

    Every random choice comes from a fixed seed per wallpaper, so the same
    inputs always produce the same images. The top and bottom edges are kept
    dark and plain because the GNOME top bar and the dock sit there.

Inputs:
    --env   path to brand.env (default: branding/brand.env)
    --out   output folder (default:
            files/system/usr/share/backgrounds/shatteredvales)
    --only  optional wallpaper names to render (default: all)
    --scale optional size factor for quick previews (default: 1.0)

Usage:
    python3 branding/wallpapers/generate.py
    (normally run by scripts/render-branding.sh inside its Fedora container)

Exit codes:
    0 on success, 1 on a rendering error, 2 on bad usage.
"""

import argparse
import math
import pathlib
import re
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

WIDTH, HEIGHT = 3840, 2160
JPEG_QUALITY = 92

# Fraction of the height kept calm at the top (GNOME top bar) and bottom
# (dock and lock-screen hint text). Sized for the tallest bar at 200% scale.
TOP_CALM = 0.045
BOTTOM_CALM = 0.10


def load_brand(path):
    """Reads KEY="value" pairs from brand.env.

    Args:
        path: path to brand.env.

    Returns:
        dict of variable name to string value.
    """
    values = {}
    pattern = re.compile(r'^([A-Z0-9_]+)="([^"]*)"')
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        match = pattern.match(line.strip())
        if match:
            values[match.group(1)] = match.group(2)
    return values


def rgb(hex_colour):
    """Converts "#rrggbb" to a float RGB array in 0..1.

    Args:
        hex_colour: colour such as "#c5a059".

    Returns:
        numpy array of shape (3,).
    """
    value = hex_colour.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def mix(a, b, t):
    """Linear interpolation that broadcasts a per-pixel weight over RGB.

    Args:
        a: colour or image (..., 3).
        b: colour or image (..., 3).
        t: scalar or (H, W) weight; 0 gives a, 1 gives b.

    Returns:
        the blended colour or image.
    """
    t = np.asarray(t, dtype=np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return a + (b - a) * t


def smoothstep(edge0, edge1, x):
    """Hermite step from 0 at edge0 to 1 at edge1.

    Args:
        edge0: lower edge.
        edge1: upper edge.
        x: input array.

    Returns:
        array in 0..1.
    """
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(rng, height, width, cell):
    """Smooth random field built by cubic upsampling of a coarse grid.

    Args:
        rng: numpy Generator.
        height: output rows.
        width: output columns.
        cell: grid spacing in pixels (larger is smoother).

    Returns:
        float32 array (height, width), roughly zero-mean, unit variance.
    """
    cell = max(cell, 1.0)
    rows = int(math.ceil(height / cell)) + 4
    cols = int(math.ceil(width / cell)) + 4
    grid = rng.standard_normal((rows, cols)).astype(np.float32)
    up = ndimage.zoom(grid, cell, order=3, mode="reflect", grid_mode=True)
    # Cropping away the outer cells hides the reflected border of the zoom.
    off = int(cell)
    return up[off:off + height, off:off + width]


def fbm(rng, height, width, cell, octaves, gain=0.5):
    """Fractal sum of value-noise octaves, normalised to 0..1.

    Args:
        rng: numpy Generator.
        height: output rows.
        width: output columns.
        cell: spacing of the coarsest octave in pixels.
        octaves: number of octaves, each half the spacing of the previous.
        gain: amplitude falloff per octave.

    Returns:
        float32 array (height, width) in 0..1.
    """
    total = np.zeros((height, width), dtype=np.float32)
    amp = 1.0
    for _ in range(octaves):
        total += amp * value_noise(rng, height, width, cell)
        amp *= gain
        cell /= 2.0
    lo, hi = np.percentile(total, (0.5, 99.5))
    return np.clip((total - lo) / (hi - lo), 0.0, 1.0)


def fbm_1d(rng, length, cell, octaves, gain=0.5):
    """One-dimensional fractal noise, used for ridge and treeline profiles.

    Args:
        rng: numpy Generator.
        length: number of samples.
        cell: spacing of the coarsest octave in samples.
        octaves: number of octaves.
        gain: amplitude falloff per octave.

    Returns:
        float32 array (length,), roughly in -1..1.
    """
    total = np.zeros(length, dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for _ in range(octaves):
        points = int(math.ceil(length / cell)) + 4
        grid = rng.standard_normal(points).astype(np.float32)
        xs = np.arange(length, dtype=np.float32) / cell + 1.0
        total += amp * ndimage.map_coordinates(grid, [xs], order=3, mode="reflect")
        norm += amp
        amp *= gain
        cell = max(cell / 2.0, 1.0)
    return total / norm


def vignette(height, width, strength, radius=0.75):
    """Radial darkening towards the corners.

    Args:
        height: rows.
        width: columns.
        strength: darkening at the corners, 0..1.
        radius: normalised distance where darkening begins.

    Returns:
        (height, width) multiplier in 1-strength..1.
    """
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    nx = (xx - width / 2) / (width / 2)
    ny = (yy - height / 2) / (height / 2)
    dist = np.sqrt(nx * nx + ny * ny) / math.sqrt(2.0)
    return 1.0 - strength * smoothstep(radius * 0.6, 1.0, dist / radius * 0.75 + 0.25)


def calm_edges(image, top_floor=0.35, bottom_floor=0.45):
    """Darkens the top and bottom bands where GNOME draws its bars.

    Args:
        image: float RGB image.
        top_floor: brightness multiplier at the very top edge.
        bottom_floor: brightness multiplier at the very bottom edge.

    Returns:
        the image with both bands faded down.
    """
    height = image.shape[0]
    ys = np.arange(height, dtype=np.float32) / height
    top = top_floor + (1.0 - top_floor) * smoothstep(0.0, TOP_CALM * 2.2, ys)
    bottom = bottom_floor + (1.0 - bottom_floor) * smoothstep(1.0, 1.0 - BOTTOM_CALM * 1.8, ys)
    return image * (top * bottom)[:, None, None]


def glow_from(mask, sigmas, weights):
    """Bloom: a weighted sum of blurred copies of a light mask.

    Args:
        mask: (H, W) or (H, W, 3) light intensity.
        sigmas: blur radii in pixels.
        weights: weight for each radius.

    Returns:
        the bloom, same shape as mask.
    """
    out = np.zeros_like(mask)
    for sigma, weight in zip(sigmas, weights):
        if mask.ndim == 3:
            blurred = ndimage.gaussian_filter(mask, (sigma, sigma, 0))
        else:
            blurred = ndimage.gaussian_filter(mask, sigma)
        out += weight * blurred
    return out


def tone(image):
    """Soft highlight roll-off so bright additive light never clips harshly.

    Args:
        image: float RGB image, may exceed 1.

    Returns:
        image in 0..1.
    """
    image = np.maximum(image, 0.0)
    knee = 0.8
    over = np.maximum(image - knee, 0.0)
    return np.where(image > knee, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))), image)


def save_jpeg(image, path, rng):
    """Dithers to 8 bits and writes a high-quality JPEG.

    Dithering stops the large, very dark gradients from banding on 8-bit
    panels.

    Args:
        image: float RGB image in 0..1.
        path: destination file.
        rng: numpy Generator for the dither pattern.

    Returns:
        None.
    """
    noise = (rng.random(image.shape, dtype=np.float32) - rng.random(image.shape, dtype=np.float32))
    pixels = np.clip(tone(image) * 255.0 + noise + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(pixels).save(
        path, "JPEG", quality=JPEG_QUALITY, subsampling=0, optimize=True, progressive=True)


def star_layer(rng, height, width, count, size_range, brightness_power, palette):
    """Scatters point stars with a power-law brightness distribution.

    Args:
        rng: numpy Generator.
        height: rows.
        width: columns.
        count: number of stars.
        size_range: (min, max) blur radius in pixels; 0 keeps single pixels.
        brightness_power: larger values make bright stars rarer.
        palette: list of RGB colours stars are tinted with.

    Returns:
        float RGB image of the stars.
    """
    layer = np.zeros((height, width, 3), dtype=np.float32)
    ys = rng.integers(0, height, count)
    xs = rng.integers(0, width, count)
    level = rng.random(count).astype(np.float32) ** brightness_power
    colours = np.array(palette, dtype=np.float32)[rng.integers(0, len(palette), count)]
    np.add.at(layer, (ys, xs), colours * level[:, None])
    if size_range[1] > 0:
        sigma = (size_range[0] + size_range[1]) / 2.0
        peak = 2.0 * math.pi * sigma * sigma
        layer = ndimage.gaussian_filter(layer, (sigma, sigma, 0)) * peak
    return layer


def warp(field, wx, wy):
    """Samples a field at displaced coordinates (domain warping).

    Domain warping turns plain fractal noise into the swirling, filamentary
    shapes of real gas clouds.

    Args:
        field: (H, W) array to sample.
        wx: (H, W) horizontal displacement in pixels.
        wy: (H, W) vertical displacement in pixels.

    Returns:
        the warped (H, W) array.
    """
    height, width = field.shape
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    return ndimage.map_coordinates(field, [yy + wy, xx + wx], order=1, mode="reflect")


def render_space(brand, height, width, seed=11):
    """Deep starfield with a sweeping gold nebula and dark dust lanes.

    Args:
        brand: brand.env values.
        height: rows.
        width: columns.
        seed: random seed.

    Returns:
        float RGB image.
    """
    rng = np.random.default_rng(seed)
    s = width / WIDTH
    bg, glow = rgb(brand["BRAND_BG"]), rgb(brand["BRAND_BG_GLOW"])
    gold, light = rgb(brand["BRAND_ACCENT"]), rgb(brand["BRAND_ACCENT_LIGHT"])
    foil = [rgb(c) for c in brand["BRAND_FOIL_STOPS"].split()]
    ember = rgb("#4a2a0e")

    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    nx, ny = xx / width, yy / height
    image = mix(bg, glow, 1.0 - smoothstep(0.0, 0.9, np.hypot(nx - 0.55, (ny - 0.5) * 0.6)))

    wx = (fbm(rng, height, width, 1100 * s, 4) - 0.5) * 520 * s
    wy = (fbm(rng, height, width, 1100 * s, 4) - 0.5) * 520 * s
    gas = warp(fbm(rng, height, width, 800 * s, 7, gain=0.55), wx, wy)
    fine = warp(fbm(rng, height, width, 260 * s, 6, gain=0.6), wx * 0.6, wy * 0.6)
    dust = warp(fbm(rng, height, width, 500 * s, 6, gain=0.55), wx * 0.8, wy * 0.8)

    # The nebula follows a gentle diagonal arc so it reads as one structure
    # rather than uniform fog, and stays clear of the top and bottom bars.
    u = nx + wx / width * 0.6
    v = ny + wy / height * 0.6
    arc = 0.56 - 0.28 * (u - 0.5) + 0.25 * (u - 0.5) ** 2
    band = np.exp(-((v - arc) / 0.22) ** 2)
    core = np.exp(-(((u - 0.62) / 0.28) ** 2 + ((v - arc) / 0.12) ** 2))

    density = band * smoothstep(0.18, 0.80, gas) * (0.6 + 0.8 * fine)
    density = density * (0.6 + 0.6 * core)
    lanes = smoothstep(0.55, 0.80, dust) * band
    density *= 1.0 - 0.9 * lanes

    colour = mix(ember, gold, smoothstep(0.10, 0.55, density))
    colour = mix(colour, foil[1], 0.6 * smoothstep(0.7, 1.3, density))
    image += colour * (density * 1.0)[..., None]
    image += gold * glow_from(density * core, (80 * s,), (0.25,))[..., None]
    # A faint cool counter-tone in the outer haze adds depth to the gold.
    haze = fbm(rng, height, width, 1200 * s, 4)
    image += rgb("#141a2a") * (smoothstep(0.5, 1.0, haze) * (1 - band) * 0.3)[..., None]

    star_colours = [rgb("#ffffff"), rgb("#fff4e0"), rgb("#ffe3b8"), light, rgb("#dfe8ff")]
    stars = star_layer(rng, height, width, int(42000 * s * s), (0, 0), 3.2, star_colours) * 1.1
    stars += star_layer(rng, height, width, int(4000 * s * s), (0.7 * s, 1.0 * s), 2.4, star_colours) * 1.3
    # Stars are denser inside the band, as they are along a galaxy's plane.
    stars += star_layer(rng, height, width, int(30000 * s * s), (0, 0), 3.0, star_colours) * band[..., None] * 1.2
    bright = star_layer(rng, height, width, int(120 * s * s), (1.3 * s, 1.6 * s), 1.4, star_colours) * 1.8
    stars += bright + glow_from(bright, (7 * s, 26 * s), (1.6, 0.8))
    stars *= (1.0 - 0.8 * lanes)[..., None]
    image += stars

    image *= vignette(height, width, 0.5)[..., None]
    return calm_edges(image, 0.55, 0.5)


def render_earth(brand, height, width, seed=23):
    """A night-side planet from orbit, with dawn breaking along the limb.

    Args:
        brand: brand.env values.
        height: rows.
        width: columns.
        seed: random seed.

    Returns:
        float RGB image.
    """
    rng = np.random.default_rng(seed)
    s = width / WIDTH
    bg = rgb(brand["BRAND_BG"])
    gold, light = rgb(brand["BRAND_ACCENT"]), rgb(brand["BRAND_ACCENT_LIGHT"])
    foil = [rgb(c) for c in brand["BRAND_FOIL_STOPS"].split()]

    image = np.broadcast_to(bg, (height, width, 3)).astype(np.float32).copy()
    # Star counts scale with the image size, so they draw from their own
    # stream; otherwise a preview and the full render would get different
    # continents.
    star_rng = np.random.default_rng([seed, 1])
    star_colours = [rgb("#ffffff"), rgb("#fff4e0"), rgb("#dfe8ff")]
    image += star_layer(star_rng, height, width, int(14000 * s * s), (0, 0), 3.5, star_colours) * 0.9
    image += star_layer(star_rng, height, width, int(900 * s * s), (0.8 * s, 1.0 * s), 2.5, star_colours) * 1.1

    radius = 4200.0 * s
    cx, cy = 0.46 * width, 0.64 * height + radius
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    px, py = (xx - cx) / radius, (yy - cy) / radius
    r = np.sqrt(px * px + py * py)
    inside = r < 1.0
    pz = np.sqrt(np.clip(1.0 - r * r, 0.0, 1.0))

    # Tilting the globe towards the viewer puts mid-latitudes, not the pole,
    # along the visible limb.
    tilt = math.radians(62.0)
    gy = py * math.cos(tilt) - pz * math.sin(tilt)
    gz = py * math.sin(tilt) + pz * math.cos(tilt)
    lat = np.arcsin(np.clip(-gy, -1, 1))
    lon = np.arctan2(px, gz) + 0.8

    map_h, map_w = 2048, 4096
    land = fbm(rng, map_h, map_w, 520, 7, gain=0.52)
    land_mask = smoothstep(0.50, 0.55, land)
    # Lights cluster along coasts and in a few dense regions, like real
    # cities, joined by faint threads of road.
    coast = smoothstep(0.48, 0.52, land) * (1.0 - smoothstep(0.55, 0.62, land))
    population = fbm(rng, map_h, map_w, 220, 6, gain=0.6)
    weight = (smoothstep(0.45, 1.0, population) ** 3 + coast * 0.15) * land_mask
    weight = weight.ravel() / weight.sum()
    picks = rng.choice(map_h * map_w, size=260000, p=weight)
    lights_map = np.zeros(map_h * map_w, dtype=np.float32)
    np.add.at(lights_map, picks, rng.random(picks.size).astype(np.float32) ** 3 * 1.6)
    lights_map = lights_map.reshape(map_h, map_w)
    lights_map = ndimage.gaussian_filter(lights_map, 0.5)
    lights_map += ndimage.gaussian_filter(lights_map, 6.0) * 2.0

    mu = (lon / (2 * math.pi) % 1.0) * map_w
    mv = (0.5 - lat / math.pi) * map_h
    coords = [mv[inside], mu[inside]]
    land_px = np.zeros((height, width), dtype=np.float32)
    lights_px = np.zeros((height, width), dtype=np.float32)
    land_px[inside] = ndimage.map_coordinates(land_mask, coords, order=1, mode="wrap")
    lights_px[inside] = ndimage.map_coordinates(lights_map, coords, order=1, mode="wrap")

    # The sun sits just behind the planet, so only a thin crescent is lit
    # and it rises at a visible point on the limb.
    sun_x = 0.72 * width
    sun_dx = (sun_x - cx) / radius
    sun_2d = np.array([sun_dx, -math.sqrt(1 - sun_dx * sun_dx)], dtype=np.float32)
    sun = np.array([sun_2d[0] * 0.16, sun_2d[1] * 0.16, -1.0], dtype=np.float32)
    sun /= np.linalg.norm(sun)
    lit = px * sun[0] + py * sun[1] + pz * sun[2]
    night = 1.0 - smoothstep(-0.03, 0.01, lit)
    day = smoothstep(-0.01, 0.06, lit)

    ocean, ground = rgb("#05070a"), rgb("#0b0c0a")
    surface = mix(ocean, ground, land_px)
    # Foreshortening near the limb would crowd the lights into a bright
    # band, so they fade out at grazing angles.
    view = smoothstep(0.03, 0.30, pz)
    city = mix(rgb("#ffb04a"), foil[1], 0.3)
    surface += city * (lights_px * night * view)[..., None]
    surface = mix(surface, mix(rgb("#3a2e18"), light, 0.3) * (0.35 + 0.5 * land_px[..., None]), day * 0.85)
    surface *= (1.0 - 0.8 * smoothstep(0.82, 1.0, yy / height))[..., None]
    image[inside] = surface[inside]

    safe_r = np.maximum(r, 1e-6)
    facing = np.clip(((px / safe_r) * sun_2d[0] + (py / safe_r) * sun_2d[1] + 1.0) / 2.0, 0.0, 1.0)
    phase = 0.10 + 0.90 * facing ** 40
    altitude = (r - 1.0) * radius
    atmosphere = np.where(altitude > 0,
                          np.exp(-altitude / (12.0 * s)) + np.exp(-altitude / (60.0 * s)) * 0.35,
                          np.exp(np.minimum(altitude, 0) / (5.0 * s)) * 0.9)
    atmosphere *= phase
    air = mix(mix(rgb("#4a2e10"), gold, smoothstep(0.1, 0.5, phase)), foil[1], smoothstep(0.75, 1.0, phase))
    image += air * atmosphere[..., None]

    # The sun peeks over the limb: a hot point, a soft halo and a faint
    # horizontal streak like a camera flare.
    sx = cx + radius * sun_2d[0]
    sy = cy + radius * sun_2d[1] - 4 * s
    d = np.hypot(xx - sx, yy - sy)
    flare = np.exp(-d / (9 * s)) * 3.0 + np.exp(-d / (80 * s)) * 0.5 + np.exp(-d / (380 * s)) * 0.2
    streak = np.exp(-np.abs(yy - sy) / (2.5 * s)) * np.exp(-np.abs(xx - sx) / (700 * s)) * 0.5
    image += mix(light, rgb("#fffaf0"), 0.5) * (flare + streak)[..., None]

    image *= vignette(height, width, 0.45)[..., None]
    return calm_edges(image, 0.6, 0.5)


def treeline(rng, width, spacing, height_range, base):
    """Adds conifer silhouettes along a ridge profile.

    Args:
        rng: numpy Generator.
        width: number of columns.
        spacing: mean distance between trees in pixels.
        height_range: (min, max) tree height in pixels.
        base: ridge height per column, in pixels above the image bottom.

    Returns:
        new height profile including the trees.
    """
    profile = base.copy()
    xs = np.arange(width, dtype=np.float32)
    pos = -spacing
    while pos < width + spacing:
        pos += spacing * rng.uniform(0.35, 1.3)
        tall = rng.uniform(*height_range)
        half = tall * rng.uniform(0.13, 0.22)
        lo, hi = int(max(pos - half, 0)), int(min(pos + half + 1, width))
        if hi <= lo:
            continue
        edge = np.abs(xs[lo:hi] - pos) / half
        # Branch tiers: the outline steps in and out instead of a clean
        # triangle, which is what makes a silhouette read as a fir.
        tiers = 0.10 * np.abs(np.sin((1.0 - edge) * rng.uniform(9, 14))) * edge
        top = base[int(min(max(pos, 0), width - 1))] + tall * (1.0 - edge ** 0.9 - tiers)
        profile[lo:hi] = np.maximum(profile[lo:hi], top)
    return profile


def render_vale(brand, height, width, seed=37):
    """Layered forest ridges falling into a misty valley lit from behind.

    Args:
        brand: brand.env values.
        height: rows.
        width: columns.
        seed: random seed.

    Returns:
        float RGB image.
    """
    rng = np.random.default_rng(seed)
    s = width / WIDTH
    gold, light = rgb(brand["BRAND_ACCENT"]), rgb(brand["BRAND_ACCENT_LIGHT"])

    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    nx, ny = xx / width, yy / height
    sun_x, sun_y = 0.53, 0.47

    image = mix(rgb("#060807"), rgb("#2c2a1c"), smoothstep(0.0, 0.55, ny) ** 1.8)
    d_sun = np.hypot(nx - sun_x, (ny - sun_y) * 1.5)
    image += gold * (np.exp(-d_sun / 0.09) * 0.6 + np.exp(-d_sun / 0.30) * 0.25)[..., None]
    image += light * (np.exp(-d_sun / 0.018) * 0.7)[..., None]

    # Faint shafts of light: angular noise around the light source, blurred
    # so they read as haze rather than a cartoon sunburst.
    theta = np.arctan2(ny - sun_y, (nx - sun_x) * (width / height))
    ray_noise = fbm_1d(rng, 4096, 40, 5, 0.6)
    rays = ndimage.map_coordinates(ray_noise, [((theta + math.pi) / (2 * math.pi) * 4095).ravel()],
                                   order=1).reshape(height, width)
    rays = smoothstep(0.0, 0.7, rays) * np.exp(-d_sun / 0.35) * (1.0 - smoothstep(0.40, 0.55, ny))
    image += gold * (ndimage.gaussian_filter(rays, 14 * s) * 0.05)[..., None]

    xs = np.arange(width, dtype=np.float32) / width
    layers = 8
    mist = rgb("#8c7c58")
    far_green, near_green = rgb("#24342a"), rgb("#040605")
    fog_tex = 0.55 + 0.45 * fbm(rng, height, width, 700 * s, 4)
    for i in range(layers):
        depth = i / (layers - 1)
        # Each ridge is a V opening onto the light: steep, tall sides near
        # the viewer and gentle far ranges, so the vale deepens into the
        # picture.
        centre = 0.50 + 0.36 * depth ** 1.3
        sides = (0.05 + 0.42 * depth ** 1.5) * smoothstep(0.0, 0.5, np.abs(xs - sun_x)) ** 0.9
        noise = (0.025 + 0.05 * depth) * fbm_1d(rng, width, (1000 - 500 * depth) * s, 6, 0.5)
        ridge_y = centre - sides + noise
        base = (1.0 - ridge_y) * height
        if depth > 0.15:
            base_trees = treeline(rng, width, (5 + 14 * depth) * s,
                                  ((8 + 60 * depth) * s, (16 + 130 * depth) * s), base)
        else:
            base_trees = base
        top_y = (height - base_trees)[None, :]
        ridge_top = (height - ndimage.gaussian_filter1d(base, 40 * s))[None, :]

        haze = (1.0 - depth) ** 1.3
        colour = mix(near_green, far_green, 0.6 * (1.0 - depth))
        colour = mix(colour, mist, 0.75 * haze)
        near_sun = np.exp(-((xs - sun_x) / 0.22) ** 2)[None, :]
        below = yy - top_y
        layer = np.broadcast_to(colour, (height, width, 3)) + gold * (
            np.exp(-np.maximum(below, 0) / (2.5 * s)) * near_sun * 0.35 * (0.2 + 0.8 * depth))[..., None]
        # A little vertical shading gives each ridge some volume.
        layer = layer * (1.0 - 0.25 * smoothstep(0.0, 0.25 * height, below))[..., None]
        image = np.where((below >= 0)[..., None], layer, image)
        if i < layers - 1:
            # Mist pooled at the foot of each ridge, following the smoothed
            # ridge line rather than every tree, separates it from the next.
            fog = np.exp(-np.abs(yy - ridge_top - 0.06 * height) / (0.04 * height))
            fog *= (0.55 * (1.0 - depth) + 0.12) * fog_tex
            fog *= smoothstep(-0.02 * height, 0.02 * height, yy - top_y)
            fog_colour = mix(mist * 0.6, mist * 1.05, near_sun[..., None] * np.ones((height, 1, 1)))
            image = mix(image, fog_colour, np.clip(fog, 0.0, 0.85))
    image *= vignette(height, width, 0.5)[..., None]
    return calm_edges(image, 0.6, 0.6)


def contour_lines(field, interval, width_px, major_every):
    """Anti-aliased contour lines of a height field.

    Args:
        field: (H, W) heights.
        interval: height step between lines.
        width_px: line width in pixels.
        major_every: every n-th line is drawn brighter.

    Returns:
        (minor, major) line intensity images in 0..1.
    """
    level = field / interval
    gy, gx = np.gradient(level)
    raw_slope = np.hypot(gx, gy)
    slope = np.maximum(raw_slope, 1e-3)
    dist = np.abs(level - np.round(level)) / slope
    # On near-flat ground the distance estimate breaks down and a line
    # would smear into a filled patch, so those stretches are left blank.
    lines = np.clip(1.0 - (dist - width_px / 2.0), 0.0, 1.0) * smoothstep(0.004, 0.012, raw_slope)
    index = np.round(level).astype(np.int64)
    is_major = (index % major_every) == 0
    return lines * ~is_major, lines * is_major


def bundle_paths(rng, width, height, s, top_limit, bottom_limit):
    """Plans one bundle of parallel traces with 45° jogs.

    Args:
        rng: numpy Generator.
        width: columns.
        height: rows.
        s: size factor relative to 4K.
        top_limit: highest y a trace may use.
        bottom_limit: lowest y a trace may use.

    Returns:
        (paths, line_width, spacing): one list of (x, y) points per trace.
    """
    root2 = math.sqrt(2.0) - 1.0
    count = int(rng.integers(2, 9))
    spacing = rng.uniform(13, 19) * s
    span = count * spacing
    y0 = rng.uniform(top_limit, bottom_limit - span)
    x_start = rng.uniform(-0.25, 0.75) * width
    length = rng.uniform(0.18, 0.6) * width
    jogs, x, y = [], x_start, y0
    for _ in range(int(rng.integers(1, 4))):
        x += rng.uniform(0.06, 0.25) * width
        dy = float(rng.choice([-1, 1]) * rng.uniform(40, 260) * s)
        if not top_limit < y + dy < bottom_limit - span:
            dy = -dy
        if x > x_start + length or not top_limit < y + dy < bottom_limit - span:
            break
        jogs.append((x, dy))
        y += dy
        x += abs(dy)
    x_end = max(x_start + length, x + 0.04 * width)

    paths = []
    for i in range(count):
        y = y0 + i * spacing
        points = [(x_start - rng.uniform(0, 4) * spacing, y)]
        for jx, dy in jogs:
            # Parallel traces keep their spacing through a 45° turn only if
            # each one turns slightly later than the one inside the bend.
            order = i if dy < 0 else count - 1 - i
            corner = jx + order * spacing * root2
            points.append((corner, y))
            points.append((corner + abs(dy), y + dy))
            y += dy
        points.append((x_end - rng.uniform(0, 4) * spacing, y))
        paths.append(points)
    return paths, rng.uniform(2.4, 3.4) * s, spacing


def draw_traces(rng, width, height, supersample, s):
    """Lays out PCB-style trace bundles that never cross, then draws them.

    Each candidate bundle is rasterised onto a coarse occupancy map and
    rejected if it would touch one already placed, which is what keeps the
    picture reading as a real board instead of a tangle.

    Args:
        rng: numpy Generator.
        width: final columns.
        height: final rows.
        supersample: drawing scale factor for anti-aliasing.
        s: size factor relative to 4K.

    Returns:
        (traces, pads) float masks in 0..1 at final size.
    """
    coarse = 4
    occupied = np.zeros((height // coarse, width // coarse), dtype=bool)
    top_limit = height * (TOP_CALM + 0.07)
    bottom_limit = height * (1 - BOTTOM_CALM - 0.07)
    placed = []
    for _ in range(400):
        if len(placed) >= 22:
            break
        paths, line_w, spacing = bundle_paths(rng, width, height, s, top_limit, bottom_limit)
        probe = Image.new("1", occupied.shape[::-1], 0)
        pdraw = ImageDraw.Draw(probe)
        for points in paths:
            pdraw.line([(px / coarse, py / coarse) for px, py in points],
                       fill=1, width=int(spacing * 2.2 / coarse) + 1)
        mask = np.asarray(probe, dtype=bool)
        if (mask & occupied).any():
            continue
        occupied |= mask
        placed.append((paths, line_w))

    ss = supersample
    trace_img = Image.new("L", (width * ss, height * ss), 0)
    pad_img = Image.new("L", (width * ss, height * ss), 0)
    tdraw, pdraw = ImageDraw.Draw(trace_img), ImageDraw.Draw(pad_img)
    for paths, line_w in placed:
        r_out, r_in = line_w * 2.4 * ss, line_w * 1.1 * ss
        for points in paths:
            tdraw.line([(px * ss, py * ss) for px, py in points],
                       fill=255, width=max(int(line_w * ss), 1), joint="curve")
            for ex, ey in (points[0], points[-1]):
                ex, ey = ex * ss, ey * ss
                pdraw.ellipse((ex - r_out, ey - r_out, ex + r_out, ey + r_out), fill=255)
                pdraw.ellipse((ex - r_in, ey - r_in, ex + r_in, ey + r_in), fill=0)
    traces = np.asarray(trace_img.resize((width, height), Image.LANCZOS), dtype=np.float32) / 255.0
    pads = np.asarray(pad_img.resize((width, height), Image.LANCZOS), dtype=np.float32) / 255.0
    return np.clip(traces, 0, 1), np.clip(pads, 0, 1)


def render_circuit(brand, height, width, seed=53):
    """Gold circuit traces over a faint topographic map, on black.

    Args:
        brand: brand.env values.
        height: rows.
        width: columns.
        seed: random seed.

    Returns:
        float RGB image.
    """
    rng = np.random.default_rng(seed)
    s = width / WIDTH
    bg, glow = rgb(brand["BRAND_BG"]), rgb(brand["BRAND_BG_GLOW"])
    gold, light = rgb(brand["BRAND_ACCENT"]), rgb(brand["BRAND_ACCENT_LIGHT"])
    foil = [rgb(c) for c in brand["BRAND_FOIL_STOPS"].split()]

    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    nx, ny = xx / width, yy / height
    image = mix(glow, bg, smoothstep(0.0, 0.8, np.hypot(nx - 0.5, (ny - 0.5) * 0.6)))

    terrain = fbm(rng, height, width, 1300 * s, 6, gain=0.48)
    minor, major = contour_lines(terrain, 0.022, 1.1 * s, 5)
    topo_tint = mix(rgb("#4a3a1c"), gold, 0.4)
    image += topo_tint * (minor * 0.22 + major * 0.45)[..., None]

    traces, pads = draw_traces(rng, width, height, 3, s)
    # Brightness varies along the picture so the traces feel lit from one
    # side instead of flat.
    light_field = 0.45 + 0.75 * fbm(rng, height, width, 1500 * s, 3)
    sheen = mix(foil[4], foil[1], smoothstep(0.3, 1.0, light_field))
    metal = np.maximum(traces, pads)
    image = mix(image, sheen * light_field[..., None], metal * 0.92)
    bloom = glow_from(metal * light_field, (5 * s, 22 * s, 80 * s), (0.35, 0.22, 0.12))
    image += gold * bloom[..., None]
    image += light * (pads * 0.2)[..., None]

    image *= vignette(height, width, 0.6)[..., None]
    return calm_edges(image, 0.5, 0.45)


RENDERERS = {
    "space": render_space,
    "earth": render_earth,
    "vale": render_vale,
    "circuit": render_circuit,
}


def main(argv):
    """Renders the requested wallpapers.

    Args:
        argv: command-line arguments without the program name.

    Returns:
        process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--env", default="branding/brand.env")
    parser.add_argument("--out", default="files/system/usr/share/backgrounds/shatteredvales")
    parser.add_argument("--only", nargs="*", choices=sorted(RENDERERS))
    parser.add_argument("--scale", type=float, default=1.0)
    args = parser.parse_args(argv)

    brand = load_brand(args.env)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    width, height = int(WIDTH * args.scale), int(HEIGHT * args.scale)
    for index, name in enumerate(args.only or RENDERERS):
        image = RENDERERS[name](brand, height, width)
        save_jpeg(image, out / f"{name}.jpg", np.random.default_rng(1000 + index))
        print(f"Rendered {out / (name + '.jpg')}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
