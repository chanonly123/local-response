//
//  MyColorScheme.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/10/24.
//

import Cocoa
import SwiftUI

class ColorSchemeViewModel: ObservableObject {

    static let shared = ColorSchemeViewModel()

    private init() {}

    @Published var value: ColorScheme = .dark

    func rotateScheme() {
        value = value == .dark ? .light : .dark
    }
}
