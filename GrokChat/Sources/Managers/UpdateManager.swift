//
//  UpdateManager.swift
//  Grok for Mac
//
//  Created by Brandon Charleson on 2025.
//  Copyright © 2025 Brandon Charleson. All rights reserved.
//
//  https://github.com/bcharleson/xai-grok
//

import Cocoa
import Sparkle

/// Sparkle is linked, but this fork never checks for or installs updates.
/// The feed URL and public key in Info.plist are blank, and the updater is not started.
class UpdateManager: NSObject {

    static let shared = UpdateManager()

    /// The Sparkle updater controller
    private var updaterController: SPUStandardUpdaterController!

    /// True when Info.plist has a real feed URL and ED25519 public key.
    private let isConfiguredForUpdates: Bool

    /// True when the updater has been started (Release + configured).
    private(set) var isUpdaterRunning: Bool = false

    /// The underlying updater for programmatic access
    var updater: SPUUpdater {
        return updaterController.updater
    }

    private override init() {
        isConfiguredForUpdates = false

        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        isUpdaterRunning = false
        print("[UpdateManager] Sparkle not started; update checks are off")
    }

    // MARK: - Public Methods

    /// Menu item stays wired, but it does not start Sparkle or contact a feed.
    @objc func checkForUpdates(_ sender: Any?) {
        print("[UpdateManager] Ignoring update check")
    }

    /// Background checks are disabled.
    func checkForUpdatesInBackground() {
    }

    /// Returns true if an update check can be performed
    var canCheckForUpdates: Bool {
        guard isConfiguredForUpdates else { return false }
        return updater.canCheckForUpdates
    }

    /// Configure automatic update settings
    func configureAutomaticUpdates(enabled: Bool) {
        guard isConfiguredForUpdates else { return }
        updater.automaticallyChecksForUpdates = enabled
    }

    /// Configure automatic download of updates
    func configureAutomaticDownloads(enabled: Bool) {
        guard isConfiguredForUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
    }

    /// Set the update check interval (in seconds)
    func setUpdateCheckInterval(_ interval: TimeInterval) {
        guard isConfiguredForUpdates else { return }
        updater.updateCheckInterval = interval
    }

    /// Get current app version string
    var currentVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Get current build number
    var currentBuild: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - SPUUpdaterDelegate
extension UpdateManager: SPUUpdaterDelegate {

    /// Called when a valid update is found
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        #if DEBUG
        print("[UpdateManager] Found valid update: \(item.displayVersionString) (build \(item.versionString))")
        #endif
    }

    /// Called when no update is found
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        #if DEBUG
        print("[UpdateManager] No update available or error: \(error.localizedDescription)")
        #endif
    }

    /// Called when update check fails
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        #if DEBUG
        print("[UpdateManager] Update aborted: \(error.localizedDescription)")
        #endif
    }

    /// Called when update is about to be installed
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        #if DEBUG
        print("[UpdateManager] Will install update: \(item.displayVersionString)")
        #endif
    }
}
