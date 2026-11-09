#!/usr/bin/env python3
"""Generates every app icon from the SVG artwork defined below.

Run from the repo root (needs `rsvg-convert`, e.g. `brew install librsvg`):

    python3 tool/icon/generate_icons.py

Artwork is drawn on Android's 108x108 adaptive-icon grid. Everything in the
foreground stays inside the 66dp safe circle (radius 33 around 54,54) so no
launcher mask ever clips it.
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
RES = ROOT / 'android/app/src/main/res'
IOS = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
STORE = ROOT / 'store'

BACKGROUND = '''
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#38BDF8"/>
      <stop offset="0.45" stop-color="#0284C7"/>
      <stop offset="1" stop-color="#0C4A6E"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.38" r="0.5">
      <stop offset="0" stop-color="#BAE6FD" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#BAE6FD" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="108" height="108" fill="url(#bg)"/>
  <rect width="108" height="108" fill="url(#glow)"/>
'''

# Audio waveform rising out of the book's spine: (x offset, bar height).
BARS = [(-15.6, 7), (-10.4, 14), (-5.2, 10), (0, 21), (5.2, 13), (10.4, 17), (15.6, 8)]
BAR_BASE = 56


def _bars(fill):
    return ''.join(
        f'<rect x="{54 + dx - 1.7:.1f}" y="{BAR_BASE - h}" width="3.4" height="{h}" rx="1.7" fill="{fill}"/>'
        for dx, h in BARS)


LEFT_PAGE = 'M54,63 C47,58.5 39,57.5 32,59 L32,76 C39,74.8 47,75.8 54,80 Z'
RIGHT_PAGE = 'M54,63 C61,58.5 69,57.5 76,59 L76,76 C69,74.8 61,75.8 54,80 Z'
COVER = ('M54,65 C47,60.5 38,59.5 30,61 L30,78.5 C38,77.3 47,78.3 54,82.5 '
         'C61,78.3 70,77.3 78,78.5 L78,61 C70,59.5 61,60.5 54,65 Z')

FOREGROUND = f'''
  <defs>
    <linearGradient id="wave" gradientUnits="userSpaceOnUse" x1="0" y1="56" x2="0" y2="35">
      <stop offset="0" stop-color="#FB923C"/>
      <stop offset="1" stop-color="#FDE047"/>
    </linearGradient>
    <linearGradient id="page" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E0F2FE"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="1.6"/>
    </filter>
  </defs>
  <g transform="translate(0,-4)">
  <ellipse cx="54" cy="83" rx="23" ry="3" fill="#082F49" opacity="0.45" filter="url(#shadow)"/>
  <path d="{COVER}" fill="#F97316"/>
  <path d="{LEFT_PAGE}" fill="url(#page)"/>
  <path d="{RIGHT_PAGE}" fill="url(#page)"/>
  <path d="M54,63 L54,80" stroke="#7DD3FC" stroke-width="0.8"/>
  <g fill="none" stroke="#7DD3FC" stroke-width="1.1" stroke-linecap="round">
    <path d="M36,64 C41,63 45,63.4 50,65"/>
    <path d="M36,68 C41,67 45,67.4 50,69"/>
    <path d="M36,72 C40,71.2 43,71.4 46,72.4"/>
    <path d="M58,65 C63,63.4 67,63 72,64"/>
    <path d="M58,69 C63,67.4 67,67 72,68"/>
    <path d="M62,72.4 C65,71.4 68,71.2 72,72"/>
  </g>
  {_bars('url(#wave)')}
  </g>
'''

# Android 13+ themed icons: single-colour silhouette, the launcher tints it.
MONOCHROME = f'''
  <g transform="translate(0,-4)">
  <path d="{LEFT_PAGE}" fill="#FFF" transform="translate(-0.8,0)"/>
  <path d="{RIGHT_PAGE}" fill="#FFF" transform="translate(0.8,0)"/>
  {_bars('#FFF')}
  </g>
'''


def svg(body, view='0 0 108 108'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">{body}</svg>'


# The full icon crops the outer 18dp the launcher would mask anyway, so the
# artwork fills a square icon the way it fills an adaptive one.
FULL = svg(BACKGROUND + FOREGROUND, view='9 9 90 90')
LEGACY = svg(
    '<defs><clipPath id="r"><rect x="9" y="9" width="90" height="90" rx="20"/></clipPath></defs>'
    f'<g clip-path="url(#r)">{BACKGROUND}{FOREGROUND}</g>',
    view='9 9 90 90')


def render(svg_text, out, size):
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), '-o', str(out)],
                   input=svg_text.encode(), check=True)


DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

for name, scale in DENSITIES.items():
    d = RES / f'mipmap-{name}'
    render(LEGACY, d / 'ic_launcher.png', round(48 * scale))
    render(svg(BACKGROUND), d / 'ic_launcher_background.png', round(108 * scale))
    render(svg(FOREGROUND), d / 'ic_launcher_foreground.png', round(108 * scale))
    render(svg(MONOCHROME), d / 'ic_launcher_monochrome.png', round(108 * scale))

# iOS: square, opaque, no rounding (iOS applies its own mask).
for image in json.loads((IOS / 'Contents.json').read_text())['images']:
    points = float(image['size'].split('x')[0])
    scale = int(image['scale'].rstrip('x'))
    render(FULL, IOS / image['filename'], round(points * scale))

# Play Store listing icon (uploaded in the Console, not bundled).
render(FULL, STORE / 'play_store_icon_512.png', 512)
(STORE / 'icon_master.svg').write_text(FULL)
