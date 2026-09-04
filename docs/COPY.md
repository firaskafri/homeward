# Homeward Threshold Copy

This is the approved language contract. Strings under **Required copy** are
target requirements, not a claim that they are implemented. Current
implementation status is tracked in `TRACEABILITY.md`.

## Voice

Use calm, literal, nonjudgmental language. Say what Homeward did, what happens
next, and what the user can do. Prefer **available**, **closed**, **paused**,
and **needs attention** over access-control or punishment metaphors.

Do not use:

- access denied, blocked by policy, forbidden, violation, failed discipline
- distraction, productivity score, streak, compliance, or shame language
- claims that Homeward prevents an app from starting or protects access
- unnecessary exclamation marks
- selected-app names or thought text in default notifications

Use an ellipsis only when an action opens choices or a confirmation. Use
sentence case. Use “today” or “tomorrow” only when calendar-correct; otherwise
show a localized weekday/date and time. Use locale-aware list and plural
formatting rather than string concatenation.

Placeholders in braces are descriptive and must not appear literally.

## Required copy

### State titles and transitions

| Purpose | Copy |
| --- | --- |
| Startup | **Starting Homeward…** |
| Delayed startup | **This is taking longer than expected. App closing has not started.** |
| Available | **Work available** |
| Wind-down | **Winding down** |
| Active closing | **Closing work apps** |
| Closed | **Work is closed** |
| Temporary availability | **Work extended** |
| Configuration recovery | **App closing is paused** |
| Force pause | **Force quit is paused** |
| Force failure | **Force quit did not close {app}.** |
| Next availability | **Available {localized date and time}** |
| Current window end | **Until {localized date and time}** |
| Override expiry | **Weekly schedule resumes {localized date and time}** |
| Continuous availability | **Work apps are always available** |
| No future window | **No work window scheduled** |

When multiple states apply, use the precedence in `UX-SPEC.md`. Recovery copy
must never be combined with **Work available** or other schedule-derived copy.

### Primary and secondary actions

- **End Work Now…**
- **Change Today Only…**
- **Show App**
- **Leave Open This Time**
- **Stop Force Quit**
- **Stop All Force Quits**
- **Stop Force Quit and Hide**
- **Resume Firm Closing…**
- **Make All Work Apps Available for 10 Minutes…**
- **Return to Weekly Schedule**
- **Save a Thought…**
- **Review Saved Thoughts ({count})…**
- **Open Homeward**
- **Settings…**
- **Homeward Needs Attention…**
- **Start Homeward**
- **Start & Close Work Apps…**
- **Choose Application…**
- **Reselect…**
- **Run Preview…**
- **Skip Preview**
- **End Preview**

### Consequence and confirmation copy

**End work now?**

> Homeward will begin {Gentle Close/Firm Close} for selected work apps.

**Save and close work apps now?**

> This change makes the current time unavailable. Homeward will begin
> {Gentle Close/Firm Close} after the change is saved.

**Enable Firm Close?**

> Firm Close can discard unsaved changes or interrupt active processes.
> Homeward first requests a normal quit and gives each app a full 30-second
> grace period.

**Resume Firm Closing?**

> Homeward will ask selected apps to quit normally and begin a new 30-second
> grace period.

**Quit Homeward?**

> Pending force quits will be cancelled. Apps already asked to quit may still
> close. Selected apps will not be monitored until Homeward is reopened.

**Reset Homeward setup?**

> This clears the schedule, selected apps, closing preferences, and today-only
> changes. Saved thoughts and Start at Login remain.

**Delete all saved thoughts?**

> This permanently deletes every saved thought. This cannot be undone.

**Delete this thought?**

> This permanently deletes the selected thought. This cannot be undone.

### Closing and app repair

