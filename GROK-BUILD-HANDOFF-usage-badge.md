# Grok Build / grokbot link — remaining work

Repo: https://github.com/kmk2k6/xai-grok-macos (Kevin’s fork). Do **not** PR to bcharleson.

## Done already (local + on fork `4beed53`)
- True-black chrome (#000), glass Appearance sliders (Pand0ra-style)
- App icon (official Grok iOS art)
- Sparkle auto-check off in Debug
- Usage bolt next to sidebar profile (WIP)

## Still needed
1. **One-click Usage sheet** — Bolt must open full Settings → Usage detail in **one** click (`/?_s=usage` was tried; Kevin says still same as old % / still feels like multi-menu). Find the real deep link or DOM action that Payments uses for Usage and wire the bolt to that only.
2. **Align bolt** — Sit **inline to the right of “Kevin Knight”** (same row, vertically centered). Currently looks under the name / off.
3. Optional: cache/display **total** usage % (~49%) on the bolt after Usage opens once — not chat-only.

## File
`Sources/Services/GrokUsageBadge.swift`

## Build (once)
```bash
xcodebuild -project GrokApp.xcodeproj -scheme Grok -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```
Relaunch `/Applications/Grok.app` **once**. No Chrome automation loops. No `build.sh`.

## Success
Bolt beside name → one click → Usage detail sheet with total %.
