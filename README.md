# QiblihCompass

A simple native iOS 17 SwiftUI compass app for facing the Bahá’í Qiblih: the Shrine of Bahá’u’lláh at Bahjí near ‘Akká/Acre.

## Run

Open `QiblihCompass.xcodeproj` in Xcode, choose the `QiblihCompass` scheme, and run on an iPhone or iOS Simulator.

The app uses CoreLocation while in use to calculate the flat-map bearing to:

- Latitude: `32.9393306`
- Longitude: `35.0886667`

The Qiblih bearing is calculated by projecting the user's current coordinate and Bahjí onto a Mercator-style flat map, then using the straight-line map direction between those two points. It does not use a great-circle bearing.

It uses true heading when available, falls back to magnetic heading as an approximate reading, does not use networking, and does not store location.
