# Local response

**Local response** is a powerful developer tool for iOS developers, allowing you to intercept and mock network traffic in your iOS apps without the need for certificates or proxy configurations. This tool is a lightweight alternative to Proxyman and Charles Proxy, specifically designed for simplicity and ease of use.

## Features

- **Method Swizzling**: Intercepts `URLSession` classes through method swizzling, capturing network requests and responses. No extra code changes required.
- **MacOS Companion App**: Records all intercepted traffic in a dedicated macOS app, which listens for incoming data via a simple server.
- **Mock Responses**: Easily override and mock network responses directly from the macOS app, enabling you to test various scenarios without modifying your code.
- **No Certificates or Proxy Needed**: Unlike other tools, this solution does not require the installation of certificates or the use of a proxy, simplifying the setup process.

## How to mock response
![alt tag](https://github.com/chanonly123/local-response/raw/main/demo/demo4.mp4)

## TODO
- Recording requests directly to Map Local window
- Mac app new version check
- Adding unit tests

## Installation

### iOS Library

1. **Add the library to your project:**

   - Using Swift Package Manager:
     ```swift
     dependencies: [
       .package(url: "https://github.com/chanonly123/local-response.git", from: "1.0.0")
     ]
     ```

   - Or by manually integrating the library into your project.

2. **Initialize the Interceptor:**

  In your AppDelegate or at the start of your app:
   ```
   import LocalResponse

   class AppDelegate: NSObject, UIApplicationDelegate {
      func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
            // When using the iOS simulator in the same network
            LocalResponse.shared.connect()

            // When using other devices in the same network, pass the local url (availabe in the listener macos app)
            LocalResponse.shared.connect(connectionUrl: "http://192.168.0.108:4040")
        #endif
      }
   }
  ```

### macOS App

1. **Download the macOS app:**
   - [Download Latest Release](https://github.com/chanonly123/local-response/releases)

2. **Run the macOS app:**
   - Launch the app, and it will automatically start listening for traffic from your iOS app.
   - Allow it to run from security options from settings.

## Usage

- **Intercepting Traffic:**
  - Once the library is initialized in your iOS app, all network requests made via `URLSession` will be intercepted and logged in the macOS app.
  
- **Mocking Responses:**
  - In the macOS app, you can select any intercepted request and provide an overridden response. The iOS app will receive this mocked response as if it were from the actual server.

## Examples

- **Logging Requests:**
  - The macOS app provides a clear and detailed log of all intercepted network traffic, including URLs, headers, and body content.

- **Testing Error Scenarios:**
  - Override network responses to simulate server errors, or custom data responses.

## Screenshots

### Allow the app to run
![alt tag](https://github.com/chanonly123/local-response/raw/main/demo/demo1.png)

### Records all http network calls
![alt tag](https://github.com/chanonly123/local-response/raw/main/demo/demo2.png)

### You can edit (Response, Headers, StatusCode)
![alt tag](https://github.com/chanonly123/local-response/raw/main/demo/demo3.png)

## Contributing

Contributions are most welcome! Please open an issue or submit a pull request with your improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Inspired by the need for simpler traffic interception without the hassle of certificate management. Apart from that most of the solutions are paid.

## Thanks To

A big thanks to the following open-source projects and contributors whose code has been used in this project:

[atlantis](https://github.com/ProxymanApp/atlantis) - Capture HTTP/HTTPS, and Websocket from iOS app without proxy.

[FlyingFox](https://github.com/swhitty/FlyingFox) - Lightweight, HTTP server written in Swift using async/await.

[Factory](https://github.com/hmlongco/Factory) - A new approach to Container-Based Dependency Injection for Swift and SwiftUI.

[realm-swift](https://github.com/realm/realm-swift) - Realm is a mobile database: a replacement for Core Data & SQLite.

