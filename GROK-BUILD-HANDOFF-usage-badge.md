# Grok Build handoff — usage control (updated)

## New preferred approach (Kevin)
Don’t scrape % forever. Move/reuse the **usage bolt** from Payments / General so a control sits **next to the profile name** at the bottom. Clicking it opens the **same Usage detail popup** Payments already shows.

## Still nice-to-have
Show total % on the control if easy; otherwise bolt alone + popup is enough.

## File / build
- `Sources/Services/GrokUsageBadge.swift` (or replace with clickable bolt + JS to open Usage modal)
- Debug: `xcodebuild -project GrokApp.xcodeproj -scheme Grok -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO`
- Relaunch once only

App (Grok Bot) will implement this on Mac; use this if you want to burn Grok Build usage in parallel.
