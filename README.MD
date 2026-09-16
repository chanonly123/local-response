# Local response

[![](https://jitpack.io/v/chanonly123/local-response.svg)](https://jitpack.io/#chanonly123/local-response)

**Local response** is a powerful developer tool for iOS and Android developers, allowing you to intercept and mock network traffic in your apps without the need for certificates or proxy configurations. This tool is a lightweight alternative to Proxyman and Charles Proxy, specifically designed for simplicity and ease of use.

## Features

- **iOS — Method Swizzling**: Intercepts `URLSession` classes through method swizzling, capturing network requests and responses. No extra code changes required.
- **Android — OkHttp Interceptor**: Add one interceptor to your `OkHttpClient` and every call through it — including Retrofit — is captured and mappable.
- **MacOS Companion App**: Records all intercepted traffic in a dedicated macOS app, which listens for incoming data via a simple server.
- **Mock Responses**: Easily override and mock network responses directly from the macOS app, enabling you to test various scenarios without modifying your code.
- **Modify Requests**: Rewrite outgoing requests before they are sent — add or replace headers, query parameters, and the request body — while still letting the call reach the real server.
- **Variables & Placeholders**: Reuse values such as tokens or base urls across rules, and inject dynamic values like `{{uuid}}` or `{{timestamp}}` that are resolved fresh on every request.
- **No Certificates or Proxy Needed**: Unlike other tools, this solution does not require the installation of certificates or the use of a proxy, simplifying the setup process.

## How to mock response
[![](https://markdown-videos-api.jorgenkh.no/youtube/_tsQh9sRV7M)](https://www.youtube.com/watch?v=_tsQh9sRV7M)

## Installation

### 1. macOS App — the server

Everything else talks to this app, so install it first. It records the traffic and serves the mapped responses; with it closed, the libraries below have nothing to send to.

**Install the latest release:**

```sh
curl -L -o ~/Downloads/app.zip https://github.com/chanonly123/local-response/releases/latest/download/Local.Response.Mapper.app.zip
unzip -oq ~/Downloads/app.zip -d ~/Downloads
open "$HOME/Downloads/Local Response Mapper.app"
```

**Or build it yourself.** Clone the repo and run the launch script — it builds the app and opens it for you:

```sh
git clone https://github.com/chanonly123/local-response.git
cd local-response
sh run.sh
```

That's it. `run.sh` builds `Local Response Mapper` with `xcodebuild` and launches the app.

- **Clean build:** `sh run.sh -clean`
- **Xcode instead:** open `Local_Response_Mapper/Local Response Mapper.xcodeproj` and run with `Cmd+R`.

### 2. iOS Library

1. **Start the macOS app** — install it as above and leave it running. The library connects to it on port 4040.

2. **Add the library to your project:**

   - Using Swift Package Manager:
     ```swift
     dependencies: [
       .package(url: "https://github.com/chanonly123/local-response.git", from: "1.0.0")
     ]
     ```

   - Using Cocoapods:
      Add `pod 'LocalResponse'` to `Podfile`

   - Or by manually integrating the library into your project.

3. **Initialize the Interceptor:**

  In your AppDelegate or at the start of your app:
   ```
   import LocalResponse

   class AppDelegate: NSObject, UIApplicationDelegate {
      func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
            // for simulator
            LocalResponse.connect()
            // for simulator and other physical devices
            LocalResponse.connect(connectionUrl: "http://192.168.31.24:4040")
        #endif
      }
   }
  ```

### 3. Android Library

1. **Start the macOS app** — install it as above and leave it running. The library connects to it on port 4040.

2. **Add the library to your project:**

   Add the JitPack repository in `settings.gradle.kts`:
   ```kotlin
   dependencyResolutionManagement {
       repositories {
           google()
           mavenCentral()
           maven { url = uri("https://jitpack.io") }
       }
   }
   ```

   Then the dependency in your module's `build.gradle.kts`:
   ```kotlin
   debugImplementation("com.github.chanonly123:local-response:2.2.8")
   ```

   `debugImplementation` keeps the interceptor — and the local network traffic it
   generates — out of your release builds.

3. **Add the interceptor to your OkHttp client:**

   ```kotlin
   import com.chanonly123.local_response.LocalResponseConfig
   import com.chanonly123.local_response.LocalResponseInterceptor

   val client = OkHttpClient.Builder()
       // for emulator
       .addInterceptor(LocalResponseInterceptor(LocalResponseConfig.emulator()))
       // for physical devices, use the address the macOS app shows
       .addInterceptor(LocalResponseInterceptor(
           LocalResponseConfig.localIpAddress("http://192.168.31.24:4040")
       ))
       .build()
   ```

   Retrofit picks this up through `Retrofit.Builder().client(client)`. A physical
   device has to reach your Mac over the LAN, so the app needs
   `android:usesCleartextTraffic="true"` for the plain-HTTP connection to the
   mapper.

   Requires OkHttp 4 or later, `minSdk` 24, and the `INTERNET` permission.

## Usage

- **Intercepting Traffic:**
  - Once the library is initialized in your iOS app, all network requests made via `URLSession` will be intercepted and logged in the macOS app.
  - On Android, every request through an `OkHttpClient` carrying `LocalResponseInterceptor` is logged the same way.

- **Mocking Responses:**
  - In the macOS app, you can select any intercepted request and provide an overridden response. The app will receive this mocked response as if it were from the actual server.

### Rules

Every override lives in the **Local Map** list as a rule. A rule matches a request when its method matches (`* (any)` matches every method) and the request url *contains* the rule's url text (`*` on its own matches every url). An empty url matches nothing, so a half-written rule never swallows your traffic.

Rules come in two kinds:

| Kind | Badge | What it does |
| --- | --- | --- |
| **Map Response** | `RES` | Answers the request from the macOS app. The call never leaves the device. |
| **Modify Request** | `REQ` | Edits the outgoing request, then lets it go to the real server. |

Order matters. Rules are matched top to bottom:

- Every matching **Modify Request** rule is applied, so several can stack on the same request. When two rules set the same header or query parameter, the lower one wins.
- The first matching **Map Response** rule serves the response and stops the walk — later rules never see the request.

Each rule shows a hit count. An enabled rule stuck at `0` usually means its url text does not match what the app actually requests.

#### Override response (Map Response)

Pick an intercepted request, create a rule from it, and edit:

- **Status code** — return `500`, `401`, or anything else to test error paths.
- **Response headers** — one `name: value` per line. `Content-Length` and `Content-Type` are always set by the app itself, so they win over anything the rule declares.
- **Response body** — the exact text the app receives.

#### Override request (Modify Request)

The request still goes to the server; only what is sent changes:

- **Query parameters** — one `name: value` per line (`name=value` also works). A parameter the url already carries is replaced, the rest are kept.
- **Request headers** — one `name: value` per line. An existing header of the same name is replaced.
- **Request body** — replaces the body the app sent. Leave it empty to keep the original body.

A Modify Request rule that sets none of the three does nothing, and the editor says so.

### Variables

Any response or request field above can carry `{{...}}` placeholders. They are resolved in the macOS app, on every request — the injected library only applies what the app hands back. A token that names nothing is left exactly as written, so bodies containing braces are safe.

Built-ins:

| Token | Value |
| --- | --- |
| `{{uuid}}` | A new UUID. |
| `{{timestamp}}` | Seconds since 1970. |
| `{{timestamp_ms}}` | Milliseconds since 1970. |
| `{{iso8601}}` | UTC, internet date-time. |
| `{{date:yyyy-MM-dd HH:mm:ss}}` | The time now, in the format after the colon. |
| `{{random_int:1-100}}` | A whole number in the range after the colon. |

The same token used twice in one request resolves to the same value, so a request id can be sent in a header and in the body at once.

Your own variables — a token, a build number, a base url — are defined once in the **Variables** sheet (the `{ }` button) and used as `{{name}}` in any rule. They are saved as you type, and a built-in name always wins over a variable of the same name.

```
Authorization: Bearer {{authToken}}
X-Request-Id: {{uuid}}
X-Sent-At: {{iso8601}}
```

## Examples

- **Logging Requests:**
  - The macOS app provides a clear and detailed log of all intercepted network traffic, including URLs, headers, and body content.

- **Testing Error Scenarios:**
  - Override network responses to simulate server errors, or custom data responses.

- **Testing Against Another Environment:**
  - Use a Modify Request rule to swap the auth header or add a `?env=staging` parameter, keeping the real server in the loop.

## Screenshots

### Records all http network calls, You can edit (Response, Headers, StatusCode)
![alt tag](https://github.com/chanonly123/local-response/raw/main/demo/demo2.gif)

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

[Highlightr](https://github.com/raspu/Highlightr) - iOS & OSX Syntax Highlighter.

[CodeEditor](https://github.com/ZeeZide/CodeEditor) - A SwiftUI TextEditor with syntax highlighting using Highlight.js
