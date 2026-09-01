# Homeward Accessibility

Target: native macOS behavior plus WCAG 2.2 Level A/AA where applicable.

## Interaction contract

- Every function is keyboard-operable.
- Dragging an application always has a Choose Application alternative.
- Visible labels are the start of Voice Control names.
- State is represented by text and symbols, never color alone.
- Automatic panels do not activate Homeward or take focus from a save dialog.
- User-invoked panels become key and restore focus on dismissal.
- Firm countdowns announce 30, 15, and 5 seconds, not every tick.
- Stop Force Quit remains available throughout every active Firm countdown.
- Reduce Motion removes nonessential custom movement.
- Reduce Transparency uses opaque semantic backgrounds.
- Text reflows instead of shrinking or clipping.

## Automated coverage

- Stable identifiers cover the onboarding root, app rows, schedule controls,
  note controls, closing rows, and critical actions.
- UI automation verifies the pre-activation menu-bar item.
- Unit tests verify the deterministic state and safety rules that drive
  accessible copy.

## Manual release gate

Complete onboarding, menu, settings, Gentle/Firm closing, blocked launch,
today-only changes, and notes using:

- VoiceOver
- Full Keyboard Access
- Voice Control
- Zoom at 200% and 400%
- Light and dark appearance
- Increase Contrast
- Differentiate Without Color
- Reduce Motion
- Reduce Transparency

No unresolved keyboard, focus, label, announcement, contrast, clipping, or
timing barrier may remain before dogfood approval.
