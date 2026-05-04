import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var locationHeadingManager = LocationHeadingManager()

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 28) {
                header

                CompassDial(
                    currentHeading: locationHeadingManager.currentHeading,
                    targetBearing: locationHeadingManager.targetBearing
                )
                .frame(maxWidth: 360)

                readings

                VStack(spacing: 8) {
                    Text(locationHeadingManager.statusText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.center)

                    Text(locationHeadingManager.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
        }
        .onAppear {
            locationHeadingManager.requestPermissionAndStartUpdates()
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            Text("Qiblih Compass")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.center)

            Text("Bahjí, near ‘Akká")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.secondaryText)
        }
    }

    private var readings: some View {
        HStack(spacing: 12) {
            ReadingTile(
                title: "Heading",
                value: formattedWholeDegrees(locationHeadingManager.currentHeading),
                footnote: headingFootnote
            )

            ReadingTile(
                title: "Qiblih Bearing",
                value: formattedPreciseDegrees(locationHeadingManager.targetBearing),
                footnote: "fixed point"
            )
        }
    }

    private var statusColor: Color {
        locationHeadingManager.statusText == "Facing the Qiblih" ? .qiblihGold : .primaryText
    }

    private var headingFootnote: String {
        guard locationHeadingManager.currentHeading != nil else {
            return "waiting"
        }

        return locationHeadingManager.isUsingApproximateHeading ? "magnetic" : "true"
    }

    private func formattedWholeDegrees(_ degrees: CLLocationDirection?) -> String {
        guard let degrees else {
            return "--"
        }

        let roundedDegrees = Int(degrees.rounded()) % 360
        return "\(roundedDegrees)°"
    }

    private func formattedPreciseDegrees(_ degrees: CLLocationDirection?) -> String {
        guard let degrees else {
            return "--"
        }

        return "\(Self.bearingFormatter.string(from: NSNumber(value: degrees)) ?? "--")°"
    }

    private static let bearingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct CompassDial: View {
    let currentHeading: CLLocationDirection?
    let targetBearing: CLLocationDirection?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.dialFill)
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)

            Circle()
                .strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1)

            TickRing()
                .stroke(Color.primaryText.opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(22)

            CardinalLabels()
                .padding(34)

            QiblihBearingMarker(bearing: targetBearing)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: targetBearing ?? 0)

            FacingMarker(heading: currentHeading)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentHeading ?? 0)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let heading = currentHeading.map { "\(Int($0.rounded())) degrees" } ?? "unknown heading"
        let bearing = targetBearing.map { "\(Int($0.rounded())) degrees" } ?? "unknown Qiblih bearing"
        return "Compass. Current heading \(heading). Qiblih bearing \(bearing)."
    }

}

private struct QiblihBearingMarker: View {
    let bearing: CLLocationDirection?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let bearing = bearing ?? 0
            let radians = CGFloat(bearing - 90) * .pi / 180
            let color = self.bearing == nil ? Color.secondaryText.opacity(0.38) : Color.qiblihGold
            let innerRadius = side * 0.47
            let outerRadius = side * 0.515
            let labelRadius = side * 0.43

            ZStack {
                Path { path in
                    path.move(
                        to: CGPoint(
                            x: center.x + cos(radians) * innerRadius,
                            y: center.y + sin(radians) * innerRadius
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: center.x + cos(radians) * outerRadius,
                            y: center.y + sin(radians) * outerRadius
                        )
                    )
                }
                .stroke(color, style: StrokeStyle(lineWidth: max(side * 0.018, 6), lineCap: .round))

                Text("Q")
                    .font(.system(size: side * 0.04, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .position(
                        x: center.x + cos(radians) * labelRadius,
                        y: center.y + sin(radians) * labelRadius
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct FacingMarker: View {
    let heading: CLLocationDirection?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let heading = heading ?? 0
            let radians = CGFloat(heading - 90) * .pi / 180
            let color = self.heading == nil ? Color.secondaryText.opacity(0.32) : Color.primaryText
            let shaftWidth = max(side * 0.018, 6)
            let tipRadius = side * 0.35
            let headLength = side * 0.09
            let headHalfWidth = side * 0.045
            let unit = CGPoint(x: cos(radians), y: sin(radians))
            let perpendicular = CGPoint(x: -unit.y, y: unit.x)
            let tip = CGPoint(
                x: center.x + unit.x * tipRadius,
                y: center.y + unit.y * tipRadius
            )
            let headBase = CGPoint(
                x: tip.x - unit.x * headLength,
                y: tip.y - unit.y * headLength
            )
            let shaftEnd = CGPoint(
                x: headBase.x - unit.x * (shaftWidth * 0.3),
                y: headBase.y - unit.y * (shaftWidth * 0.3)
            )
            let headLeft = CGPoint(
                x: headBase.x + perpendicular.x * headHalfWidth,
                y: headBase.y + perpendicular.y * headHalfWidth
            )
            let headRight = CGPoint(
                x: headBase.x - perpendicular.x * headHalfWidth,
                y: headBase.y - perpendicular.y * headHalfWidth
            )

            ZStack {
                Path { path in
                    path.move(to: center)
                    path.addLine(to: shaftEnd)
                }
                .stroke(color.opacity(0.78), style: StrokeStyle(lineWidth: shaftWidth, lineCap: .round))

                Path { path in
                    path.move(to: tip)
                    path.addLine(to: headLeft)
                    path.addLine(to: headRight)
                    path.closeSubpath()
                }
                .fill(color)

                Circle()
                    .fill(Color.dialFill)
                    .frame(width: side * 0.075, height: side * 0.075)
                    .overlay {
                        Circle()
                            .stroke(color.opacity(0.78), lineWidth: max(side * 0.012, 3))
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct CardinalLabels: View {
    private let labels: [(text: String, bearing: CLLocationDirection)] = [
        ("N", 0),
        ("E", 90),
        ("S", 180),
        ("W", 270)
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = side / 2
            let radius = (side / 2) - 18

            ZStack {
                ForEach(labels, id: \.text) { label in
                    let radians = CGFloat(label.bearing - 90) * .pi / 180

                    Text(label.text)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(label.text == "N" ? Color.northRed : Color.secondaryText)
                        .position(
                            x: center + cos(radians) * radius,
                            y: center + sin(radians) * radius
                        )
                }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct TickRing: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()
        for tick in 0..<72 {
            let angle = CGFloat(Double(tick) * 5 - 90) * .pi / 180
            let isMajor = tick.isMultiple(of: 6)
            let tickLength: CGFloat = isMajor ? 14.0 : 7.0
            let outerPoint = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let innerPoint = CGPoint(
                x: center.x + cos(angle) * (radius - tickLength),
                y: center.y + sin(angle) * (radius - tickLength)
            )

            path.move(to: innerPoint)
            path.addLine(to: outerPoint)
        }

        return path
    }
}

private struct ReadingTile: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.primaryText)

            Text(footnote)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.secondaryText.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primaryText.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.backgroundTop, .backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private extension Color {
    static let backgroundTop = Color(red: 0.97, green: 0.98, blue: 0.96)
    static let backgroundBottom = Color(red: 0.88, green: 0.94, blue: 0.93)
    static let dialFill = Color(red: 0.99, green: 0.99, blue: 0.97)
    static let primaryText = Color(red: 0.10, green: 0.16, blue: 0.18)
    static let secondaryText = Color(red: 0.34, green: 0.44, blue: 0.45)
    static let qiblihGold = Color(red: 0.74, green: 0.54, blue: 0.18)
    static let northRed = Color(red: 0.72, green: 0.18, blue: 0.18)
}

private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
