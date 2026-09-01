# Homeward UX Specification

Homeward behaves like a quiet system utility.

## Information architecture

- One menu-bar item is always the primary status surface.
- One management window contains Overview, Schedule, Work Apps, Closing, and
  General destinations.
- Setup is resumable and never enables enforcement before the final action.
- Automatic panels do not activate Homeward or steal focus.
- User-invoked panels become keyboard-operable key windows.

## Interaction rules

- Every surface has one obvious primary action.
- Changes that can immediately close apps state that consequence before save.
- Firm Close always exposes a visible 30-second countdown and Stop Force Quit.
- Hiding an armed Firm panel first stops force escalation.
- Opening Change Today Only from Firm also stops force escalation before
  choices appear.
- Homeward never opens a work application except when the user explicitly asks
  the optional preview to open its chosen harmless app.
- Drag-and-drop always has a Choose Application alternative.

## Visual language

- Native controls, system typography, semantic colors, SF Symbols, and system
  spacing.
- No custom theme, gamification, decorative progress, gradients, or
  punishment-oriented imagery.
- Motion is brief and informative and disappears under Reduce Motion.
- State never depends on color alone.

## Window behavior

- Onboarding and management windows are resizable.
- The menu remains compact; detailed recovery and settings move to the
  management window.
- Firm, blocked-launch, and notes panels remain within the visible display
  frame and keep a menu route when hidden.
- User-facing window placement and focus must be manually verified across
  Spaces, full-screen apps, and multiple displays before dogfood.
