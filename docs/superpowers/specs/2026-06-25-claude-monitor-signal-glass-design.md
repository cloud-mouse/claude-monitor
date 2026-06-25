# Claude Monitor Signal Glass Redesign

## Decision

Use option A, **Signal Glass**, as the redesign direction for Claude Monitor.

The app should feel like a quiet macOS desktop instrument: compact, polished,
always available, and visually calm until a session needs attention.

Reference mockup:

- `designs/ui-redesign-options.html`

## Goals

- Keep the existing floating capsule behavior and small desktop footprint.
- Make the capsule feel more refined: deeper glass, better spacing, clearer status
  lamps, and less cramped text.
- Use attention color and pulse only when the user needs to act.
- Give the settings window the same visual language: restrained surfaces, cleaner
  sections, and less default SwiftUI feel.
- Preserve the current feature set: multi-session display, context menu actions,
  notifications, hooks, settings, and position memory.

## Visual System

### Palette

- Base capsule: near-black glass, around `#111419` with translucency.
- Secondary surface: slightly lifted charcoal, around `#222933`.
- Accent cyan: `#3ED4C6` for selected/active chrome.
- Busy: warm orange `#FF9F2E`.
- Needs attention: clear red `#FF4D5B`.
- Idle: green `#35C76B`.
- Offline: muted gray `#9CA3AF`.

### Typography

- Use native San Francisco through SwiftUI system fonts.
- Session names should be semibold, compact, and readable at small sizes.
- Utility labels in settings should be smaller and calmer than the primary
  session labels.

### Shape And Depth

- Main capsule remains pill-shaped.
- Individual session pills sit inside the shared glass shell.
- Use subtle borders and inner highlights instead of heavy outlines.
- Radius should be high for the floating capsule and moderate for settings
  controls.

## Floating Capsule

The redesigned capsule should contain:

- A dark translucent outer shell.
- One pill per active session.
- A small status dot at the start of each session pill.
- Optional active styling for the highest-priority session.
- Horizontal scrolling only when sessions exceed available width.

Status priority remains:

1. Needs attention
2. Busy
3. Idle
4. Offline

Behavior:

- Needs attention pulses.
- Busy, idle, and offline stay steady.
- Hover should slightly lift or brighten a pill, not resize the whole layout.
- Click and context menu behavior remain unchanged.

## Settings Window

The settings window should be reskinned, not functionally redesigned in this
pass.

Expected changes:

- Cleaner section grouping.
- Softer dark-on-light surface treatment matching Signal Glass.
- Better spacing and smaller utility text.
- Toggles and channel chips should use the same accent/status palette.
- Webhook and script editors should remain practical and readable.

Out of scope:

- New settings features.
- Major settings navigation changes.
- Replacing the notification model.

## Implementation Scope

Primary SwiftUI/AppKit files:

- `Sources/ClaudeMonitor/CapsuleView.swift`
- `Sources/ClaudeMonitor/FloatingPanel.swift`
- `Sources/ClaudeMonitor/SettingsView.swift`

Likely implementation steps:

1. Extract local design constants for colors, spacing, and capsule materials.
2. Rebuild `SessionPill` styling around the Signal Glass visual system.
3. Adjust `MiniScrollBar` and scroll states to match the new capsule.
4. Tune `FloatingPanel` sizing, shadow, and visual effect material.
5. Reskin settings sections and channel chips without changing persisted settings.

## Testing And Verification

Run:

- `swift test`
- `swift build`

Manual visual checks:

- No sessions.
- One idle session.
- One needs-attention session.
- Multiple mixed-status sessions.
- Horizontal overflow with many sessions.
- Settings window at minimum size.
- Light and dark desktop backgrounds if practical.

The implementation should be compared against option A in
`designs/ui-redesign-options.html`, with priority on capsule proportion, glass
depth, state-dot clarity, spacing, and restrained settings styling.
