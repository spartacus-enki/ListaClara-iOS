# iOS notifications and voice

## Implemented

UserNotifications authorization is requested from Settings. After local edits, foreground entry and synchronization, the app recomputes the earliest 60 pending list/event/family occasions and replaces its pending local requests. This is a conservative finite queue, not an unlimited scheduler. Renew it by opening the app. Revisions and matching DONE/SKIPPED/silenced occurrences suppress obsolete event alerts. Changes on Android can only cancel/reprogram iOS notifications after iOS downloads them.

Notifications use a generic title/body to reduce lock-screen disclosure and the default system sound. Tap navigation opens the related list/event/task subject to the local lock. Foreground announcement is opt-in; speech only runs when the app is active and unlocked. Event voice flags are respected. Manual read actions and a Spanish voice test use AVSpeechSynthesizer. Speech stops on leaving the active state.

No audio background mode, fake silent audio, VoIP push workaround, critical-alert entitlement or APNs registration is enabled. Delivery, Focus/silent mode, permission revocation and timezone/DST behavior require physical device testing. Expired reminders are not replayed in an endless catch-up loop.

Apple's [local notification API](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) can present an alert/sound when the app is not running. This does not grant the app continuous execution or dynamic background speech.

## Custom audio

Apple supports compatible custom alert files in the app bundle or Library/Sounds, shorter than 30 seconds; longer sounds fall back to the default. See [Preparing Custom Alert Sounds](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SupportingNotificationsinYourApp.html). The source currently ships the default sound. A later iOS-only change may add a reviewed short CAF/AIFF/WAV and select it with UNNotificationSound(named:). Rendering user-specific speech to files would require a bounded lifecycle and privacy/storage cleanup design; it is not implemented or promised here.

## APNs investigation

The existing backend exposes no device-token registration/removal route and no APNs provider. iOS source must not invent such endpoints. APNs requires a signed app with Push Notifications capability, device tokens delivered to an authenticated provider, APNs key/certificate/environment management, per-user/device authorization, token rotation/invalidation, logout handling and delivery observability. See [Registering with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

Proposed future work, requiring explicit authorization: add an optional versioned device-registration API while keeping existing API v1 behavior; send generic content-change signals; refresh authorized records; cover account changes/revocation and Android regression tests. Credentials stay on the provider. No schema/service/authentication change has been applied.

Even [background push updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) offer bounded execution and are not an exact wake-up timer. They cannot reproduce Android's unrestricted repeated background TTS/insistence behavior. App-open speech plus system-managed notification sounds are the delivered adaptation.
