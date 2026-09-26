# Ezan Vakti for macOS

A native Turkish prayer times app for the macOS menu bar, with small and medium desktop widgets. It shows the current prayer period, the next prayer, a live countdown, and all six daily times. Choose any of Istanbul's 39 districts or grant location permission to use your current position within Istanbul.

## Requirements

- macOS 14 or newer
- Internet access when downloading fresh prayer times
- Xcode 15 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build from source

## Run the packaged app

Unzip `EzanVakti-macOS.zip`, then open `EzanVakti.app`. The app appears in the menu bar as a moon with the next prayer and minutes remaining. Click it to see the full schedule and choose a district. In macOS, add the **Ezan Vakti** widget from the desktop or Notification Center widget gallery after opening the app once.

The included app is locally signed for development, not notarized for public distribution. macOS may require you to use **Open** from the Finder context menu on another Mac. For reliable widget data sharing across machines, build and sign both targets with your own Apple development team and enable the App Groups capability for `group.com.halilozel.EzanVakti`.

## Build from source

```sh
brew install xcodegen
xcodegen generate
open EzanVakti.xcodeproj
```

In Xcode, select your development team for both **EzanVakti** and **EzanWidget**. Set unique bundle identifiers and change the shared App Group identifier in both entitlement files and `Shared/PrayerModels.swift` if the existing identifiers are unavailable to your team. Then build and run the **EzanVakti** scheme.

For a local unsigned build:

```sh
xcodebuild -project EzanVakti.xcodeproj -scheme EzanVakti \
  -configuration Release -derivedDataPath work/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## Prayer time source and privacy

Times come from the [AlAdhan calendar API](https://aladhan.com/prayer-times-api), using calculation method 13, labeled **Diyanet İşleri Başkanlığı, Turkey (experimental)** by that service. These are calculated times and should not be described as the official Diyanet timetable. The [official Diyanet API](https://awqatsalah.diyanet.gov.tr/) requires registration and authenticated access.

The app sends the selected district's coordinates, or your current coordinates after you grant location permission, to AlAdhan to retrieve the calendar. Apple's geocoder resolves district names. The downloaded current and next month are cached locally and shared with the widget. There are no analytics or account requirements. When offline, previously downloaded times remain available. The app refreshes cached times after 12 hours when it runs.

## Project layout

- `EzanVakti/App`: menu bar app, location handling, and Turkish interface
- `EzanVakti/Widget`: WidgetKit extension
- `EzanVakti/Shared`: prayer models, Istanbul time calculations, and API client
- `EzanVakti/Tests`: schedule boundary checks

The interface and system permission message are Turkish. Source code, repository history, and documentation are English.
