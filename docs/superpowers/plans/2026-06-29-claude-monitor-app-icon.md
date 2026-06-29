# Claude Monitor App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current eye/heartbeat app icon with the approved Signal Capsule icon and keep the installed icon visually compact.

**Architecture:** Keep the existing Python/Pillow generation pipeline and existing `iconutil` packaging path. Replace only the icon drawing logic in `Resources/gen_icon.py`, then regenerate `Resources/AppIcon.icns` from the script output.

**Tech Stack:** Python 3, Pillow, NumPy, macOS `iconutil`, existing SwiftPM app bundle resources.

---

## File Structure

- Modify: `Resources/gen_icon.py`
  - Responsibility: Draw the 1024px Signal Capsule source image and package it into a correct macOS `.icns` file.
  - Keep: `create_icns()` and its iconset/iconutil workflow.
  - Replace: the old hexagon, eye, and heartbeat drawing with the Signal Capsule composition.
- Modify generated asset: `Resources/AppIcon.icns`
  - Responsibility: Bundled app icon consumed by `Makefile` during `make bundle`.
- No Swift source files change for this task.

## Design Constants

The implementation should use these concrete values:

- Canvas: `1024x1024`
- Safe visual mass: within approximately `760px` centered in the canvas
- Base squircle bounds: `(132, 132, 892, 892)`
- Base corner radius: `185`
- Capsule bounds: `(270, 420, 754, 604)`
- Capsule width: `484px`
- Capsule height: `184px`
- Status dot radius: `35px`
- Dot centers: `(404, 512)`, `(512, 512)`, `(620, 512)`
- Palette:
  - background top: `(34, 41, 51)`
  - background bottom: `(8, 14, 18)`
  - accent cyan: `(62, 212, 198)`
  - busy orange: `(255, 159, 46)`
  - attention red: `(255, 77, 91)`
  - idle green: `(53, 199, 107)`
  - highlight white: `(255, 255, 255)`

### Task 1: Replace Icon Drawing

**Files:**
- Modify: `Resources/gen_icon.py`

- [ ] **Step 1: Replace the old icon composition helpers**

Replace the current hexagon/eye/heartbeat-oriented helpers with helpers that draw a compact glass squircle, rounded rectangles, gradients, and soft glows.

Use this code shape in `Resources/gen_icon.py`:

```python
#!/usr/bin/env python3
"""Generate the Signal Capsule macOS app icon for ClaudeMonitor."""

import os
import subprocess
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CX = SIZE // 2
CY = SIZE // 2

BG_TOP = (34, 41, 51)
BG_BOTTOM = (8, 14, 18)
CYAN = (62, 212, 198)
BUSY = (255, 159, 46)
ATTENTION = (255, 77, 91)
IDLE = (53, 199, 107)
WHITE = (255, 255, 255)


def rounded_rect_mask(size, bounds, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(bounds, radius=radius, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(0.35))


def vertical_gradient(size, top, bottom):
    arr = np.zeros((size, size, 4), dtype=np.uint8)
    for y in range(size):
        t = y / (size - 1)
        arr[y, :, 0] = int(top[0] * (1 - t) + bottom[0] * t)
        arr[y, :, 1] = int(top[1] * (1 - t) + bottom[1] * t)
        arr[y, :, 2] = int(top[2] * (1 - t) + bottom[2] * t)
        arr[y, :, 3] = 255
    return Image.fromarray(arr, "RGBA")


def paste_masked(base, layer, mask):
    clipped = Image.new("RGBA", base.size, (0, 0, 0, 0))
    clipped.alpha_composite(layer)
    clipped.putalpha(mask)
    return Image.alpha_composite(base, clipped)


def add_radial_glow(base, center, radius, color, max_alpha):
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    cx, cy = center
    for r in range(radius, 0, -4):
        t = r / radius
        alpha = int(max_alpha * (1 - t) ** 2)
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(color[0], color[1], color[2], alpha),
        )
    return Image.alpha_composite(base, glow)
```

