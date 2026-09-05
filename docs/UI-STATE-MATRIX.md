# Homeward Threshold UI State Matrix

This matrix is normative. Current implementation status is tracked in
`TRACEABILITY.md`.

Focus modes:

- **Passive:** do not activate Homeward or move focus.
- **Invoked:** make the user-requested surface key and focus its heading, error
  summary, or first meaningful control.
- **Safety:** Homeward may activate to expose Firm safety controls; focus Stop
  Force Quit and restore the prior app/control on dismissal.

All changing statuses must be available as text, not color alone. Dates, times,
counts, and app lists use locale-aware system formatting. Version 0.1.0 UI copy
is English-only; localization is deferred. VoiceOver announcements do not move
keyboard focus.

## Lifecycle and schedule

| State | Required presentation and rule | Actions and consequence | Focus and announcement | Notification and privacy | Recovery |
| --- | --- | --- | --- | --- | --- |
| Starting | **Starting Homeward…** No schedule state is asserted while configuration is loading. | None; Quit remains available from the app menu when practical. | Passive progress indicator. Announce once if the window is already open. | None. | Continue to setup, normal state, or configuration recovery. |
| Delayed startup | After a defined delay, retain **Starting Homeward…** and add **This is taking longer than expected. App closing has not started.** | **Retry** restarts bootstrap once; **Quit Homeward…** uses normal quit consequences. | Invoked only if startup window is visible. Announce delayed status once. | None. | Retry or quit; never infer availability from the initial schedule. |
| Onboarding | Show step number, purpose, saved progress, and a live summary. Closing remains off until completion. | **Back**, **Continue**, and final **Start Homeward** or **Start & Close Work Apps…**. Continue is disabled with an adjacent reason when the current requirement is incomplete. | Invoked window. On step change, focus the new heading; announce validation near its field. | None until permission is explicitly requested. | Preserve completed steps and drafts where safe; route invalid persisted setup to the affected step. |
| Work available | **Work available** and **Until {date, time}** or **Work apps are always available**. Weekly rule governs unless an override is shown. | Primary: **End Work Now…**. Secondary: Change Today Only, review thoughts when eligible. End Work confirms immediate configured closing. | Passive in menu; invoked on Today. Announce only on transition while Homeward is foregrounded. | No status notification by default. | If next transition cannot be resolved, show **No work window scheduled** and route to Schedule. |
| Winding down | **Winding down** and exact cutoff. This is the available period inside the largest enabled warning offset. | Primary: **End Work Now…**. Secondary: Change Today Only. | No focus change. One transition announcement at most. | Generic warning only; no app names. Actions must be generation-bound. | If scheduling a notification fails, closing continues and Today shows a dismissible attention item. |
| Work closed | **Work is closed** and **Available {date, time}** or **No work window scheduled**. | Primary: **Save a Thought…**. Secondary: Change Today Only. | No activation for schedule transition. | Generic completion/blocked-launch status only; no app names or thought text. | Schedule repair when no future window exists; unresolved apps remain fail-open. |
| Work extended | **Work extended** and **Weekly schedule resumes {date, time}**. Show the governing today-only override. | Primary depends on context; **Return to Weekly Schedule** ends the override and may immediately start closing, so confirm when applicable. | No automatic focus change. Announce when a foreground action successfully creates the extension. | Replace stale warnings; no detailed content by default. | Failed save retains the prior schedule and the edit affordance. |
| No future window | **Work is closed** and **No work window scheduled**. Explain the governing all-blocked rules. | Primary: **Edit Schedule…**. Secondary: Change Today Only. | Invoked route to Schedule; focus weekly schedule heading. | Generic only. | Edit schedule or create a bounded today-only availability override. |

## Closing and process events

