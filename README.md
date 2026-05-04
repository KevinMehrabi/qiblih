# QiblihCompass

A simple native iOS 17 SwiftUI compass app for facing the Bahá’í Qiblih: the Shrine of Bahá’u’lláh at Bahjí near ‘Akká/Acre.

## Run

Open `QiblihCompass.xcodeproj` in Xcode, choose the `QiblihCompass` scheme, and run on an iPhone or iOS Simulator.

The app uses CoreLocation while in use to calculate the Qiblih bearing to:

- Latitude: `32.9445`
- Longitude: `35.0918`

The app lets the user choose between a Mercator-map bearing and an initial great-circle bearing, also called the forward azimuth. It does not use CoreLocation course or distance-based bearing logic.

It uses true heading for direction guidance, displays the user's heading and Qiblih bearing from both true north and magnetic north, does not use networking, and does not store location.