| Condition | Copy |
| --- | --- |
| Gentle request | **Waiting for the app to quit normally** |
| Gentle attention | **{app} needs your attention before it can quit.** |
| Firm countdown | **{app} will be force quit in {count} seconds. Unsaved changes can be lost.** |
| Force pause detail | **Work apps are still unavailable. Resume starts a new 30-second grace period.** |
| Force failure detail | **{app} remains open. Homeward will not retry force quit in the background.** |
| Unresolved selection | **Needs reselection** |
| Unresolved explanation | **Homeward will leave this app open until you reselect or remove it.** |
| Zero apps | **Choose at least one work app. Homeward has nothing to close.** |
| Browser scope | **Homeward manages the whole browser, including every profile and window. Use a separate browser for personal browsing.** |
| System application | **Homeward cannot manage that system application. Choose another application.** |
| Unsupported item | **The selected item is not a supported application.** |

### Preview

**Preview is optional**

> Preview requests normal quits only. If the app accepts the request, unsaved
> work may close. Homeward never launches the app.

| Preview state | Copy |
| --- | --- |
| Idle | **Choose a harmless selected app, open it, then run the preview.** |
| First exit | **Waiting for {app} to close normally.** |
| Relaunch | **Reopen {app}. Homeward will detect and close it automatically.** |
| Second exit | **Homeward detected the relaunch and is waiting for {app} to close.** |
| Needs attention | **{app} needs your attention before the preview can continue.** |
| Timeout | **Preview timed out. Check {app}, try again, or skip preview.** |
| Complete | **Preview complete. Homeward closed both launches normally.** |
| Cancel consequence | **Ending preview prevents later preview steps. A normal quit the app already accepted cannot be undone.** |

### Saved Thoughts

| Condition | Copy |
| --- | --- |
| Capture title | **Save a thought for later** |
| Closed privacy | **Existing thoughts stay hidden while work is closed.** |
| Empty editor reason | **Enter a thought to save.** |
| Saving | **Saving…** |
| Saved | **Thought saved. It will stay private until you review it.** |
| Automatic availability | **Saved thoughts are ready** |
| Automatic detail | **You have {count} saved {thought/thoughts}. Open Saved Thoughts to review them.** |
| No notes | **No saved thoughts** |
| Kept for interval | **No thoughts to review in this work window** |
| Kept confirmation | **This thought will return in a later work window.** |
| Completed | **Thought marked done** |
| Notes unavailable | **Saved thoughts are unavailable. App closing still works.** |
| Save failure | **The thought was not saved. Your draft is still here.** |

Automatic and notification copy must never substitute `{thought text}`. A
count is allowed. Thought text appears only after the user deliberately opens
Saved Thoughts while the session is active.

### Recovery, readiness, and persistence

| Condition | Copy |
| --- | --- |
| Configuration recovery | **Homeward could not verify its saved settings, so it will not close any applications.** |
| Restore unavailable | **No previous settings are available.** |
| Configuration load retry failed | **App closing is paused because settings could not be verified.** |
| Save in progress | **Saving…** |
| Save succeeded | **Changes saved** |
| Policy save failed | **Changes could not be saved. No new app-closing policy was applied.** |
| Notifications off | **Wind-down notifications are off. App closing still works.** |
| Start at Login off | **Start at Login is off. Homeward works only while it is open.** |
| Login approval | **Start at Login needs approval in System Settings.** |

Errors must name the failed operation, preserve the valid state, and avoid
generic blame such as “Something went wrong.”

## Privacy-safe notifications

Default notification content is intentionally generic.

### Fifteen-minute warning

- Title: **Workday ends in 15 minutes**
- Body: **Finish your current thought. Work apps will close at {localized
  time}.**

### Five-minute warning

- Title: **5 minutes remaining**
- Body: **Work apps will close at {localized time}.**

### Blocked launch

- Title: **A work app was closed**
- Body: **{Next availability sentence}**

### Closing complete

- Title: **Work is closed**
- Body: **Selected apps are unavailable until {localized date and time}.**
- No-future-window body: **No work window is scheduled.**

### Saved Thoughts

- Title: **Saved thoughts are ready**
- Body: **Open Homeward to review {count} saved {thought/thoughts}.**

No notification contains an app name, bundle identifier, file path, developer
name, process count tied to a named app, thought text, or draft text by
default. An optional detailed-notification preference, if implemented later,
must be explicit, off by default, and explain lock-screen exposure.
