# Grok Build / grokbot link — usage bolt

Repo: https://github.com/kmk2k6/xai-grok-macos (Kevin’s fork). Do **not** PR to bcharleson.
Do not mix this with Pand0ra.

## Fixed on main
- Bolt stays on the profile **name row**, vertically centered, to the right of the name.
- Pointer down is swallowed so the profile menu does not also open.
- One click hard-loads the **current** page with `?_s=usage`.
  Grok's settings store reads `_s` only when it is constructed. A soft URL
  change, or walking Account → Payments → Usage, is the old multi-menu.
- If Usage is already open, the total % in that dialog is cached on the bolt.

## File
`Sources/Services/GrokUsageBadge.swift`

## Build (once, on the Mini)
```bash
xcodebuild -project GrokApp.xcodeproj -scheme Grok -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```
Relaunch `/Applications/Grok.app` once. No Chrome loops. No `build.sh`.

## Success
Bolt beside the name → one click → Settings Usage sheet, chat still behind it.
