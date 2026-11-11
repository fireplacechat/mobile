# 0026: Push notifications, app icon badge and notification settings

Status: requested by the owner, 2026-11-11, after moving the Firebase project to
the Blaze plan. Review before merge. No change to keys, the ratchet or message
payloads. The backend change is in the backend repository (decision 0013 there).

## What a notification shows

```
[Fireplace icon]  alice                 now
                  New Message
```

The title is the sender's **username** and the body is always **New Message**.
The icon is the app icon on iOS and the white flame tinted orange on Android.
Nothing else is sent: no message text, no chat id, no account id, no badge
number. The server only has ciphertext, so it could not show the text even if
asked. The username already sits in `users/{uid}` on the server.

On a device where **Show sender's name** is off, the title is **Fireplace**.
How alerts appear on a locked phone follows the phone's own preview setting.

One alert per conversation: later alerts from the same person replace the
earlier one (APNs collapse id / Android tag), and the sender sends at most one
alert per conversation per recipient every 20 seconds. Reactions, edits and
deletes are encrypted messages like any other, so the server cannot tell them
apart and they also alert. The throttle keeps a burst, such as Delete all, to
one alert.

## Who gets an alert

The `pushOnMessage` Cloud Function runs when a message document is created. It
alerts only the recipient's devices that received an envelope, never the
sender's own linked devices. It sends nothing for an unaccepted message
request, a sender the recipient blocked, or an account that is deleted or being
deleted. Tokens that FCM reports as dead are removed.

## Permission and settings

- The first signed-in launch shows the system prompt (iOS, and Android 13+).
  Afterwards Fireplace never prompts at launch. iOS reports "not determined"
  until it has asked. Android reports "denied" before the first request, so
  the app also remembers that it asked (`pushasked:<uid>` in the secure store).
- **Settings → Notifications** in the app:
  - **Allow notifications** registers or unregisters this device. Turning it
    off is remembered (`pushoff:<uid>`), so a later launch does not
    re-register. If the system setting is off, the switch opens the system
    settings, because the app may not prompt again.
  - **Show sender's name** is stored as `showName` on this device's
    registration.
  - **Sounds, banners and badges** opens the system settings for Fireplace.
- iOS Settings → Fireplace → Notifications and Android's "Messages" channel
  control sounds, banners, badges and lock-screen previews as usual.
- While Fireplace is open, the system banner is suppressed. The existing
  in-app notice (with its own "Show message text" choice) shows arrivals.

## App icon badge

The badge is the unread total from the encrypted local history, with muted
chats excluded, the same numbers as the chat list. The app sets it whenever
that total changes and clears delivered alerts when it reaches zero. The
server never learns what was read, so pushes carry no badge. On iOS the badge
keeps its last value while the app is closed and corrects itself when it
opens. A count that climbs while closed would need a Notification Service
Extension and an App Group; that is left for a later decision. Android shows
the launcher's dot while an alert is in the shade.

## Server fields and rules

- `users/{uid}/pushTokens/{deviceId}` gains an optional boolean `showName`
  (owner-only, as before). Older apps omit it and keep showing names.
- `pushThrottle/{chatId}` maps a recipient uid to when they were last alerted.
  Only the function writes it; the rules deny all client access. It records
  when messages arrived, which each message's `ts` already shows; it holds no
  read state. `fp-ops delete` removes the deleted account's entry.

## What it costs

Per message: one function call, about 6 Firestore reads (chat, block, two
profiles, tokens, throttle) and 1 write when an alert is sent. FCM is free. At
20 people × 100 messages a day this stays inside the free allowances. The
function has `maxInstances: 2`, 256 MiB, 20 s and no retries. Firestore has no
spending cap on Blaze, so the owner should set budget alerts.

## Native and project changes

- iOS: `Runner.entitlements` (`aps-environment`), `UIBackgroundModes:
  remote-notification`, and a `fireplace/notifications` channel in
  `AppDelegate.swift` (badge, clear delivered, open settings).
- Android: the "Messages" channel, a status-bar icon generated from the
  existing flame artwork (`ic_notification`), the brand color, and the same
  channel in `MainActivity.kt`. `POST_NOTIFICATIONS` was already allowed by
  `scripts/check_apk.sh`.
- `PUSH_ENABLED` now defaults to true. `--dart-define=PUSH_ENABLED=false`
  builds without push.

## Owner setup before release

1. Apple Developer → Identifiers → `com.fireplacechat.app` → enable **Push
   Notifications**. Create an APNs auth key (.p8) and upload it in Firebase
   console → Project settings → Cloud Messaging.
2. Regenerate the App Store profile so it includes push (run **iOS signing
   setup**). Until then a signed upload fails on the new entitlement.
3. Set budget alerts in Google Cloud Billing.
4. Deploy from the backend repository: `firebase deploy --only
   firestore:rules,functions`.
5. Update the privacy policy and store privacy answers: push token, sender
   username shown in alerts, Apple/Google as processors.

## Tests

`push_notification_service_test.dart` (first-launch prompt, no re-prompt,
remembered opt-out, system-off cleanup, name preference, existing race
tests), `app_badge_test.dart`, `push_settings_test.dart`, the
`settings-notifications` render, and in the backend the sender unit tests,
rules tests for `showName` and `pushThrottle`, and an operator deletion test.
Implementation assisted by Claude Code.
