# Push notifications

Two kinds of images. The **settings** images are Flutter renders of the real
screen (`TZ=UTC flutter test scripts/render/render_screens_test.dart --name
settings-notifications`). The other images are **illustrations**. iOS and
Android draw notifications and icon badges themselves, so no Flutter render can
show them. They follow each system's layout for a titled alert, using the
app's real icon files (`assets/icon/fireplace_ios.png` and the generated
`ic_notification`). Fonts are approximate (Segoe UI stands in for the system
fonts). Usernames are fictional.

What a phone shows: the Fireplace icon on the left, the sender's username as the
title, and **New Message** below it. Each conversation keeps one alert, which
later alerts replace.

| Surface | Light | Dark |
| --- | --- | --- |
| iOS lock screen | [light](ios-lock-screen-light.png) | [dark](ios-lock-screen-dark.png) |
| iOS, "Show sender's name" off | [light](ios-hidden-name-light.png) | [dark](ios-hidden-name-dark.png) |
| Android shade and status-bar flame | [light](android-shade-light.png) | [dark](android-shade-dark.png) |
| App icon badge (iOS) | [image](ios-app-icon-badge.png) | |
| Settings → Notifications (render) | [light](settings-light.png) | [dark](settings-dark.png) |
