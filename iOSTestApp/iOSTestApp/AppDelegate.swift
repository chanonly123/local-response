//
//  AppDelegate.swift
//  iOSTestApp
//
//  Created by Chandan on 17/09/24.
//

import LocalResponse

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        LocalResponse.shared.connect()
        return true
    }
}