- [ ] **Step 2: Implement the Signal Capsule drawing**

Replace `create_icon()` with the approved composition. Keep the primary visual mass inside the safe area so the installed icon does not look oversized.

```python
def create_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    base_bounds = (132, 132, 892, 892)
    base_mask = rounded_rect_mask(SIZE, base_bounds, 185)

    base = vertical_gradient(SIZE, BG_TOP, BG_BOTTOM)
    base = add_radial_glow(base, (350, 310), 360, CYAN, 42)
    base = add_radial_glow(base, (700, 710), 300, ATTENTION, 26)

    base_detail = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    detail = ImageDraw.Draw(base_detail)
    detail.rounded_rectangle(
        (146, 146, 878, 878),
        radius=172,
        outline=(255, 255, 255, 38),
        width=3,
    )
    detail.rounded_rectangle(
        (162, 162, 862, 862),
        radius=158,
        outline=(62, 212, 198, 20),
        width=2,
    )
    detail.arc((178, 166, 846, 664), 205, 330, fill=(255, 255, 255, 42), width=5)
    base = Image.alpha_composite(base, base_detail)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(base_bounds, radius=185, fill=(0, 0, 0, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    shadow = shadow.transform(
        shadow.size,
        Image.AFFINE,
        (1, 0, 0, 0, 1, 28),
        resample=Image.BICUBIC,
    )
    img = Image.alpha_composite(img, shadow)
    img = paste_masked(img, base, base_mask)

    capsule_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cap_shadow_draw = ImageDraw.Draw(capsule_shadow)
    cap_shadow_draw.rounded_rectangle((270, 420, 754, 604), radius=92, fill=(0, 0, 0, 128))
    capsule_shadow = capsule_shadow.filter(ImageFilter.GaussianBlur(22))
    capsule_shadow = capsule_shadow.transform(
        capsule_shadow.size,
        Image.AFFINE,
        (1, 0, 0, 0, 1, 16),
        resample=Image.BICUBIC,
    )
    img = Image.alpha_composite(img, capsule_shadow)

    capsule = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cap_draw = ImageDraw.Draw(capsule)
    cap_draw.rounded_rectangle(
        (270, 420, 754, 604),
        radius=92,
        fill=(18, 24, 29, 236),
        outline=(255, 255, 255, 48),
        width=3,
    )
    cap_draw.rounded_rectangle(
        (282, 432, 742, 592),
        radius=80,
        outline=(62, 212, 198, 42),
        width=2,
    )
    cap_draw.arc((292, 434, 732, 600), 197, 342, fill=(255, 255, 255, 44), width=4)
    capsule = add_radial_glow(capsule, (512, 512), 270, CYAN, 34)
    img = Image.alpha_composite(img, capsule)

    for center, color, radius in [
        ((404, 512), BUSY, 35),
        ((512, 512), ATTENTION, 35),
        ((620, 512), IDLE, 35),
    ]:
        img = add_radial_glow(img, center, 72, color, 96)
        dot = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        dot_draw = ImageDraw.Draw(dot)
        cx, cy = center
        dot_draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            fill=(color[0], color[1], color[2], 255),
        )
        dot_draw.ellipse(
            [cx - radius + 7, cy - radius + 7, cx + radius - 7, cy + radius - 7],
            outline=(255, 255, 255, 70),
            width=2,
        )
        dot_draw.ellipse(
            [cx - 12, cy - 18, cx + 4, cy - 2],
            fill=(255, 255, 255, 105),
        )
        img = Image.alpha_composite(img, dot)

    final = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    final.alpha_composite(img)
    return final
```

- [ ] **Step 3: Keep the existing `.icns` packaging function**

Keep `create_icns()` using the current `iconutil -c icns` flow. If the file already contains the same function, leave it in place. The function must still create these iconset files:

```python
iconset_files = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}
```