| State | Required presentation and rule | Actions and consequence | Focus and announcement | Notification and privacy | Recovery |
| --- | --- | --- | --- | --- | --- |
| Actively closing | **Closing work apps** with total process count and one row per process or an explicitly aggregated app group. The schedule or override remains visible. | **Show Closing Details…**. Each row states whether an action affects one process or all selected apps. | Do not move focus for routine progress. Announce entry once, not each row update. | No process/app names in notifications by default. | Rows disappear when the exact process exits. Reconcile missing/out-of-order events. |
| Gentle normal quit | Row: **Waiting for the app to quit normally**. No force is permitted. | After attention delay: **Show App** and **Leave Open This Time**. Leave Open exempts only this process session. | Initially passive. Show App explicitly activates the target app. | Blocked-launch feedback remains generic outside the app. | If the app exits, remove the row. If it remains, show needs-attention state. |
| Gentle needs attention | **{App} needs your attention before it can quit.** | **Show App** activates that app; **Leave Open This Time** stops closing that process session only. | Panel remains passive unless user invokes details. No repeated announcement loop. | Generic status only. | A later launch remains eligible for closing. |
| Firm countdown | **{App} will be force quit in {n} seconds. Unsaved changes can be lost.** A full 30 seconds applies to each process session. | Primary: **Stop Force Quit** or **Stop All Force Quits**. Secondary: **Change Today Only…**. Hide/Escape/red close first stop force escalation. | Safety mode; initial focus on Stop, never on the ticking value. Announce 30, 15, and 5 seconds once each. Restore prior app/control on dismissal. | No countdown notification; safety is in-app and reachable from menu. | Session inactivity or hidden/occluded safety UI moves to Force paused. |
| Force paused | **Force quit is paused. Work apps are still unavailable.** Identify the blocked interval scope. | Primary: **Resume Firm Closing…**; confirmation states that normal quit is requested again and a new 30-second grace begins. Change Today Only remains available. | Invoked confirmation; no automatic activation. Announce pause once if caused by session/visibility change while foregrounded. | Remove stale closing actions. Generic status if a notification is necessary. | Resume safely, change availability, switch to Gentle, or wait for the blocked interval to end. |
| Force failed | **Force quit did not close {App}.** Explain that the app remains open and Homeward will not retry invisibly. | Primary: **Show App**. Secondary: Change Today Only or switch mode in Closing. | Keep panel available; announce failure once with high priority. Do not move focus from an active control. | Generic failure notice only if panel cannot be presented. | User handles the app, changes policy, or waits. Reconciliation may clear the row only when that exact process exits. |
| Blocked launch closed | **A work app was closed** plus next availability; inside an explicitly opened detail view the app name may be shown. | **Save a Thought…**; optional Gentle extension affects all selected apps and names that scope. **Close** dismisses only feedback. | Automatic panel is passive. User-invoked details are Invoked. | Generic title/body by default; aggregate repeats during cooldown. | Work Apps repair if identity is wrong; Change Today Only if the user wants availability. |
| Multiple instances | Show each process separately or **{App}: {count} instances**. Never imply one action affects only one instance when it affects all. | Show App targets one identified process; global Stop affects every active Firm countdown. | Preserve focus as rows reorder or disappear. | Aggregate without names by default. | Reconcile PID/session identity; never transfer a deadline to a relaunched process. |

## Setup, readiness, and system attention

| State | Required presentation and rule | Actions and consequence | Focus and announcement | Notification and privacy | Recovery |
| --- | --- | --- | --- | --- | --- |
| Zero selected apps | **Choose at least one work app. Homeward has nothing to close.** Blocks onboarding completion; after setup, marks Homeward Needs Attention. | Primary: **Choose Application…**. Drag-and-drop is secondary. | Focus the chooser when routed from attention. Announce blocker when Continue/Start is unavailable. | None. | Add one resolvable app that Homeward is allowed to manage. |
| Unresolved app | **Needs reselection. Homeward will leave this app open until repaired.** It is excluded from normal and force closing. | **Reselect…** validates replacement; **Remove** stops future management. Blocked-time repair confirms immediate consequences before applying. | No automatic activation. Invoked repair returns focus to the repaired row. | Generic Needs Attention only; do not name the app on the lock screen. | Reselect or remove. Other resolvable selections continue normally. |
| System/unsupported app | Explain that Homeward cannot manage the chosen item. The saved selection is unchanged. | **Choose Another Application…** or dismiss. | Return focus to Choose Application and associate the error. | None. | Pick a supported `.app` that Homeward is allowed to manage. |
| Catalog loading | **Looking for applications…** while selected apps remain visible and actionable. | **Choose Application…** remains available. Search waits or filters loaded results. | Do not steal focus from search/selected rows. | None. | Load results; on failure show recoverable catalog error, not an empty result. |
| Catalog empty/no matches | Distinguish **No applications found** from **No matching applications**. | **Choose Application…**. Clearing search restores results. | Focus remains in search unless the user invokes chooser. | None. | Direct chooser or clear search. |
| Notifications not determined | **Notifications not requested. Wind-down alerts are optional; app closing still works.** | **Enable Notifications** opens the system prompt. | Invoked only. Return focus to status after the prompt. | Do not schedule until authorized. | Recheck status and explain denial path. |
| Notifications denied/unavailable | **Notifications are off/unavailable. App closing still works.** | **Open System Settings** and **Check Again**. | Invoked; restore Homeward route when returning if possible. | None. | Enable in System Settings or continue without notifications. |
| Start at Login off | **Start at Login is off. Homeward works only while it is open.** | **Enable**. | Invoked only. | None. | Enable or continue knowingly. |
| Start at Login approval/location issue | Show **Approval required**, **Move to Applications**, or **Restart required** according to the verified state. Confirm success with **On** and “Homeward starts automatically when you log in.” | **Open Login Items** with **Check Again** for approval; **Show in Finder** with **Check Again** before a move; **Show in Finder** with **Quit Homeward** after moving the running app. | Refresh when Homeward becomes active and when readiness first appears. | None. | Approve in System Settings, or move the app and reopen that installed copy before enabling. |

