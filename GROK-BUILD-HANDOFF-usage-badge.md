# Grok Build / grokbot link — usage bolt

Repo: https://github.com/kmk2k6/xai-grok-macos (Kevin’s fork). Do **not** PR to bcharleson.

## Done (pushed 2026-10-02)
- Bolt sits on the same row as the profile name (inline to the right), not under it. Pointer events on the bolt no longer open the profile menu.
- One click calls grok.com’s settings store the same way Payments / the in-app “View usage” buttons do: `setTab("usage")` then `setOpen(true)`, found by walking the live React fiber tree. It does **not** navigate to `/?_s=usage` unless that store cannot be found.
- Fallback deep link keeps the current path and only sets `_s=usage` (no forced reload to `/`).
- If the Usage dialog text includes a total/weekly percent, it is cached on the bolt.
- Kevin confirmed the Usage sheet opened on the first click (2026-10-02).

## File
`Sources/Services/GrokUsageBadge.swift`

## Build (once)
```bash
xcodebuild -project GrokApp.xcodeproj -scheme Grok -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```
App that is actually running: `build/Build/Products/Debug/Grok.app`.
`/Applications/Grok.app` is a separate copy (not a symlink to Debug).
