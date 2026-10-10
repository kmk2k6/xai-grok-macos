//
//  HotKeyManager.swift
//  Grok for Mac
//
//  Created by Brandon Charleson on 2025.
//  Copyright © 2025 Brandon Charleson. All rights reserved.
//
//  https://github.com/bcharleson/xai-grok
//

import Cocoa
import Carbon

protocol HotKeyDelegate: AnyObject {
    func hotKeyTriggered()
    func screenshotHotKeyTriggered()
}

class HotKeyManager {
    static let shared = HotKeyManager()
    weak var delegate: HotKeyDelegate?
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID(signature: OSType(0x47524F4B), id: 1) // 'GROK', 1
    
    private var currentKeyCode: UInt32 = 49 // Space
    private var currentModifiers: UInt32 = UInt32(optionKey) // Option
    
    // Presets
    enum ShortcutPreset: Int {
        case optionSpace = 0
        case controlSpace = 1
        case commandShiftG = 2
        case optionG = 3
        
        var name: String {
            switch self {
            case .optionSpace: return "Option + Space"
            case .controlSpace: return "Control + Space"
            case .commandShiftG: return "Command + Shift + G"
            case .optionG: return "Option + G"
            }
        }
        
        var keyCode: UInt32 {
            switch self {
            case .optionSpace: return 49 // Space
            case .controlSpace: return 49 // Space
            case .commandShiftG: return 5 // G
            case .optionG: return 5 // G
            }
        }
        
        var modifiers: UInt32 {
            switch self {
            case .optionSpace: return UInt32(optionKey)
            case .controlSpace: return UInt32(controlKey)
            case .commandShiftG: return UInt32(cmdKey | shiftKey)
            case .optionG: return UInt32(optionKey)
            }
        }
    }

    /// Region-capture shortcut. Default is Control-Option-4.
    enum ScreenshotPreset: Int {
        case controlOption4 = 0
        case optionShift4 = 1
        case controlShift4 = 2

        var name: String {
            switch self {
            case .controlOption4: return "Control + Option + 4"
            case .optionShift4: return "Option + Shift + 4"
            case .controlShift4: return "Control + Shift + 4"
            }
        }

        var keyCode: UInt32 { 21 } // kVK_ANSI_4

        var modifiers: UInt32 {
            switch self {
            case .controlOption4: return UInt32(controlKey | optionKey)
            case .optionShift4: return UInt32(optionKey | shiftKey)
            case .controlShift4: return UInt32(controlKey | shiftKey)
            }
        }
    }
    
    func setup() {
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressed
            )
            if status == noErr && pressed.id == 2 {
                HotKeyManager.shared.delegate?.screenshotHotKeyTriggered()
            } else {
                HotKeyManager.shared.delegate?.hotKeyTriggered()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        
        // Load preference
        let saved = UserDefaults.standard.integer(forKey: "hotkeyPreset")
        let preset = ShortcutPreset(rawValue: saved) ?? .optionSpace
        setPreset(preset)
        let shot = ScreenshotPreset(rawValue: UserDefaults.standard.integer(forKey: "screenshotHotkeyPreset")) ?? .controlOption4
        setScreenshotPreset(shot)
    }
    
    func setPreset(_ preset: ShortcutPreset) {
        // Save
        UserDefaults.standard.set(preset.rawValue, forKey: "hotkeyPreset")
        
        // Register
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        
        let id = EventHotKeyID(signature: OSType(0x47524F4B), id: 1)
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        #if DEBUG
        print("Registered HotKey: \(preset.name)")
        #endif
    }

    func setScreenshotPreset(_ preset: ScreenshotPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: "screenshotHotkeyPreset")
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x47524F4B), id: 2)
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &screenshotHotKeyRef)
    }
}
