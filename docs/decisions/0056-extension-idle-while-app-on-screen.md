# 0056: The iPhone extension does nothing while the app is on screen

Date: 2026-11-15. Status: accepted by the owner. Works on issue 178. Adds to
[0043](0043-ios-notification-service.md); changes nothing in what the extension
may read or write.

## The problem

iOS starts the notification extension for every push, also while the app is
open. The extension reads its keys, asks the server for the new messages,
decrypts them, and rewrites the alert (0043). It saves nothing: the app then
fetches and decrypts the same messages itself.

While the app is on screen, that work is thrown away twice over: the app is
receiving the message anyway, and the system shows no banner then (the app's own
in-app notice does that job). So every message received while chatting cost a
second network request, a second decryption and a round of keychain reads, for
nothing. This is the largest cost per message that exists only on iPhone.

## What changes

- **The app marks that it is on screen**: it touches an empty file,
  `foreground`, in the container it shares with the extension, when it comes to
  the front and about every ten seconds while it stays there. It removes the
  file when it leaves the front (inactive, hidden, paused, closed).
- **The extension looks at that file first.** One touched in the last 30 seconds
  means the app is on screen: the extension returns the push unchanged, without
  opening the keychain, the network or the crypto core.
- A file left behind by an app that was killed while open stops counting after
  30 seconds, so previews cannot stay off.

The extension cannot ask iOS whether the app is running; a file both can see is
the simplest signal that needs no entitlement.

## Also: the newest three messages, not the oldest ten

With the app closed, the extension asked the server for up to ten messages
*counting up* from where the app last saved its place, and decrypted each. After
more than ten unread messages it never reached the newest one, so the preview
showed an old message, and every push repeated the same ten.

It now asks for the **newest three** since that place and handles them oldest
first. The alert is about the newest; the one or two before it are there so that
a reaction or a delete that follows a text is seen together with it. The ratchet
steps over anything older without decrypting it (it derives and keeps the
skipped keys in its throwaway copy, up to the usual thousand), so a long backlog
costs one request and at most three decryptions per push, where it was ten.

## What it does not change

- Previews with the app in the background or closed: as before.
- What the extension is allowed to do (0043): it still writes nothing.
- With the app closed, a message is still decrypted once by the extension
  for its preview and once by the app when it opens. Removing that would mean
  the extension saving what it decrypts, as Signal's does. It is deliberately
  not done: the history database is in the app's own storage, which the
  extension cannot reach (decision 0057), and giving the extension write
  access to sessions and history is the largest risk decision 0043 avoided.
  What remains is one small decryption per push.

## Privacy

The file is empty and has a fixed name. It says the app was on screen in the
last half minute, to another process of the same app on the same phone.

## Cost

One file touch every ten seconds while the app is on screen. No server reads or
writes; fewer of both, since the extension's request is skipped.

## Not verified

No iPhone and no Mac were available. The Swift code is type-checked and its
tests run in the macOS CI job, and the Dart side is tested, but the behaviour on
a device (that the banner is indeed not shown, that the file is readable from
the extension) is unconfirmed.

## Tests

- `test/app/ios_foreground_marker_test.dart`: the file exists only while on
  screen, is refreshed on each tick, and a failure to write is not an error.
- `ios/PreviewTests/FirestorePreviewTests.swift`, `PreviewForegroundTests`: what
  counts as fresh, and reading the file's time from the shared folder.
