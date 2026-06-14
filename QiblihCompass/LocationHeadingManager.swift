import Combine
import CoreLocation
import Foundation

enum BearingMode: String, CaseIterable, Identifiable {
    case mercator
    case azimuth

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .mercator:
            "Mercator"
        case .azimuth:
            "Azimuth"
        }
    }

    var subtitle: String {
        switch self {
        case .mercator:
            "Traditional"
        case .azimuth:
            "Scientific"
        }
    }
}

final class LocationHeadingManager: NSObject, ObservableObject {
    static let qiblihCoordinate = CLLocationCoordinate2D(
        latitude: 32.9445,
        longitude: 35.0918
    )

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentHeading: CLLocationDirection?
    @Published private(set) var currentMagneticHeading: CLLocationDirection?
    @Published private(set) var bearingMode: BearingMode = .azimuth
    @Published private(set) var targetBearing: CLLocationDirection?
    @Published private(set) var targetMagneticBearing: CLLocationDirection?
    @Published private(set) var relativeAngle: CLLocationDirection = 0
    @Published private(set) var statusText = "Finding the Qiblih"
    @Published private(set) var detailText = "Allow location access and hold the phone flat."
    @Published private(set) var headingAccuracy: CLLocationDirection?
    @Published private(set) var isHeadingCalibrated = false
    @Published private(set) var isUsingApproximateHeading = false
    @Published private(set) var isHeadingUnavailable = !CLLocationManager.headingAvailable()

    private static let calibratedHeadingAccuracy: CLLocationDirection = 35
    private static let poorHeadingAccuracy: CLLocationDirection = 65
    private static let poorHeadingSamplesBeforeRecalibration = 5
    private static let headingJumpThreshold: CLLocationDirection = 55
    private static let headingJumpConfirmationThreshold: CLLocationDirection = 18
    private static let headingJumpConfirmationSamples = 2
    private static let headingJumpResetInterval: TimeInterval = 1.5

    private let locationManager = CLLocationManager()
    private var isCheckingLocationServices = false
    private var hasStartedUpdates = false
    private var poorHeadingSampleCount = 0
    private var smoothedTrueHeading: CLLocationDirection?
    private var smoothedMagneticHeading: CLLocationDirection?
    private var pendingHeadingJump: PendingHeadingJump?

    private struct PendingHeadingJump {
        var trueHeading: CLLocationDirection
        var magneticHeading: CLLocationDirection?
        var sampleCount: Int
        var timestamp: Date
    }

