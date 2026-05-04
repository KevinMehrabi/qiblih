# QiblihCompass

A simple native iOS 17 SwiftUI compass app for facing the Bahá’í Qiblih: the Shrine of Bahá’u’lláh at Bahjí near ‘Akká/Acre.

## Run

Open `QiblihCompass.xcodeproj` in Xcode, choose the `QiblihCompass` scheme, and run on an iPhone or iOS Simulator.

The app uses CoreLocation while in use to calculate the Qiblih bearing to:

- Latitude: `32.9445`
- Longitude: `35.0918`

The Qiblih bearing is calculated as a rhumb-line bearing, which is a constant azimuth and appears as a straight line on a Mercator map. The app does not use great-circle, geodesic, CoreLocation course, or distance-based bearing logic.

It uses true heading only, does not fall back to magnetic heading, does not use networking, and does not store location.
