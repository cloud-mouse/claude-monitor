# Signal Glass Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved Signal Glass visual direction to Claude Monitor's floating capsule and settings window.

**Architecture:** Keep existing app behavior and state models intact. Limit changes to SwiftUI/AppKit presentation in `CapsuleView.swift`, `FloatingPanel.swift`, and `SettingsView.swift`, with no changes to notification or hook persistence logic.

**Tech Stack:** SwiftPM, SwiftUI, AppKit `NSPanel`, native macOS materials and system fonts.

---

### Task 1: Signal Glass Capsule

**Files:**
- Modify: `Sources/ClaudeMonitor/CapsuleView.swift`

- [x] Add local Signal Glass color and layout constants.
- [x] Restyle `DisplayStatus.color` to use the approved palette.
- [x] Restyle empty state, session pill background, status dot, hover, and blinking behavior.
- [x] Keep sorting, click, context menu, and scroll behavior unchanged.

### Task 2: Floating Panel Shell

**Files:**
- Modify: `Sources/ClaudeMonitor/FloatingPanel.swift`

- [x] Tune `NSVisualEffectView` material, corner radius, shadow, and target size.
- [x] Preserve drag, snap, position memory, all-spaces behavior, and non-activating panel behavior.

### Task 3: Signal Glass Settings Skin

**Files:**
- Modify: `Sources/ClaudeMonitor/SettingsView.swift`

- [x] Add shared settings styling helpers.
- [x] Restyle sections, headers, channel chips, text editors, inputs, and test buttons.
- [x] Preserve all existing settings bindings and persisted data structure.

### Task 4: Verification

**Files:**
- No source changes expected.

- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `swift build -c release`.
- [x] Inspect the diff for accidental functional changes.
