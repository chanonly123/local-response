//
//  iOSTestAppApp.swift
//  iOSTestApp
//
//  Created by Chandan on 17/09/24.
//

import SwiftUI

@main
struct iOSTestAppApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