- [ ] **Step 4: Run the icon generator**

Run:

```bash
python3 Resources/gen_icon.py
```

Expected:

```text
Generating ClaudeMonitor icon...
Preview saved: /tmp/ClaudeMonitor_icon_preview.png
icns written via iconutil: /Users/edy/my-space/claude-monitor/Resources/AppIcon.icns
Done!
```

- [ ] **Step 5: Commit the drawing update and generated icon**

Run:

```bash
git add Resources/gen_icon.py Resources/AppIcon.icns
git commit -m "design: refresh app icon"
```

Expected: commit includes only `Resources/gen_icon.py` and `Resources/AppIcon.icns`.

### Task 2: Verify Icon Sizes And Visual Padding

**Files:**
- Inspect generated: `/tmp/ClaudeMonitor_icon_preview.png`
- Inspect generated: `/tmp/AppIcon_1024.png`
- Inspect generated: `Resources/AppIcon.icns`

- [ ] **Step 1: Confirm generated files exist**

Run:

```bash
test -s Resources/AppIcon.icns
test -s /tmp/ClaudeMonitor_icon_preview.png
test -s /tmp/AppIcon_1024.png
file Resources/AppIcon.icns /tmp/AppIcon_1024.png
```

Expected:

```text
Resources/AppIcon.icns: Mac OS X icon
/tmp/AppIcon_1024.png: PNG image data, 1024 x 1024
```

- [ ] **Step 2: Export representative icon sizes**

Run:

```bash
mkdir -p /tmp/claude-monitor-icon-check
sips -z 512 512 /tmp/AppIcon_1024.png --out /tmp/claude-monitor-icon-check/icon-512.png
sips -z 128 128 /tmp/AppIcon_1024.png --out /tmp/claude-monitor-icon-check/icon-128.png
sips -z 64 64 /tmp/AppIcon_1024.png --out /tmp/claude-monitor-icon-check/icon-64.png
sips -z 32 32 /tmp/AppIcon_1024.png --out /tmp/claude-monitor-icon-check/icon-32.png
sips -z 16 16 /tmp/AppIcon_1024.png --out /tmp/claude-monitor-icon-check/icon-16.png
```

Expected: five PNG files exist in `/tmp/claude-monitor-icon-check`.

- [ ] **Step 3: Visually inspect the generated icon**

Open or inspect these files:

```text
/tmp/AppIcon_1024.png
/tmp/claude-monitor-icon-check/icon-128.png
/tmp/claude-monitor-icon-check/icon-64.png
/tmp/claude-monitor-icon-check/icon-32.png
```

Expected:

- The dark base has visible padding inside the 1024 canvas.
- The central capsule does not touch the base edges.
- The icon appears slightly compact, not oversized.
- The orange, red, and green status lights are readable at 64px.
- At 32px, the icon still reads as a dark status-monitor mark.

- [ ] **Step 4: Verify bundle picks up the icon**

Run:

```bash
make bundle
test -s _DIST/ClaudeMonitor.app/Contents/Resources/AppIcon.icns
cmp Resources/AppIcon.icns _DIST/ClaudeMonitor.app/Contents/Resources/AppIcon.icns
```

Expected:

```text
Icon bundled
App bundle created: _DIST/ClaudeMonitor.app
```

The `cmp` command should print no output.

- [ ] **Step 5: Commit verification notes only if files changed**

Run:

```bash
git status --short
```

Expected: no new source changes from verification except ignored build output. If no tracked files changed, do not create a commit.

## Self-Review

- Spec coverage: Task 1 implements the Signal Capsule direction, safe visual padding, Signal Glass colors, and no text/eye/heartbeat motifs. Task 2 checks `.icns` generation, representative small sizes, and bundling.
- Scope: The plan only changes `Resources/gen_icon.py` and the generated `Resources/AppIcon.icns`.
- Type consistency: All helper function names used by `create_icon()` are defined in Task 1.
