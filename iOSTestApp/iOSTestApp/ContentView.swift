//
//  ContentView.swift
//  iOSTestApp
//
//  Created by Chandan on 17/09/24.
//

import SwiftUI

struct ContentView: View {

    @State var response: String? = "-"

    var body: some View {
        ScrollView {
            VStack {

                VStack(alignment: .leading) {
                    Text("1. 'LocalResponse.connect()' add to AppDelegate didFinishLaunchingWithOptions")
                    Text("2. Open the 'Local response' macos app")
                    Text("3. Hit 'GET' or 'POST', It should show the api calls and components")
                }
                .frame(maxWidth: .infinity)

                Divider()

                ApiCallView(url: "https://yavuzceliker.github.io/sample-images/image-\((1...100).randomElement()!).jpg", method: "GET")
                Divider()

                ApiCallView(url: "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4", method: "GET")
                Divider()

                ApiCallView(url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", method: "GET")
                Divider()

                ApiCallView(url: "https://jsonplaceholder.typicode.com/todos/1", method: "GET")

                ApiCallView(url: "https://jsonplaceholder.typicode.com/todos/1", method: "POST")
                Divider()
            }
        }
        .padding()
        .disabled(response == nil)
    }

    func callApi() {
        Task {
            do {
                response = "loading"
                let req = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com/todos/1")!)
                let res = try await URLSession.shared.data(for: req)
                if let string = String(data: res.0, encoding: .utf8) {
                    response = string
                } else {
                    response = "-"
                }
            } catch let err {
                response = "Error: \(err)"
            }
        }
    }
}

struct ApiCallView: View {

    let url: String
    let method: String
    @State private var response: String = "-"

    var body: some View {
        Button(method) {
            callApi()
        }
        .buttonStyle(.bordered)

        Text(response)
    }

    func callApi() {
        Task {
            do {
                response = "loading"
                var req = URLRequest(url: URL(string: url)!)
                req.httpMethod = method
                let res = try await URLSession.shared.data(for: req)
                if let string = String(data: res.0, encoding: .utf8) {
                    response = string
                } else {
                    response = "-"
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
