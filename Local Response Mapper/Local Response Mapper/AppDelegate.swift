//
//  AppDelegate.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import AppKit
import Factory

class AppDelegate: NSObject, NSApplicationDelegate {
    @Injected(\.db) var db
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isPreview {
            db.createDummyForPreview()
        }
    }
    
    static var isPreview: Bool {
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

