# Homeward Privacy

Homeward is local-only and requires no account or network connection for core
operation.

## Stored locally

- Weekly work windows.
- Today-only changes and expiry.
- Selected application identifiers, paths, names, and availability metadata.
- Closing and warning preferences.
- Plain-text saved thoughts and timestamps.

Files are stored under the current user’s Application Support directory with
owner-only permissions. Homeward relies on macOS and FileVault for at-rest
device protection; it does not add application-level note encryption.

## Never collected

- Screen contents.
- Document contents or names.
- Window titles.
- Browser history or URLs.
- Terminal commands.
- AI conversations.
- Employee or team activity.

Homeward has no remote analytics. It creates no app-managed diagnostic log by
default. Minimal lifecycle/error codes may appear in macOS unified logging,
without note text, paths, URLs, commands, window titles, or app identity.

Notification and Start-at-Login authorization are queried from macOS and are
not treated as authoritative persisted settings.
