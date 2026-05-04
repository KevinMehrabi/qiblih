# QiblihCompass

A simple native iOS 17 SwiftUI compass app for facing the Bahá’í Qiblih: the Shrine of Bahá’u’lláh at Bahjí near ‘Akká/Acre.

## Run

Open `QiblihCompass.xcodeproj` in Xcode, choose the `QiblihCompass` scheme, and run on an iPhone or iOS Simulator.

The app uses CoreLocation while in use to calculate the flat-map bearing to:

- Latitude: `32.9393306`
- Longitude: `35.0886667`

The Qiblih bearing is calculated from the straight-line direction on a simple flat world map: longitude is horizontal, latitude is vertical, and the vector runs from the user's current coordinate to Bahjí. It does not use a great-circle bearing or Mercator latitude stretching.

It uses true heading when available, falls back to magnetic heading as an approximate reading, does not use networking, and does not store location.
