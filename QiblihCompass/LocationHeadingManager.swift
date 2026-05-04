import Combine
import CoreLocation
import Foundation

final class LocationHeadingManager: NSObject, ObservableObject {
    static let qiblihCoordinate = CLLocationCoordinate2D(
        latitude: 32.9393306,
        longitude: 35.0886667
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

    static func bearing(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDirection {
        let phi1 = origin.latitude.radians
        let lambda1 = origin.longitude.radians
        let phi2 = destination.latitude.radians
        let lambda2 = destination.longitude.radians
        let deltaLambda = lambda2 - lambda1

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        let theta = atan2(y, x)

        return normalizeDegrees(theta.degrees)
    }

    static func shortestSignedAngle(from currentHeading: CLLocationDirection, to targetBearing: CLLocationDirection) -> CLLocationDirection {
        let delta = normalizeDegrees(targetBearing - currentHeading + 180) - 180
        return delta == -180 ? 180 : delta
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

        targetBearing = Self.bearing(from: coordinate, to: Self.qiblihCoordinate)
        updateDirectionIfPossible()
    }

    private func updateHeading(from heading: CLHeading) {
        if heading.trueHeading >= 0 {
            currentHeading = Self.normalizeDegrees(heading.trueHeading)
            isUsingApproximateHeading = false
        } else if heading.magneticHeading >= 0 {
            currentHeading = Self.normalizeDegrees(heading.magneticHeading)
            isUsingApproximateHeading = true
        } else {
            currentHeading = nil
            isUsingApproximateHeading = true
            detailText = "The compass heading is not available yet."
        }

        updateDirectionIfPossible()
    }

    private func updateDirectionIfPossible() {
        guard let currentHeading, let targetBearing else {
            if hasLocationAuthorization {
                statusText = "Finding the Qiblih"
                detailText = isHeadingUnavailable
                    ? "This device does not provide heading updates."
                    : "Waiting for location and compass readings."
            }
            return
        }

        let signedAngle = Self.shortestSignedAngle(from: currentHeading, to: targetBearing)
        relativeAngle = signedAngle

        if abs(signedAngle) <= 3 {
            statusText = "Facing the Qiblih"
        } else if signedAngle < 0 {
            statusText = "Turn left"
        } else {
            statusText = "Turn right"
        }

        detailText = isUsingApproximateHeading
            ? "Approximate: using magnetic heading."
            : "Using true heading."
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
