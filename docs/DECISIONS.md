# Homeward Decisions

## Product

- Working name: Homeward.
- Platform: macOS 15+ on Apple Silicon.
- Process architecture: one menu-bar application process; no helper/XPC
  service in the MVP.
- Distribution: direct download; Mac App Store deferred.
- Update mechanism: manual download and replacement.

## Scheduling

- Monday–Friday, 09:00–17:00 is the onboarding suggestion.
- Supported day modes: Scheduled hours, Available all day, Blocked all day.
- Scheduled hours may end the same day or next day.
- Rules follow the Mac’s current wall clock and time zone.
- Contradictory overnight-to-blocked-day rules are rejected.

## Closing

- Gentle Close is the default and never force-terminates.
- Firm Close gives every launch a complete 30-second grace after normal quit.
- No action shortens that grace.
- Stop Force Quit pauses force for all selected apps for the current blocked
  interval without granting availability.
- Force is paused while the user session is inactive or countdown UI is not
  visible.
- Fifteen- and five-minute warnings begin enabled; the five-minute warning can
  be disabled.
- The one-time Gentle extension begins disabled.
- When used, it makes all selected work apps available for ten minutes.

## Data and privacy

- Bundle identifier: `com.firaskafri.homeward`.
- Configuration and notes use versioned Codable files in Application Support.
- `UserDefaults` is reserved for presentation preferences.
- Notes are plain text, limited to 500 characters, and have no archive.
- No app-managed diagnostic log; minimal redacted unified logging only.

## Delivery

- The dedicated repository is `firaskafri/homeward`.
- GitHub Releases will be the versioned source after dogfood.
- The personal site will receive a checksum-verified release input without
  committing the DMG to source control.
- Development-signed local build is the unattended-run boundary while
  Developer ID credentials are unavailable.
