//
//  Local_Response_MapperApp.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI

@main
struct Local_Response_MapperApp: SwiftUI.App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var myColorScheme = ColorSchemeViewModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 300)
                .preferredColorScheme(myColorScheme.value)
        }

        .commands {
            FontSizeCommands()
        }

        Window("", id: "map-local-view") {
            LocalMapView()
                .frame(minWidth: 700, minHeight: 300)
                .preferredColorScheme(myColorScheme.value)
        }
    }
}

/// ⌘= and ⌘-, as menu commands rather than key handling on a view.
///
/// They used to live on `MyTextEditor`'s `onKeyPress`, which only sees a key
/// while that editor holds focus — so the shortcut worked in the response pane
/// and nowhere else in the window. A menu command is matched before the key
/// reaches any responder, so it fires wherever focus happens to be, and it
/// shows up in the menu bar where a shortcut can be discovered rather than
/// guessed.
///
/// The menu bar is app-wide on macOS, so attaching this to one scene covers the
/// rule editor window too.
struct FontSizeCommands: Commands {

    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    var body: some Commands {
        // Beside the system's own view-scaling items rather than in a menu of
        // our own — this is the same gesture every other Mac app puts there.
        CommandGroup(after: .toolbar) {
            Button("Increase Font Size") {
                fontSize = min(Constants.fontSizeMax, fontSize + 1)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Font Size") {
                fontSize = max(Constants.fontSizeMin, fontSize - 1)
            }
            .keyboardShortcut("-", modifiers: .command)

            Divider()
        }
    }
}
