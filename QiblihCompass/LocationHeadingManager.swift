import Combine
import CoreLocation
import Foundation

final class LocationHeadingManager: NSObject, ObservableObject {
    static let qiblihCoordinate = CLLocationCoordinate2D(
        latitude: 32.9445,
        longitude: 35.0918
    )

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentHeading: CLLocationDirection?
    @Published private(set) var targetBearing: CLLocationDirection?
    @Published private(set) var relativeAngle: CLLocationDirection = 0
    @Published private(set) var statusText = "Finding the Qiblih"
    @Published private(set) var detailText = "Allow location access and hold the phone flat."
    @Published private(set) var isUsingApproximateHeading = false
    @Published private(set) var isHeadingUnavailable = !CLLocationManager.headingAvailable()

    private let locationManager = CLLocationManager()

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 1
        locationManager.headingOrientation = .portrait
    }

    func requestPermissionAndStartUpdates() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusText = "Location Services Off"
            detailText = "Turn on Location Services to calculate the direction to Bahjí."
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            #if os(iOS)
            locationManager.requestWhenInUseAuthorization()
            #else
            locationManager.requestAlwaysAuthorization()
            #endif
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        #else
        case .authorized, .authorizedAlways:
            startUpdates()
        #endif
        case .denied, .restricted:
            statusText = "Location Permission Needed"
            detailText = "Allow location access in Settings to calculate the Qiblih direction."
        @unknown default:
            statusText = "Location Status Unknown"
            detailText = "The app cannot read the current location permission state."
        }
    }

    static func qiblihBearing(from origin: CLLocationCoordinate2D) -> CLLocationDirection {
        projectedBearing(
            from: origin.latitude,
            lon1: origin.longitude,
            to: qiblihCoordinate.latitude,
            lon2: qiblihCoordinate.longitude
        )
    }

    static func mercatorY(_ latitude: Double) -> Double {
        let phi = latitude.radians
        return log(tan(.pi / 4 + phi / 2))
    }

    static func projectedBearing(
        from lat1: Double,
        lon1: Double,
        to lat2: Double,
        lon2: Double
    ) -> CLLocationDirection {
        let x1 = lon1.radians
        let y1 = mercatorY(lat1)
        let x2 = lon2.radians
        let y2 = mercatorY(lat2)

        var dx = x2 - x1
        let dy = y2 - y1

        if abs(dx) > .pi {
            dx = dx > 0
                ? dx - 2 * .pi
                : dx + 2 * .pi
        }

        let theta = atan2(dx, dy)

        return normalizeDegrees(theta.degrees)
    }

    static func relativeAngle(from currentHeading: CLLocationDirection, to targetBearing: CLLocationDirection) -> CLLocationDirection {
        normalizeDegrees(targetBearing - currentHeading)
    }

    static func signedTurnAngle(from relativeAngle: CLLocationDirection) -> CLLocationDirection {
        relativeAngle > 180 ? relativeAngle - 360 : relativeAngle
    }

    static func normalizeDegrees(_ degrees: CLLocationDirection) -> CLLocationDirection {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func startUpdates() {
        locationManager.startUpdatingLocation()

        isHeadingUnavailable = !CLLocationManager.headingAvailable()
        if isHeadingUnavailable {
            statusText = "Compass Unavailable"
            detailText = "This device does not provide heading updates."
        } else {
            locationManager.startUpdatingHeading()
        }
    }

    private func updateBearingIfPossible() {
        guard let coordinate = currentLocation?.coordinate else {
            return
        }

        targetBearing = Self.qiblihBearing(from: coordinate)
        updateDirectionIfPossible()
    }

    private func updateHeading(from heading: CLHeading) {
        guard heading.trueHeading >= 0 else {
            currentHeading = nil
            isUsingApproximateHeading = false
            detailText = "Waiting for true heading."
            updateDirectionIfPossible()
            return
        }

        currentHeading = Self.normalizeDegrees(heading.trueHeading)
        isUsingApproximateHeading = false
        updateDirectionIfPossible()
    }

    private func updateDirectionIfPossible() {
        guard let currentHeading, let targetBearing else {
            if hasLocationAuthorization {
                statusText = "Finding the Qiblih"
                if isHeadingUnavailable {
                    detailText = "This device does not provide heading updates."
                } else if currentHeading == nil, targetBearing != nil {
                    detailText = "Waiting for true heading."
                } else {
                    detailText = "Waiting for location and compass readings."
                }
            }
            return
        }

        let turnAngle = Self.relativeAngle(from: currentHeading, to: targetBearing)
        let signedAngle = Self.signedTurnAngle(from: turnAngle)
        relativeAngle = turnAngle

        if abs(signedAngle) <= 3 {
            statusText = "Facing the Qiblih"
        } else if signedAngle < 0 {
            statusText = "Turn left"
        } else {
            statusText = "Turn right"
        }

        detailText = "Using true heading."
    }

    private var hasLocationAuthorization: Bool {
        #if os(iOS)
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #else
        authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
        #endif
    }
}

extension LocationHeadingManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        requestPermissionAndStartUpdates()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else {
            return
        }

        currentLocation = location
        updateBearingIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        updateHeading(from: newHeading)
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationError = error as? CLError else {
            detailText = "Location update failed. Try again in a moment."
            return
        }

        switch locationError.code {
        case .denied:
            statusText = "Location Permission Needed"
            detailText = "Allow location access in Settings to calculate the Qiblih direction."
        case .headingFailure:
            isHeadingUnavailable = true
            statusText = "Compass Unavailable"
            detailText = "This device cannot provide a reliable heading right now."
        default:
            detailText = "Location update failed. Try again in a moment."
        }
    }
}

private extension Double {
    var radians: Double {
        self * .pi / 180
    }

    var degrees: Double {
        self * 180 / .pi
    }
}
