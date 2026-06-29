# Claude Monitor App Icon Design

## Decision

Use the **Signal Capsule** direction for the Claude Monitor app icon.

The icon should represent the product directly: a quiet macOS desktop monitor
for Claude Code sessions, shown as a compact glass capsule with status lights.

## Goals

- Match the existing Signal Glass visual system.
- Make the app recognizable as a session/status monitor, not a generic AI or
  terminal app.
- Keep the icon calm, compact, and native to macOS.
- Preserve legibility at Finder, Dock, Spotlight, and menu-sized contexts.
- Leave enough visual padding so the installed app icon does not look oversized
  beside other macOS app icons.

## Visual Concept

The icon uses a dark rounded-square macOS app icon base with a centered floating
capsule. Inside the capsule are three status lights:

- Busy: warm orange.
- Needs attention: red.
- Idle: green.

The icon does not use an eye, heartbeat trace, mascot, or large terminal prompt.
Those motifs either compete with the product's actual UI or make the app feel
more dramatic than the intended quiet desktop instrument.

## Composition

Canvas:

- Render source size: `1024x1024`.
- Final output: `Resources/AppIcon.icns` generated through the existing
  `iconutil` iconset workflow.

Safe area:

- Keep the primary visual mass inside roughly 72-76% of the canvas width.
- Leave approximately 12-15% padding on all sides.
- Avoid extending glow or shadow to the canvas edge.
- The installed icon should look slightly compact rather than oversized.

Base:

- Use a macOS-style rounded square or squircle.
- Use a deep charcoal glass gradient from lifted charcoal at the top-left to
  near-black at the bottom-right.
- Add a subtle inner highlight and restrained outer shadow.

Central mark:

- Use a horizontally centered pill-shaped glass capsule.
- Capsule width should be about 58-64% of the canvas width.
- Capsule height should be about 18-22% of the canvas height.
- Place the capsule slightly above optical center or exactly centered; do not
  place it low in the icon.
- Use a fine translucent border and soft cyan edge glow to connect it to the
  Signal Glass UI language.

Status lights:

- Show three circular lights in the capsule: orange, red, green.
- Each light should have a small glow, but the glow must not merge into one
  blurred strip at small sizes.
- Use equal spacing and make the red light the center emphasis.
- Do not add labels or text.

## Palette

Use the existing Signal Glass palette as the source of truth:

- Background top: lifted charcoal, close to `#222933`.
- Background bottom: near-black, close to `#0A1014`.
- Accent cyan: `#3ED4C6`.
- Busy orange: `#FF9F2E`.
- Attention red: `#FF4D5B`.
- Idle green: `#35C76B`.
- Border/highlight: translucent white, low opacity.

The icon should not become a one-color orange mark. Orange is only one status
light, not the dominant brand color.

## Small-Size Behavior

At 1024px and 512px:

- The glass base, capsule, and three lights should all be visible.
- The icon should feel polished, dimensional, and native to macOS.

At 128px and 64px:

- The capsule silhouette and three colored lights should remain readable.
- The outer glass details may simplify visually.

At 32px and 16px:

- The three lights may compress, but the icon should still read as a dark
  monitor/status mark.
- Avoid thin details that become noise.

## Implementation Scope

Update only the icon generation path:

- `Resources/gen_icon.py`
- Generated `Resources/AppIcon.icns`

The app UI, settings UI, monitoring behavior, hooks, and tests are out of scope
for this icon change.

## Verification

After implementation:

- Regenerate the icon with `Resources/gen_icon.py`.
- Confirm `Resources/AppIcon.icns` exists and contains all required macOS icon
  sizes.
- Export or inspect representative sizes: 1024, 512, 128, 64, 32, and 16.
- Compare the generated icon beside common macOS icons or in Finder/Dock to
  confirm it does not look oversized.
- Confirm the icon still matches the Signal Glass app UI direction.
