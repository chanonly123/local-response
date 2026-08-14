//
//  AppDelegate.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import AppKit
import Factory

class AppDelegate: NSObject, NSApplicationDelegate {

    /// Kept for the process lifetime: the activity ends when this is released.
    private var backgroundActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Traffic is recorded while the user works in another app, so this one
        // has to keep processing and drawing while it is not frontmost. Without
        // an activity assertion macOS puts the app in App Nap once its window
        // is covered, timers and run loop work get coalesced, and the request
        // list only catches up when the window is focused again.
        //
        // `userInitiatedAllowingIdleSystemSleep` opts out of App Nap without
        // also keeping the machine awake.
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Recording network traffic in the background"
        )
    }
}

