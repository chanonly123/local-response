//
//  Local_Response_MapperApp.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI
import RealmSwift

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

        Window("", id: "map-local-view") {
            LocalMapView()
                .frame(minWidth: 700, minHeight: 300)
                .preferredColorScheme(myColorScheme.value)
        }
    }
}
