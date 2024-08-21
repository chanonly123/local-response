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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .textSelection(.enabled)
                .frame(minWidth: 700, minHeight: 300)
        }
        Window("", id: "map-local-view") {
            LocalMapView()
                .textSelection(.enabled)
                .frame(minWidth: 700, minHeight: 300)
        }
    }
}
