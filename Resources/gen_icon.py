#!/usr/bin/env python3
"""Generate a beautiful macOS app icon for ClaudeMonitor."""

import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CX, CY = SIZE // 2, SIZE // 2


def rounded_rect_mask(size, radius):
    """Create a rounded rectangle mask (macOS squircle-ish)."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    # Use superellipse for macOS-like squircle
    img = np.zeros((size, size), dtype=np.float64)
    r = radius
    cx, cy = size / 2, size / 2
    for y in range(size):
        for x in range(size):
            dx = abs(x - cx)
            dy = abs(y - cy)
            # Approximate squircle
            dist = (dx / r) ** 4 + (dy / r) ** 4
            if dist <= 1.0:
                img[y, x] = 1.0
            elif dist <= 1.05:
                img[y, x] = max(0, 1.0 - (dist - 1.0) / 0.05)

    # Smooth the edge
    mask_arr = (img * 255).astype(np.uint8)
    mask = Image.fromarray(mask_arr, 'L')
    return mask


def draw_gradient_bg(draw, size):
    """Draw a dark gradient background."""
    for y in range(size):
        t = y / size
        # Dark blue-gray gradient
        r = int(30 + 15 * t)
        g = int(28 + 12 * t)
        b = int(40 + 20 * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b))


def draw_hexagon(draw, cx, cy, radius, fill=None, outline=None, width=1):
    """Draw a regular hexagon."""
    points = []
    for i in range(6):
        angle = math.pi / 6 + i * math.pi / 3
        x = cx + radius * math.cos(angle)
        y = cy + radius * math.sin(angle)
        points.append((x, y))
    points.append(points[0])
    if fill:
        draw.polygon(points, fill=fill)
    if outline:
        draw.line(points, fill=outline, width=width)


def create_icon():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Background gradient
    draw_gradient_bg(draw, SIZE)

    # 2. Subtle radial glow in center
    glow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    for r in range(400, 0, -1):
        t = r / 400
        alpha = int(40 * (1 - t) ** 2)
        color = (232, 130, 60, alpha)
        glow_draw.ellipse([CX - r, CY - r, CX + r, CY + r], fill=color)
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # 3. Outer hexagon glow (multiple layers for bloom effect)
    glow_hex = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glow_hex_draw = ImageDraw.Draw(glow_hex)
    hex_radius = 280
    for i in range(20, 0, -1):
        alpha = int(8 * (20 - i))
        r_offset = i * 3
        draw_hexagon(glow_hex_draw, CX, CY, hex_radius + r_offset,
                     fill=(232, 113, 58, min(alpha, 60)))
    img = Image.alpha_composite(img, glow_hex)
    draw = ImageDraw.Draw(img)

    # 4. Main hexagon with gradient fill
    hex_img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    hex_draw = ImageDraw.Draw(hex_img)

    # Draw filled hexagon
    points = []
    for i in range(6):
        angle = math.pi / 6 + i * math.pi / 3
        x = CX + hex_radius * math.cos(angle)
        y = CY + hex_radius * math.sin(angle)
        points.append((x, y))
    points.append(points[0])
    hex_draw.polygon(points, fill=(200, 95, 45))

    # Gradient overlay on hexagon
    hex_gradient = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    hg_draw = ImageDraw.Draw(hex_gradient)
    for y_off in range(-300, 300):
        t = (y_off + 300) / 600
        r = int(255 - 70 * t)
        g = int(150 - 60 * t)
        b = int(70 - 30 * t)
        alpha = 120
        hg_draw.line([(CX - 350, CY + y_off), (CX + 350, CY + y_off)],
                     fill=(r, g, b, alpha))

    hex_img = Image.alpha_composite(hex_img, hex_gradient)

    # Clip hex_gradient to hexagon shape
    hex_mask = Image.new('L', (SIZE, SIZE), 0)
    hex_mask_draw = ImageDraw.Draw(hex_mask)
    hex_mask_draw.polygon(points, fill=255)
    hex_img.putalpha(ImageChops_multiply(hex_img.getchannel('A'), hex_mask)
                     if hex_img.mode == 'RGBA' else hex_mask)

    img = Image.alpha_composite(img, hex_img)
    draw = ImageDraw.Draw(img)

    # 5. Hexagon border (bright)
    draw_hexagon(draw, CX, CY, hex_radius, outline=(255, 180, 100), width=4)
    # Inner border highlight
    draw_hexagon(draw, CX, CY, hex_radius - 8, outline=(255, 200, 130, 60), width=2)

    # 6. Center "eye" / monitor symbol
    # Draw a stylized eye shape
    eye_w = 120  # half-width
    eye_h = 60   # half-height at center
    eye_cy = CY + 10

    # Eye outline path
    eye_points_upper = []
    eye_points_lower = []
    for i in range(101):
        t = i / 100
        x = CX - eye_w + t * 2 * eye_w
        # Upper lid - smooth curve
        y_up = eye_cy - eye_h * math.sin(t * math.pi) * 1.0
        # Lower lid
        y_low = eye_cy + eye_h * math.sin(t * math.pi) * 0.8
        eye_points_upper.append((x, y_up))
        eye_points_lower.append((x, y_low))

    eye_path = eye_points_upper + list(reversed(eye_points_lower))
    draw.polygon(eye_path, fill=(240, 200, 160))

    # Iris circle
    iris_r = 38
    draw.ellipse([CX - iris_r, eye_cy - iris_r, CX + iris_r, eye_cy + iris_r],
                 fill=(60, 35, 20))

    # Pupil
    pupil_r = 18
    draw.ellipse([CX - pupil_r, eye_cy - pupil_r, CX + pupil_r, eye_cy + pupil_r],
                 fill=(20, 10, 5))

    # Highlight in eye
    hl_r = 8
    draw.ellipse([CX + 8, eye_cy - 18, CX + 8 + hl_r * 2, eye_cy - 18 + hl_r * 2],
                 fill=(255, 255, 255, 200))

    # 7. Pulse/heartbeat line across the hexagon
    pulse_y = CY + 130
    pulse_points = []
    for i in range(80):
        x = CX - 160 + i * 4
        if i < 25:
            y = pulse_y
        elif i < 30:
            y = pulse_y - (i - 25) * 8
        elif i < 35:
            y = pulse_y + (i - 30) * 12
        elif i < 40:
            y = pulse_y - (40 - i) * 8
        elif i < 50:
            y = pulse_y
        elif i < 55:
            y = pulse_y - (i - 50) * 4
        elif i < 60:
            y = pulse_y + (i - 55) * 6
        elif i < 65:
            y = pulse_y - (65 - i) * 4
        else:
            y = pulse_y
        pulse_points.append((x, y))

    for i in range(len(pulse_points) - 1):
        draw.line([pulse_points[i], pulse_points[i + 1]],
                  fill=(255, 220, 180), width=3)

    # Small dots at pulse peaks
    dot_positions = [pulse_points[28], pulse_points[55]]
    for dp in dot_positions:
        draw.ellipse([dp[0] - 5, dp[1] - 5, dp[0] + 5, dp[1] + 5],
                     fill=(255, 220, 180))

    # 8. Apply squircle mask
    mask = rounded_rect_mask(SIZE, 440)
    # Round corners
    img.putalpha(ImageChops_multiply(img.getchannel('A'), mask))

    return img


def ImageChops_multiply(a, b):
    """Multiply two images channel-wise."""
    a_arr = np.array(a).astype(np.float64)
    b_arr = np.array(b).astype(np.float64)
    result = (a_arr * b_arr / 255).clip(0, 255).astype(np.uint8)
    return Image.fromarray(result, mode='L')


def create_icns(img, output_path):
    """Create .icns file with required icon sizes."""
    import os
    import struct

    icns_dir = os.path.dirname(output_path) or '.'
    os.makedirs(icns_dir, exist_ok=True)

    # macOS icns format requires specific size entries
    # ic04: 16x16, ic07: 128x128, ic08: 256x256, ic09: 512x512, ic10: 512x512@2x=1024
    # Also: ic11 (32@2x), ic12 (64@2x), ic13 (256@2x), ic14 (512@2x)
    sizes = {
        'ic07': 128,
        'ic08': 256,
        'ic09': 512,
        'ic10': 1024,  # 512@2x
        'ic11': 64,    # 32@2x
        'ic12': 128,   # 64@2x
        'ic13': 512,   # 256@2x
        'ic14': 1024,  # 512@2x
    }

    # Also legacy PNG sizes
    png_sizes = {
        'icp4': 16,
        'icp5': 32,
        'icp6': 64,
        'ic07': 128,
    }

    import io

    def to_png(image):
        buf = io.BytesIO()
        image.save(buf, format='PNG')
        return buf.getvalue()

    data = b''
    # magic header
    all_entries = {}

    for tag, sz in sizes.items():
        resized = img.resize((sz, sz), Image.LANCZOS)
        all_entries[tag] = to_png(resized)

    for tag, sz in png_sizes.items():
        if tag not in all_entries:
            resized = img.resize((sz, sz), Image.LANCZOS)
            all_entries[tag] = to_png(resized)

    for tag, png_data in all_entries.items():
        entry_len = 8 + len(png_data)
        data += tag.encode('ascii')
        data += struct.pack('>I', entry_len)
        data += png_data

    # Write icns file
    total_len = 8 + len(data)
    header = b'icns' + struct.pack('>I', total_len)

    with open(output_path, 'wb') as f:
        f.write(header)
        f.write(data)

    print(f"✅ icns written: {output_path} ({total_len} bytes)")


def main():
    print("Generating ClaudeMonitor icon...")
    img = create_icon()

    # Save preview PNG
    preview_path = '/tmp/ClaudeMonitor_icon_preview.png'
    img.save(preview_path)
    print(f"✅ Preview saved: {preview_path}")

    # Create .icns
    icns_path = '/tmp/ClaudeMonitor.icns'
    create_icns(img, icns_path)

    # Also save the 1024x1024 PNG for reference
    img.save('/tmp/AppIcon_1024.png')
    print("Done!")


if __name__ == '__main__':
    main()
