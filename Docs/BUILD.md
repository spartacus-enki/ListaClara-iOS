> Documento de la fase inicial. La ruta sin Mac propia y el estado actual están en [Fase 1.2](phase1.2/REPORT.md).

# Build, signing and iPhone installation

## Required environment

A Mac with Xcode and an iOS SDK supporting deployment target 16.0; use Xcode 15 or newer and select an Xcode version compatible with the actual iPhone OS. Swift package manifest uses Swift tools 5.9. An iPhone on iOS 16+, USB or paired wireless connection, owner-controlled Apple account/team and a reachable HTTPS SPARTA root URL with an existing authorized account. None of these signing credentials or production accounts are bundled.

No third-party Swift dependencies. Foundation, SwiftUI, UIKit, UserNotifications, AVFoundation, LocalAuthentication, Security, CryptoKit, PhotosUI and Vision come with the SDK. The checked-in Xcode project is directly openable; Python generation is optional.

## Transfer to durable storage

The Linux session can only write inside Android or /tmp. Android was preserved, so this project lives at `/tmp/ListaClara-iOS`. Copy the sibling archive to the Mac or extract it into a separate owner-managed directory, preferably `/home/dexanox/Servicios/TaskFamily/ListaClara-iOS` on SPARTA using normal owner access. Do not extract into the Android directory. No elevation is inherently required for an owner-writable parent.

The archive contains a top-level `ListaClara-iOS` folder. Verify its SHA256 against the delivered `.sha256` file. On a Mac, extract in the desired parent directory with `tar -xzf ListaClara-iOS-1.0.0.tar.gz`.

## Mac verification commands

From the iOS project directory:

```sh
swift test
xcodebuild -list -project ListaClara.xcodeproj
xcodebuild -project ListaClara.xcodeproj -scheme ListaClara -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -showdestinations -project ListaClara.xcodeproj -scheme ListaClara
```

Then use an installed iPhone simulator ID from that output:

```sh
xcodebuild -project ListaClara.xcodeproj -scheme ListaClara -destination 'platform=iOS Simulator,id=REPLACE_WITH_INSTALLED_SIMULATOR_ID' CODE_SIGNING_ALLOWED=NO test
```

`swift test` checks portable Core only; Xcode builds and tests the full app host and Apple adapters. Save build/test output and xcresult, and resolve any compile/typechecking or SDK issues before calling this a verified build. There is no `.ipa` in this delivery.

## Install on your iPhone

1. Open `ListaClara.xcodeproj` and choose the shared `ListaClara` scheme.
2. In Xcode Settings → Apple Accounts, sign into the owner's account. Set the app and test targets' Signing & Capabilities Team and keep automatic signing. Use an owner-controlled unique bundle ID if `mx.listaclara.ios` is unavailable. This is separate from Android's application ID.
3. Connect/unlock the iPhone, trust the Mac and enable Developer Mode when required. Select that device, then Build/Run. Xcode creates the permitted development signing assets. Follow [Apple's device-running instructions](https://developer.apple.com/documentation/xcode/building-and-running-an-app) and [Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
4. In the app, connect to the existing HTTPS SPARTA root URL, log in with an existing account, allow local-network access if applicable, and explicitly permit notifications. Test first with an approved non-production account/server.
5. Check login/session restoration, account isolation, airplane-mode edits/retries, conflict choices, item completion on both phones, event timezone/DST, family permissions/history/repeats, notification tap/lock, sounds/Focus and foreground speech. Compare all screens with Android.

A [Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account) supports development testing with restrictions; Apple states its device provisioning profiles expire after seven days. Advanced capabilities/distribution require the appropriate program membership. This work does not enroll accounts, publish, upload to TestFlight or submit to the App Store.

No APNs entitlement is necessary for the local notifications shipped here. Do not add Push Notifications capabilities without the separately authorized provider work described in NOTIFICATIONS.md.
