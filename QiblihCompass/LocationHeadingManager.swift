import Combine
import CoreLocation
import Foundation

final class LocationHeadingManager: NSObject, ObservableObject {
    private enum QiblihDirectionRule {
        case fixedCoordinateLocalPlaneNoRoute
    }

    static let qiblihCoordinate = CLLocationCoordinate2D(
        latitude: 32.9393306,
        longitude: 35.0886667
    )

    private static let qiblihDirectionRule: QiblihDirectionRule = .fixedCoordinateLocalPlaneNoRoute

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
        bearing(from: origin, to: qiblihCoordinate, rule: qiblihDirectionRule)
    }

    private static func bearing(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        rule: QiblihDirectionRule
    ) -> CLLocationDirection {
        switch rule {
        case .fixedCoordinateLocalPlaneNoRoute:
            return fixedCoordinateLocalPlaneBearing(from: origin, to: destination)
        }
    }

    private static func fixedCoordinateLocalPlaneBearing(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let originLatitude = origin.latitude.radians
        let originLongitude = origin.longitude.radians
        let destinationLatitude = destination.latitude.radians
        let destinationLongitude = destination.longitude.radians
        let deltaLongitude = destinationLongitude - originLongitude

        // Orientation only: no distance, no route choice, no longitude normalization.
        let eastComponent = cos(destinationLatitude) * sin(deltaLongitude)
        let northComponent = cos(originLatitude) * sin(destinationLatitude)
            - sin(originLatitude) * cos(destinationLatitude) * cos(deltaLongitude)
        let theta = atan2(eastComponent, northComponent)

        return normalizeDegrees(theta.degrees)
    }

    static func signedTurnAngle(from currentHeading: CLLocationDirection, to targetBearing: CLLocationDirection) -> CLLocationDirection {
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

        targetBearing = Self.qiblihBearing(from: coordinate)
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

        let signedAngle = Self.signedTurnAngle(from: currentHeading, to: targetBearing)
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
