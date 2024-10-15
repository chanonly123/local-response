//
//  ContentView.swift
//  iOSTestApp
//
//  Created by Chandan on 17/09/24.
//

import SwiftUI

struct ContentView: View {

    @State var response: String? = "<>"

    var body: some View {
        ScrollView {
            VStack {
                Button("Call Api") {
                    callApi()
                }
                Text(response ?? "")
            }
        }
        .padding()
        .disabled(response == nil)
    }

    func callApi() {
        response = nil
        Task {
            do {
                let req = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com/todos/1")!)
                let res = try await URLSession.shared.data(for: req)
                if let string = String(data: res.0, encoding: .utf8) {
                    response = string
                } else {
                    response = "<empty>"
                }
            } catch let err {
                response = "Error: \(err)"
            }
        }
    }
}

#Preview {
    ContentView()
}
