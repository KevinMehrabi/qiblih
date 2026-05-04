# QiblihCompass

A simple native iOS 17 SwiftUI compass app for facing the Bahá’í Qiblih: the Shrine of Bahá’u’lláh at Bahjí near ‘Akká/Acre.

## Run

Open `QiblihCompass.xcodeproj` in Xcode, choose the `QiblihCompass` scheme, and run on an iPhone or iOS Simulator.

The app uses CoreLocation while in use to calculate the Qiblih bearing to:

- Latitude: `32.9393306`
- Longitude: `35.0886667`

The Qiblih bearing is calculated as an orientation to the fixed Bahjí coordinate in the user's local compass plane. It uses north/east components of Bahjí from the user's current coordinate and does not calculate distance, choose a shortest route, normalize longitude to shorten a path, or allow pole shortcuts.

It uses true heading when available, falls back to magnetic heading as an approximate reading, does not use networking, and does not store location.
