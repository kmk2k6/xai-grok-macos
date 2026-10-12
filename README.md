<div align="center">

# Grok for Mac

<img src="logo/grok-logo-png.png" alt="Grok for Mac" width="128" height="128">

### The Native macOS Client for xAI's Grok

**A free, open-source, lightning-fast native Mac app for chatting with Grok AI**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-black.svg?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![Xcode 15+](https://img.shields.io/badge/Xcode-15+-147EFB.svg?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)

[Download](#-installation) · [Features](#-features) · [Getting Started](#-getting-started) · [Build from Source](#-build-from-source) · [Contributing](#-contributing)

---

**🎬 [Watch the Video Tutorial](#)** *(Coming Soon)*

</div>

---

## 🚀 What is Grok for Mac?

**Grok for Mac** is a native macOS application that gives you direct access to xAI's powerful Grok AI models right from your desktop. No browser needed — just pure, fast, native performance.

Unlike web-based alternatives, this app is built entirely in **Swift and SwiftUI**, optimized specifically for macOS. It's lightweight (~15MB), blazing fast, and integrates seamlessly with your Mac workflow.

> **⚠️ Note:** This is an unofficial, community-built app. [Grok](https://grok.x.ai) is a product of [xAI](https://x.ai). You'll need your own [xAI API key](https://console.x.ai) to use this app.

---

## ✨ Features

### ⚡ Quick Ask
Summon a prompt from any app:
- **Option-Space** opens a floating panel. Enter starts a new [grok.com](https://grok.com) chat and brings Grok forward. Esc closes the panel.
- The shortcut is configurable in Settings.
- **Prefill from selection** stays off until you enable it. When it is on, Quick Ask copies the frontmost selection, then restores the clipboard.
- The Services menu and a Finder Quick Action, **Ask Grok about this**, send selected text or files into a new chat.
- **Control-Option-4** captures a screen region and attaches the image to a new chat.
- File → **Quick Query** (⌘Space) is a separate input window.

### 💬 grok.com tabs and page tools
- **⌘T** opens a new grok.com tab. **⌘W** closes a tab, and hides the window when it is the last one. **⌘1–9** switch tabs.
- **⌘F** finds text in the page. **⌘=**, **⌘-**, and **⌘0** zoom in, out, and back to actual size. Zoom is remembered per mode.
- **⌘⇧F** is focus mode: chrome hides and the page sits in a narrow centered column. Full screen is **⌘⌃F**.
- **⌘⇧P** opens the prompt library. The library imports and exports as JSON.
- **Export Chat…** saves the open page's text as Markdown or PDF.
- **Mini Chat** floats a small always-on-top grok.com window on the same website data store.
- Relaunch restores the last mode, the last allowed URL, and the autosaved window frame.

### 📊 Menu bar usage
The bolt in the menu bar shows the usage percent reported by the page, recent grok.com chats, New Chat, Quick Ask, and Grok Bot. Every 15 minutes, and whenever Grok becomes active, a hidden offscreen page opens Settings → Usage with the same login as the main window, reads the weekly percent, saves it, and closes. That refresh does not change the page on screen, and it waits while the Mac is asleep or offline.
- A weekly sparkline says whether you are on pace or ahead of an even weekly pace. Samples stay on this Mac for 14 days.
- The pace warning is off until you enable it in Settings. It fires at most once a week, and only when usage is more than 15 points ahead of even pacing.
- An optional Dock badge shows the same percent.
- Quiet hours (default 22:00–07:00) and macOS Focus hold those usage alerts.

### 🔄 Modes

| Mode | Opens |
|------|--------|
| **Grok** | grok.com |
| **Chat** | chat.x.com |
| **Build** | Local Grok Build agent, including the terminal pane |
| **Grokipedia** | grokipedia.com |
| **𝕏** | x.com |
| **Console** | console.x.ai, from Build |
| **Grok Bot** | The separate Grok Bot app, beside the mode switcher |

### 🤖 Grok Bot
- **Grok Bot** in the mode bar, File → Grok Bot, **⌘⇧B**, and the command palette launch the Grok Bot app in `/Applications`, or bring it forward if it is already running.
- If that app is not installed, Grok shows “Grok Bot isn't installed” and a download link to [x.ai/bot](https://x.ai/bot).
- **⌃⌥G** still switches between Grok and the Grok Bot app. The menu bar extra does too. If Grok Bot is already the frontmost app, the hotkey comes back to Grok.
- Settings also offers **⌃⌥B** and **⌥⇧G**. If Grok Bot is not in `/Applications` or `~/Applications`, Settings has a path field and a Choose… button.
- Hover **Send to Grok Bot** on a Grok answer or code block, or right-click that content and choose **Send to Grok Bot**. Grok copies `Review, build and install this on my Mac:` plus the content, then brings the Grok Bot app forward. Paste and send it yourself.
- **File → Handoff Inbox…** (also in the bolt menu) lists the newest files in the Google Drive Grok Bot inbox, outbox, and done folders under `~/Library/CloudStorage`. **Open** opens a file. **Wake Grok** appears only when `~/Downloads/grok-bot-setup-check.sh` is present. It runs that script’s Keychain-signed webhook in the background and does not open Settings. The secret stays in the Keychain.
- The dot beside the menu-bar bolt is yellow while an outbox file is newer than the newest done file, and green otherwise.

### 🖥️ Build terminal
Build includes a live shell powered by SwiftTerm:
- **⌘`** opens the Build terminal.
- The pane has tabs, a split of the active tab, a font size, and a light or dark theme.
- The Finder service **Open in Terminal pane** opens a chosen folder there.
- **Send selection to Grok** sends the selected terminal text into a new grok.com chat.
- **Grok in terminal** types `grok` into that shell when the `grok` CLI is on your PATH. If it is not, the pane shows install help and does not install anything.

Ghostty is not included. SwiftTerm remains the terminal.

### ⌨ Command palette, cheat sheet, and Settings
- **⌘⇧K** opens a palette of actions, modes, and settings. Return runs the highlighted row. A setting row opens Settings.
- **⌘/** opens the keyboard shortcut cheat sheet.
- Settings search hides rows that do not match.
- Settings rows and the mode switcher have accessibility labels.
- The Grok Build API key stays in the macOS Keychain. Sparkle is linked, and this build does not start the updater.

---

## 📦 Installation

### Option 1: Download DMG (Recommended)

1. **Download** the latest `Grok-X.X.X.dmg` from [Releases](https://github.com/bcharleson/xai-grok/releases)
2. **Open** the DMG file
3. **Drag** Grok.app to your Applications folder
4. **Launch** Grok from Applications

> **First Launch:** macOS may show a security warning. Right-click the app → Open → Open to bypass Gatekeeper.

### Option 2: Build from Source

See [Build from Source](#-build-from-source) below.

---

## 🏁 Getting Started

### 1. Get Your API Key

1. Go to [console.x.ai](https://console.x.ai)
2. Sign in with your xAI/X account
3. Create a new API key
4. Copy the key (starts with `xai-...`)

### 2. Configure the App

1. Launch **Grok for Mac**
2. Open **Settings** (⌘,)
3. Go to the **Grok Build** tab
4. Paste your API key
5. Close Settings — you're ready!

### 3. Start Chatting

- Use **Grok** for grok.com, and **Build** for the local coding agent
- Press **Option-Space** for Quick Ask from any app

---

## ⌨️ Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| **Quick Ask** | ⌥Space (customizable) |
| **Screenshot to Grok** | ⌃⌥4 |
| **Open Grok Bot** | ⌘⇧B |
| **Switch with Grok Bot** | ⌃⌥G (customizable) |
| **New Tab** | ⌘T |
| **Close Tab / Hide Window** | ⌘W |
| **Switch Tab** | ⌘1–9 |
| **Prompt Library** | ⌘⇧P |
| **Find in Page** | ⌘F |
| **Focus Mode** | ⌘⇧F |
| **Full Screen** | ⌘⌃F |
| **Zoom In / Out / Actual Size** | ⌘= / ⌘- / ⌘0 |
| **Command Palette** | ⌘⇧K |
| **Build Terminal** | ⌘` |
| **Keyboard Shortcuts** | ⌘/ |
| **New Chat** | ⌘N |
| **Quick Query** | ⌘Space |
| **Settings** | ⌘, |
| **Minimize** | ⌘M |
| **Quit** | ⌘Q |
| **Copy / Paste / Select All** | ⌘C / ⌘V / ⌘A |
| **Back / Forward** | ⌘[ / ⌘] |
| **Reload** | ⌘R |

---

## 🔧 Settings & Configuration

Access Settings via **⌘,** or the menu bar.

### General Tab
| Setting | Description |
|---------|-------------|
| **Launch at Login** | Start Grok when you log in |
| **Show in Menu Bar** | Display icon in menu bar for quick access |
| **Auto-check for Updates** | Keep the app up to date automatically |
| **Global Shortcut** | Choose your preferred hotkey |

### Grok Build Tab
| Setting | Description |
|---------|-------------|
| **API Key** | Your xAI API key (stored in Keychain) |
| **Safety Mode** | Block potentially destructive commands |
| **Chat Retention** | How long to keep chat history (Forever/7 days/30 days) |

---

## 🛠 Build from Source

### Prerequisites

- **macOS 14.0** (Sonoma) or later
- **Xcode 15.0** or later
- **Swift 5.9** or later
- An [xAI API key](https://console.x.ai)

### Build Steps

```bash
# Clone the repository
git clone https://github.com/bcharleson/xai-grok.git
cd xai-grok

# Open in Xcode
cd GrokChat
open GrokApp.xcodeproj
```

Then in Xcode:
1. Select the **Grok** scheme
2. Choose **My Mac** as the destination
3. Press **⌘R** to build and run

### Command Line Build

```bash
cd GrokChat

# Build release version
xcodebuild -project GrokApp.xcodeproj \
           -scheme Grok \
           -configuration Release \
           build

# Find the built app
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release/
```

### Create a DMG

```bash
# Use the included build script
./build-dmg.sh
```

### Shipping a Sparkle update (production)

Follow the exact flow that shipped **1.0.89**:

- **Full checklist:** [`cursor/RELEASE_WORKFLOW.md`](cursor/RELEASE_WORKFLOW.md)
- **Short pointer:** [`GrokChat/RELEASE_WORKFLOW.md`](GrokChat/RELEASE_WORKFLOW.md)
- **After notarization:** `GrokChat/scripts/ship-sparkle-release.sh`

Critical: never run bare `generate_keys` on a release Mac. Confirm the production Sparkle public key (`a+vXV7…`) before every ship.

---

## 📁 Project Structure

```
xai-grok/
├── GrokChat/                      # Main app directory
│   ├── Sources/
│   │   ├── AppDelegate.swift      # App lifecycle, window management
│   │   ├── DeveloperRootView.swift # Developer chat UI (SwiftUI)
│   │   ├── SettingsWindow.swift   # Settings panel
│   │   ├── InputWindow.swift      # Quick input window
│   │   ├── Managers/
│   │   │   ├── HotKeyManager.swift    # Global hotkey handling
│   │   │   └── UpdateManager.swift    # Sparkle auto-updates
│   │   └── Utils/
│   │       └── KeychainHelper.swift   # Secure credential storage
│   ├── Tests/
│   │   └── GrokChatTests.swift    # Unit tests
│   ├── GrokApp.xcodeproj/         # Xcode project
│   ├── Package.swift              # Swift Package Manager
│   ├── Info.plist                 # App configuration
│   ├── appcast.xml                # Sparkle update feed
│   ├── bin/                       # Sparkle tools
│   ├── build.sh                   # Build script
│   ├── build-dmg.sh               # DMG creation script
│   └── release.sh                 # Release automation
├── .github/
│   └── PULL_REQUEST_TEMPLATE.md
├── logo/                          # App icons and branding
├── LICENSE                        # MIT License
├── README.md                      # This file
└── CONTRIBUTING.md                # Contribution guidelines
```

---

## 🔧 Technical Details

| Component | Technology |
|-----------|------------|
| **Language** | Swift 5.9+ |
| **UI Framework** | SwiftUI + AppKit |
| **Minimum macOS** | 14.0 (Sonoma) |
| **API Communication** | URLSession with streaming support |
| **Credential Storage** | macOS Keychain |
| **Preferences** | UserDefaults |
| **Auto-Updates** | Sparkle 2.x |
| **Markdown Rendering** | AttributedString + custom parser |
| **Code Highlighting** | Custom Swift highlighter |

### API Integration

The app communicates directly with the [xAI API](https://docs.x.ai):
- Endpoint: `https://api.x.ai/v1/chat/completions`
- Streaming: Server-Sent Events (SSE)
- Models: Fetched dynamically from `/v1/models`
- Pricing: Automatically calculated per model

---

## 🤝 Contributing

We welcome contributions! Whether it's bug fixes, new features, or documentation improvements.

### Quick Start

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
4. **Make** your changes
5. **Test** thoroughly
6. **Commit** (`git commit -m 'Add amazing feature'`)
7. **Push** (`git push origin feature/amazing-feature`)
8. **Open** a Pull Request

### Guidelines

- Follow Swift style conventions
- Add tests for new functionality
- Update documentation as needed
- Keep commits focused and atomic

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 🐛 Troubleshooting

### "App can't be opened because it is from an unidentified developer"
Right-click the app → **Open** → **Open**. This bypasses Gatekeeper for this app.

### API key not working
- Ensure your key starts with `xai-`
- Check that you have API credits at [console.x.ai](https://console.x.ai)
- Try regenerating your API key

### Global hotkey not working
- Check System Settings → Privacy & Security → Accessibility
- Ensure Grok has permission to control your computer
- Try a different hotkey combination in Settings

### High memory usage
- Use "Clear All Chats" in Settings to remove old conversations
- Set a retention policy (7 or 30 days) to auto-delete old chats

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

```
MIT License

Copyright (c) 2025 Brandon Charleson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software...
```

---

## 👨‍💻 Author

<a href="https://x.com/brandon_ai">
  <img src="https://img.shields.io/badge/@brandon__ai-000000?style=for-the-badge&logo=x&logoColor=white" alt="X/Twitter">
</a>
<a href="https://github.com/bcharleson">
  <img src="https://img.shields.io/badge/@bcharleson-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub">
</a>

**Brandon Charleson** — Creator & Maintainer

---

## 🙏 Acknowledgments

- **[xAI](https://x.ai)** — For creating Grok and providing the API
- **[Sparkle](https://sparkle-project.org)** — For the excellent auto-update framework
- **[HotKey](https://github.com/soffes/HotKey)** — For global hotkey support
- **Community Contributors** — Thank you for making this project better!

---

## ⚠️ Disclaimer

This is an **unofficial, community-built application**.

- Grok is a product of [xAI](https://x.ai)
- This project is **not affiliated with, endorsed by, or sponsored by xAI**
- You are responsible for your own API usage and costs
- Use at your own risk

---

<div align="center">

### ⭐ Star this repo if you find it useful!

[⭐ Star](https://github.com/bcharleson/xai-grok) · [🐛 Report Bug](https://github.com/bcharleson/xai-grok/issues) · [💡 Request Feature](https://github.com/bcharleson/xai-grok/issues) · [🍴 Fork](https://github.com/bcharleson/xai-grok/fork)

---

**Made with ❤️ for the Mac community**

</div>