    private struct StabilizedHeading {
        let trueHeading: CLLocationDirection
        let magneticHeading: CLLocationDirection?
        let isHeldEstimate: Bool
    }

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 2
        locationManager.headingOrientation = .portrait
    }

    func requestPermissionAndStartUpdates() {
        switch authorizationStatus {
        case .notDetermined:
            #if os(iOS)
            locationManager.requestWhenInUseAuthorization()
            #else
            locationManager.requestAlwaysAuthorization()
            #endif
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            checkLocationServicesAndStartUpdates()
        #else
        case .authorized, .authorizedAlways:
            checkLocationServicesAndStartUpdates()
        #endif
        case .denied, .restricted:
            statusText = "Location Permission Needed"
            detailText = "Allow location access in Settings to calculate the Qiblih direction."
        @unknown default:
            statusText = "Location Status Unknown"
            detailText = "The app cannot read the current location permission state."
        }
    }

    func setBearingMode(_ mode: BearingMode) {
        guard bearingMode != mode else {
            return
        }

        bearingMode = mode
        updateBearingIfPossible()
    }

    var hasReliableDirection: Bool {
        currentHeading != nil && targetBearing != nil && isHeadingCalibrated
    }

    static func qiblihBearing(from origin: CLLocationCoordinate2D, mode: BearingMode) -> CLLocationDirection {
        switch mode {
        case .mercator:
            mercatorBearing(
                from: origin.latitude,
                lon1: origin.longitude,
                to: qiblihCoordinate.latitude,
                lon2: qiblihCoordinate.longitude
            )
        case .azimuth:
            initialGreatCircleBearing(
                from: origin.latitude,
                lon1: origin.longitude,
                to: qiblihCoordinate.latitude,
                lon2: qiblihCoordinate.longitude
            )
        }
    }

    static func mercatorBearing(
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

    static func mercatorY(_ latitude: Double) -> Double {
        let phi = latitude.radians
        return log(tan(.pi / 4 + phi / 2))
    }

    static func initialGreatCircleBearing(
        from lat1: Double,
        lon1: Double,
        to lat2: Double,
        lon2: Double
    ) -> CLLocationDirection {
        let phi1 = lat1.radians
        let phi2 = lat2.radians
        var deltaLambda = (lon2 - lon1).radians
        if deltaLambda > Double.pi {
            deltaLambda -= 2 * Double.pi
        } else if deltaLambda < -Double.pi {
            deltaLambda += 2 * Double.pi
        }

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        let theta = atan2(y, x)

        return normalizeDegrees(theta.degrees)
    }

    static func relativeAngle(from currentHeading: CLLocationDirection, to targetBearing: CLLocationDirection) -> CLLocationDirection {
        normalizeDegrees(targetBearing - currentHeading)
    }

    static func signedTurnAngle(from relativeAngle: CLLocationDirection) -> CLLocationDirection {
        relativeAngle > 180 ? relativeAngle - 360 : relativeAngle
    }

    static func signedAngleDelta(from start: CLLocationDirection, to end: CLLocationDirection) -> CLLocationDirection {
        signedTurnAngle(from: relativeAngle(from: start, to: end))
    }

    static func interpolatedHeading(
        from start: CLLocationDirection,
        to end: CLLocationDirection,
        fraction: CLLocationDirection
    ) -> CLLocationDirection {
        let boundedFraction = min(max(fraction, 0), 1)
        return normalizeDegrees(start + signedAngleDelta(from: start, to: end) * boundedFraction)
    }

    static func normalizeDegrees(_ degrees: CLLocationDirection) -> CLLocationDirection {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func checkLocationServicesAndStartUpdates() {
        guard !isCheckingLocationServices else {
            return
        }

        isCheckingLocationServices = true
        DispatchQueue.global(qos: .userInitiated).async {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isCheckingLocationServices = false
                guard servicesEnabled else {
                    self.statusText = "Location Services Off"
                    self.detailText = "Turn on Location Services to calculate the direction to Bahjí."
                    return
                }

                self.startUpdates()
            }
        }
    }

    private func startUpdates() {
        guard !hasStartedUpdates else {
            return
        }

        hasStartedUpdates = true
        locationManager.startUpdatingLocation()

        isHeadingUnavailable = !CLLocationManager.headingAvailable()
        if isHeadingUnavailable {
            statusText = "Compass Unavailable"
            detailText = "This device cannot provide your heading."
        } else {
            locationManager.startUpdatingHeading()
        }
    }

    private func updateBearingIfPossible() {
        guard let coordinate = currentLocation?.coordinate else {
            return
        }

        targetBearing = Self.qiblihBearing(from: coordinate, mode: bearingMode)
        updateMagneticBearingIfPossible()
        updateDirectionIfPossible()
    }

    private func updateHeading(from heading: CLHeading) {
        headingAccuracy = heading.headingAccuracy >= 0 ? heading.headingAccuracy : nil
        updateCalibrationState()

        let measuredMagneticHeading = heading.magneticHeading >= 0
            ? Self.normalizeDegrees(heading.magneticHeading)
            : nil

        guard heading.trueHeading >= 0 else {
            currentHeading = nil
            currentMagneticHeading = measuredMagneticHeading
            targetMagneticBearing = nil
            isHeadingCalibrated = false
            poorHeadingSampleCount = 0
            isUsingApproximateHeading = false
            resetStabilizedHeading()
            detailText = "Waiting for your true heading."
            updateDirectionIfPossible()
            return
        }

        let measuredTrueHeading = Self.normalizeDegrees(heading.trueHeading)
        let stabilizedHeading = stabilizedHeading(
            trueHeading: measuredTrueHeading,
            magneticHeading: measuredMagneticHeading,
            accuracy: headingAccuracy,
            timestamp: heading.timestamp
        )

        currentHeading = stabilizedHeading.trueHeading
        currentMagneticHeading = stabilizedHeading.magneticHeading
        isUsingApproximateHeading = stabilizedHeading.isHeldEstimate
        updateMagneticBearingIfPossible()
        updateDirectionIfPossible()
    }

    private func stabilizedHeading(
        trueHeading: CLLocationDirection,
        magneticHeading: CLLocationDirection?,
        accuracy: CLLocationDirection?,
        timestamp: Date
    ) -> StabilizedHeading {
        guard let previousTrueHeading = smoothedTrueHeading else {
            smoothedTrueHeading = trueHeading
            smoothedMagneticHeading = magneticHeading
            pendingHeadingJump = nil
            return StabilizedHeading(
                trueHeading: trueHeading,
                magneticHeading: magneticHeading,
                isHeldEstimate: false
            )
        }

        if let accuracy, accuracy > Self.poorHeadingAccuracy {
            return StabilizedHeading(
                trueHeading: previousTrueHeading,
                magneticHeading: smoothedMagneticHeading ?? magneticHeading,
                isHeldEstimate: true
            )
        }

        let delta = abs(Self.signedAngleDelta(from: previousTrueHeading, to: trueHeading))
        let shouldHoldJump = shouldHoldPossibleHeadingJump(
            trueHeading: trueHeading,
            magneticHeading: magneticHeading,
            delta: delta,
            timestamp: timestamp
        )

        if shouldHoldJump {
            return StabilizedHeading(
                trueHeading: previousTrueHeading,
                magneticHeading: smoothedMagneticHeading ?? magneticHeading,
                isHeldEstimate: true
            )
        }

        let acceptedConfirmedJump = (pendingHeadingJump?.sampleCount ?? 0) >= Self.headingJumpConfirmationSamples
        pendingHeadingJump = nil

        let smoothingFraction = Self.headingSmoothingFraction(
            for: accuracy,
            delta: delta,
            acceptedConfirmedJump: acceptedConfirmedJump
        )

        let smoothedTrueHeading = Self.interpolatedHeading(
            from: previousTrueHeading,
            to: trueHeading,
            fraction: smoothingFraction
        )
        self.smoothedTrueHeading = smoothedTrueHeading

        if let magneticHeading {
            let previousMagneticHeading = smoothedMagneticHeading ?? magneticHeading
            smoothedMagneticHeading = Self.interpolatedHeading(
                from: previousMagneticHeading,
                to: magneticHeading,
                fraction: smoothingFraction
            )
        } else {
            smoothedMagneticHeading = nil
        }

        return StabilizedHeading(
            trueHeading: smoothedTrueHeading,
            magneticHeading: smoothedMagneticHeading,
            isHeldEstimate: false
        )
    }

    private func shouldHoldPossibleHeadingJump(
        trueHeading: CLLocationDirection,
        magneticHeading: CLLocationDirection?,
        delta: CLLocationDirection,
        timestamp: Date
    ) -> Bool {
        guard delta >= Self.headingJumpThreshold else {
            pendingHeadingJump = nil
            return false
        }

        if var pendingHeadingJump,
           timestamp.timeIntervalSince(pendingHeadingJump.timestamp) <= Self.headingJumpResetInterval,
           abs(Self.signedAngleDelta(from: pendingHeadingJump.trueHeading, to: trueHeading)) <= Self.headingJumpConfirmationThreshold {
            pendingHeadingJump.trueHeading = trueHeading
            pendingHeadingJump.magneticHeading = magneticHeading
            pendingHeadingJump.sampleCount += 1
            pendingHeadingJump.timestamp = timestamp
            self.pendingHeadingJump = pendingHeadingJump
            return pendingHeadingJump.sampleCount < Self.headingJumpConfirmationSamples
        }

        pendingHeadingJump = PendingHeadingJump(
            trueHeading: trueHeading,
            magneticHeading: magneticHeading,
            sampleCount: 1,
            timestamp: timestamp
        )
        return true
    }

    private static func headingSmoothingFraction(
        for accuracy: CLLocationDirection?,
        delta: CLLocationDirection,
        acceptedConfirmedJump: Bool
    ) -> CLLocationDirection {
        if acceptedConfirmedJump {
            return 0.45
        }

        guard let accuracy else {
            return 0.16
        }

        if accuracy <= 15 {
            return delta > 30 ? 0.34 : 0.28
        }

        if accuracy <= calibratedHeadingAccuracy {
            return delta > 30 ? 0.26 : 0.2
        }

        return 0.12
    }

    private func resetStabilizedHeading() {
        smoothedTrueHeading = nil
        smoothedMagneticHeading = nil
        pendingHeadingJump = nil
    }

    private func updateCalibrationState() {
        guard let headingAccuracy else {
            poorHeadingSampleCount += 1
            if !isHeadingCalibrated || poorHeadingSampleCount >= Self.poorHeadingSamplesBeforeRecalibration {
                isHeadingCalibrated = false
            }
            return
        }

        if headingAccuracy <= Self.calibratedHeadingAccuracy {
            isHeadingCalibrated = true
            poorHeadingSampleCount = 0
        } else if headingAccuracy > Self.poorHeadingAccuracy {
            poorHeadingSampleCount += 1
            if !isHeadingCalibrated || poorHeadingSampleCount >= Self.poorHeadingSamplesBeforeRecalibration {
                isHeadingCalibrated = false
            }
        } else if isHeadingCalibrated {
            poorHeadingSampleCount = 0
        }
    }

    private func updateMagneticBearingIfPossible() {
        guard let targetBearing, let currentHeading, let currentMagneticHeading else {
            targetMagneticBearing = nil
            return
        }

        let declination = currentHeading - currentMagneticHeading
        targetMagneticBearing = Self.normalizeDegrees(targetBearing - declination)
    }

    private func updateDirectionIfPossible() {
        guard let currentHeading, let targetBearing else {
            if hasLocationAuthorization {
                statusText = "Finding the Qiblih"
                if isHeadingUnavailable {
                    detailText = "This device cannot provide your heading."
                } else if currentHeading == nil, targetBearing != nil {
                    detailText = "Waiting for your true heading."
                } else {
                    detailText = "Waiting for location and compass readings."
                }
            }
            return
        }

        let turnAngle = Self.relativeAngle(from: currentHeading, to: targetBearing)
        let signedAngle = Self.signedTurnAngle(from: turnAngle)
        relativeAngle = turnAngle

        guard isHeadingCalibrated else {
            statusText = "Calibrate Compass"
            detailText = calibrationDetailText
            return
        }

        if abs(signedAngle) < 1 {
            statusText = "Facing the Qiblih"
        } else if signedAngle < 0 {
            statusText = "Turn left"
        } else {
            statusText = "Turn right"
        }

        detailText = ""
    }

    private var calibrationDetailText: String {
        guard let headingAccuracy else {
            return "Move iPhone in a figure eight away from metal or magnets."
        }

        let roundedAccuracy = Int(headingAccuracy.rounded())
        return "Move iPhone in a figure eight away from metal or magnets. Accuracy ±\(roundedAccuracy)°."
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
            detailText = "This device cannot provide your heading reliably right now."
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