## Preview

| State | Required presentation and rule | Actions and consequence | Focus and announcement | Notification and privacy | Recovery |
| --- | --- | --- | --- | --- | --- |
| Preview offered | **Preview is optional. It requests normal quits only.** Warn that an accepted normal quit can close unsaved work. | **Run Preview…**, **Skip Preview**, and **Start Homeward**. Skip is explicit and preview remains available later. | Invoked; focus Run Preview when opened, never auto-start. | None. | Skip or choose a harmless selected app. |
| Preview idle | Choose one resolvable selected app and instruct the user to open it first. | **Run Preview**; **End Preview**. | Focus app picker, then Run Preview. | None. | Missing/unresolved app returns to selection with an error. |
| Waiting for first exit | **Waiting for {App} to close normally.** | **End Preview** cancels later preview handling but cannot undo an accepted quit. | Do not move focus; announce stage change once. | None. | After 60 seconds, Needs attention. |
| Waiting for relaunch | **Reopen {App}. Homeward will detect and close it automatically.** | **End Preview**. | Do not activate or launch the app. | None. | After 60 seconds, Needs attention. |
| Waiting for second exit | **Homeward detected the relaunch and is waiting for {App} to close.** | **End Preview**. | Announce stage change once. | None. | After 60 seconds, Needs attention. |
| Preview needs attention | Explain whether the app is still open, missing, or timed out. | **Show App** only when that exact process still runs; **Try Again** starts a fresh preview; **End Preview**. | Invoked action may activate the selected app. | None. | Retry, select another app, or skip. |
| Preview complete | **Preview complete. Homeward closed both launches normally.** | **Done**; preview remains optional for onboarding completion. | Announce completion once; focus Done. | None. | Return to Ready. |

## Saved Thoughts

| State | Required presentation and rule | Actions and consequence | Focus and announcement | Notification and privacy | Recovery |
| --- | --- | --- | --- | --- | --- |
| Capture empty/disabled | Editor is empty; Save is disabled with **Enter a thought to save.** Character limit is 500. | **Cancel** preserves nothing; **Save** unavailable. | Invoked; focus editor. Disabled reason is programmatically associated. | Never expose draft content outside the panel. | Enter text or cancel. |
| Capture editing | Show remaining characters and local-storage privacy context. Existing thoughts remain concealed while closed. | **Save** / `⌘Return`; **Cancel**. | Keep focus in editor. Announce character-limit error once, not each keystroke. | No draft notifications. | Trim surrounding whitespace on validation guidance without silently changing intent. |
| Saving thought | **Saving…** at the Save control; prevent duplicate submission and preserve draft. | Cancel is disabled only if cancelling could create ambiguity. | Do not move focus. | None. | Success closes; failure keeps editor and draft. |
| Thought saved | **Thought saved. It will stay private until you review it.** | **Done** or return to prior surface. | Polite announcement; restore prior focus. | No content. | Available later from Saved Thoughts. |
| Thoughts ready | Generic **Saved thoughts are ready** with count; content stays concealed until deliberate review. Only during a normal base work window. | **Review Saved Thoughts…**; **Later** defers without marking individual notes presented. | Automatic in-app presentation is Passive; explicit Review is Invoked. | No Saved Thoughts system notification in version 0.1.0. Never include note text in any future notification. Suppress all content while session is locked/inactive. | Menu and persistent Saved Thoughts destination retain access. |
| Review empty | Distinguish **No saved thoughts**, **Kept for this work window**, and **Saved thoughts unavailable**. | Done, retry, or capture as context permits. | Invoked; focus heading. | None. | Follow state-specific action. |
| Thought kept | Explain that the thought will return in a later eligible work window. | **Undo Keep** or Done. | Keep focus in the row or announce its removal from this interval. | No content outside review. | Reappears after interval changes. |
| Thought completed | Explain removal and provide a user-controlled restore path. | **Restore** remains available until the review is dismissed or completion is explicitly confirmed. | Focus Restore/confirmation; announce completion. | No content outside review. | Restore the same note identity and order. |
| Thought deletion | Confirm **Delete this thought? This cannot be undone.** | **Delete**, **Cancel**. | Invoked confirmation; return focus to row on Cancel. | No notification. | No restoration after confirmed delete. |
| Notes unavailable | **Saved thoughts are unavailable. App closing still works.** Do not render stale or partial content. | **Retry**, optional **Restore Previous Thoughts…** only with a validated candidate, **Reset Saved Thoughts…**. | Invoked if user opens Saved Thoughts; otherwise a polite attention announcement. | Generic only. | Notes-only recovery; never reset configuration. |

