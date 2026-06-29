#!/usr/bin/env python3
"""Generate the Signal Capsule macOS app icon for ClaudeMonitor.

The generator intentionally uses only Python's standard library plus macOS
system tools. Swift/CoreGraphics renders the source PNG, `sips` builds the
required resized PNGs, and `iconutil` packages the final `.icns`.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap


SIZE = 1024


SWIFT_SOURCE = r"""
import AppKit
import CoreGraphics
import Foundation

let size = 1024
let outputPath = CommandLine.arguments[1]
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fatalError("Unable to create bitmap context")
}

ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    return CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let bgTop = color(34, 41, 51)
let bgBottom = color(8, 14, 18)
let cyan = color(62, 212, 198)
let busy = color(255, 159, 46)
let attention = color(255, 77, 91)
let idle = color(53, 199, 107)
let white = color(255, 255, 255)

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawLinearGradient(in rect: CGRect, top: CGColor, bottom: CGColor) {
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.minY),
        end: CGPoint(x: rect.maxX, y: rect.maxY),
        options: []
    )
}

func drawRadialGlow(center: CGPoint, radius: CGFloat, base: CGColor, maxAlpha: CGFloat) {
    let components = base.components ?? [1, 1, 1, 1]
    let inner = CGColor(
        red: components[0],
        green: components[1],
        blue: components[2],
        alpha: maxAlpha
    )
    let outer = CGColor(
        red: components[0],
        green: components[1],
        blue: components[2],
        alpha: 0
    )
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [inner, outer] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
}

func strokeRoundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor, width: CGFloat) {
    ctx.saveGState()
    ctx.addPath(roundedPath(rect, radius))
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.strokePath()
    ctx.restoreGState()
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.addPath(roundedPath(rect, radius))
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawDot(center: CGPoint, radius: CGFloat, dotColor: CGColor) {
    drawRadialGlow(center: center, radius: 74, base: dotColor, maxAlpha: 0.38)

    let dotRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    ctx.saveGState()
    ctx.addEllipse(in: dotRect)
    ctx.setFillColor(dotColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: dotRect.insetBy(dx: 7, dy: 7))
    ctx.setStrokeColor(color(255, 255, 255, 0.28))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - 12, y: center.y - 18, width: 16, height: 16))
    ctx.setFillColor(color(255, 255, 255, 0.42))
    ctx.fillPath()
    ctx.restoreGState()
}

let baseRect = CGRect(x: 102, y: 102, width: 820, height: 820)
let basePath = roundedPath(baseRect, 200)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 28), blur: 34, color: color(0, 0, 0, 0.38))
ctx.addPath(basePath)
ctx.setFillColor(color(0, 0, 0, 0.35))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(basePath)
ctx.clip()
drawLinearGradient(in: baseRect, top: bgTop, bottom: bgBottom)
drawRadialGlow(center: CGPoint(x: 350, y: 310), radius: 360, base: cyan, maxAlpha: 0.16)
drawRadialGlow(center: CGPoint(x: 700, y: 710), radius: 300, base: attention, maxAlpha: 0.10)
ctx.restoreGState()

strokeRoundedRect(CGRect(x: 118, y: 118, width: 788, height: 788), radius: 186, color: color(255, 255, 255, 0.15), width: 3)
strokeRoundedRect(CGRect(x: 136, y: 136, width: 752, height: 752), radius: 170, color: color(62, 212, 198, 0.08), width: 2)

ctx.saveGState()
ctx.addArc(center: CGPoint(x: 512, y: 484), radius: 344, startAngle: 3.58, endAngle: 5.76, clockwise: false)
ctx.setStrokeColor(color(255, 255, 255, 0.16))
ctx.setLineWidth(5)
ctx.strokePath()
ctx.restoreGState()

let capsuleRect = CGRect(x: 238, y: 406, width: 548, height: 212)
let capsulePath = roundedPath(capsuleRect, 106)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 22, color: color(0, 0, 0, 0.50))
ctx.addPath(capsulePath)
ctx.setFillColor(color(0, 0, 0, 0.25))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(capsulePath)
ctx.clip()
drawLinearGradient(in: capsuleRect, top: color(36, 45, 55, 0.96), bottom: color(11, 16, 20, 0.96))
drawRadialGlow(center: CGPoint(x: 512, y: 512), radius: 270, base: cyan, maxAlpha: 0.13)
ctx.restoreGState()

strokeRoundedRect(capsuleRect, radius: 106, color: color(255, 255, 255, 0.19), width: 3)
strokeRoundedRect(CGRect(x: 252, y: 420, width: 520, height: 184), radius: 92, color: color(62, 212, 198, 0.17), width: 2)

ctx.saveGState()
ctx.addArc(center: CGPoint(x: 512, y: 528), radius: 218, startAngle: 3.44, endAngle: 5.97, clockwise: false)
ctx.setStrokeColor(color(255, 255, 255, 0.17))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

drawDot(center: CGPoint(x: 386, y: 512), radius: 40, dotColor: busy)
drawDot(center: CGPoint(x: 512, y: 512), radius: 40, dotColor: attention)
drawDot(center: CGPoint(x: 638, y: 512), radius: 40, dotColor: idle)

guard let cgImage = ctx.makeImage() else {
    fatalError("Unable to create CGImage")
}

let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}

try png.write(to: URL(fileURLWithPath: outputPath))
"""


def run_checked(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"{command[0]} failed: {detail}")
    return result


def create_source_png(output_path: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".swift", delete=False) as swift_file:
        swift_file.write(textwrap.dedent(SWIFT_SOURCE).strip() + "\n")
        swift_path = swift_file.name

    try:
        run_checked(["swift", swift_path, output_path])
    finally:
        os.unlink(swift_path)


def create_icns(source_png: str, output_path: str) -> None:
    """Build a .icns via the standard iconutil workflow."""

    icns_dir = os.path.dirname(output_path) or "."
    os.makedirs(icns_dir, exist_ok=True)

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

    iconset_path = output_path + ".iconset"
    if os.path.exists(iconset_path):
        shutil.rmtree(iconset_path)
    os.makedirs(iconset_path, exist_ok=True)

    try:
        for name, size in iconset_files.items():
            target = os.path.join(iconset_path, name)
            run_checked(["sips", "-z", str(size), str(size), source_png, "--out", target])

        run_checked(["iconutil", "-c", "icns", iconset_path, "-o", output_path])
    finally:
        shutil.rmtree(iconset_path, ignore_errors=True)

    print(
        f"icns written via iconutil: {output_path} "
        f"({os.path.getsize(output_path)} bytes)"
    )


def main() -> None:
    print("Generating ClaudeMonitor icon...")

    source_path = "/tmp/AppIcon_1024.png"
    create_source_png(source_path)

    preview_path = "/tmp/ClaudeMonitor_icon_preview.png"
    shutil.copyfile(source_path, preview_path)
    print(f"Preview saved: {preview_path}")

    icns_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "AppIcon.icns",
    )
    create_icns(source_path, icns_path)
    print("Done!")


if __name__ == "__main__":
    main()