## Configuration, save, and validation

| State | Required presentation and rule | Actions and consequence | Focus and announcement | Notification and privacy | Recovery |
| --- | --- | --- | --- | --- | --- |
| Configuration unavailable | **App closing is paused. Homeward could not verify its saved settings, so it will not close any applications.** No schedule-derived status is shown. | **Retry**, **Restore Previous Settings…**, **Reset Setup…**. Reset preserves thoughts. | Invoked recovery window; focus heading, then Retry. Announce once at high priority. | No schedule warning/status notifications; remove stale pending actions. | Successful retry/restore resumes bootstrap. Failed actions remain on recovery with scoped error. |
| Draft modified | Mark Schedule or other editable policy as **Unsaved changes**. Saved policy continues governing Homeward. | **Save**, **Reset Draft**; closing the view confirms discard when needed. | Keep focus at edit location. | None until save succeeds. | Restore saved values or save validated draft. |
| Validation error | Plain-language error associated with the invalid control; no policy change. | Correct value; Retry Save only when valid. | Focus first invalid control or an error summary that links to it. Announce once. | None. | Preserve draft. |
| Policy saving | **Saving…** and duplicate actions disabled. The previously saved policy remains authoritative until success. | No duplicate Save. Unrelated navigation follows native conventions but must not imply success. | Do not move focus. | Do not replace warnings until commit succeeds. | Success reconciles; failure restores displayed saved policy while preserving a recoverable draft. |
| Policy saved | **Changes saved** near the initiating action. Reconciliation may start closing only after any required confirmation. | Contextual next action. | Polite announcement. | Replace warnings with generic generation-bound requests. | None. |
| Policy save failed | **Changes could not be saved. No new app-closing policy was applied.** | **Try Again**, edit, or dismiss. | Focus error summary/failed action; high-priority announcement only when consequence is safety-relevant. | Existing valid notifications remain unless now stale. | Preserve previous verified policy and recoverable draft. |

## Required variants and evidence

Every applicable row requires:

- Light and dark appearance
- Increase Contrast and Differentiate Without Color
- Reduce Motion and Reduce Transparency
- Largest supported macOS text settings and representative long English copy;
  pseudo-localization is deferred with localization
- Keyboard, Full Keyboard Access, VoiceOver, Voice Control, and Switch Control
- Zoom at 200% and 400%
- Single and multiple displays, Spaces, and full-screen apps
- Hidden, crowded, and notched menu-bar conditions
- Long app names, duplicate names, missing icons, multiple instances, and no
  future schedule window

Automated coverage may prove deterministic state selection, copy, action
availability, process identity, and focus identifiers. Manual evidence is
still required for assistive technologies, notification presentation,
save-dialog focus, display placement, and real third-party application
behavior.

### Version 0.1.0 automated evidence

- **Passed by deterministic unit/native tests:** startup mutation gating and
  delayed Retry handoff; configuration/notes recovery isolation; stale and
  current notification-action routing; Saved Thoughts session concealment and
  completion Restore; Firm Stop persistence ordering and presentation
  precedence; outside-Applications Start at Login gating.
- **Passed by isolated UI scenarios:** first launch, completed-setup reopen,
  delayed-startup safety copy and Retry, configuration recovery without
  schedule state, notes-only recovery while runtime remains available,
  outside-Applications guidance, moved-app restart guidance, Start-at-Login
  approval and enabled states, and Work Apps reachability with a representative
  long application name.
- **NOT RUN / manual blockers:** VoiceOver, Voice Control, Switch Control, Full
  Keyboard Access, real notification authorization/actions, real login-item
  approval, lock/sleep/Fast User Switching, Spaces, multiple displays,
  save-dialog focus, third-party applications, compact resizing and largest
  text settings, other long-copy surfaces, clean-machine
  signing/notarization/Gatekeeper, and dogfood.
