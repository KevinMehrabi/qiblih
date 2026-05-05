import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var locationHeadingManager = LocationHeadingManager()

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 28) {
                header

                BearingModeSelector(
                    selection: locationHeadingManager.bearingMode,
                    onSelect: { locationHeadingManager.setBearingMode($0) }
                )

                CompassDial(
                    qiblihAngle: locationHeadingManager.relativeAngle,
                    hasDirection: locationHeadingManager.currentHeading != nil && locationHeadingManager.targetBearing != nil
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
        VStack(spacing: 16) {
            ReadingSection(title: "Your Heading") {
                HStack(spacing: 12) {
                    ReadingTile(
                        title: "True",
                        value: formattedDegrees(locationHeadingManager.currentHeading),
                        footnote: "from true north"
                    )

                    ReadingTile(
                        title: "Magnetic",
                        value: formattedDegrees(locationHeadingManager.currentMagneticHeading),
                        footnote: "from magnetic north"
                    )
                }
            }

            ReadingSection(title: "Qiblih Bearing") {
                HStack(spacing: 12) {
                    ReadingTile(
                        title: "True",
                        value: formattedDegrees(locationHeadingManager.targetBearing),
                        footnote: "\(locationHeadingManager.bearingMode.title) from true north"
                    )

                    ReadingTile(
                        title: "Magnetic",
                        value: formattedDegrees(locationHeadingManager.targetMagneticBearing),
                        footnote: "\(locationHeadingManager.bearingMode.title) from magnetic north"
                    )
                }
            }
        }
    }

    private var statusColor: Color {
        locationHeadingManager.statusText == "Facing the Qiblih" ? .qiblihGold : .primaryText
    }

    private func formattedDegrees(_ degrees: CLLocationDirection?) -> String {
        guard let degrees else {
            return "--"
        }

        let normalizedDegrees = LocationHeadingManager.normalizeDegrees(degrees)
        let roundedDegrees = (normalizedDegrees * 100).rounded() / 100
        let displayDegrees = roundedDegrees >= 360 ? 0 : roundedDegrees

        return "\(Self.degreeFormatter.string(from: NSNumber(value: displayDegrees)) ?? "--")°"
    }

    private static let degreeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

private struct BearingModeSelector: View {
    let selection: BearingMode
    let onSelect: (BearingMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BearingMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(selection == mode ? Color.dialFill : Color.primaryText)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == mode ? Color.primaryText : Color.white.opacity(0.64))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    selection == mode ? Color.primaryText.opacity(0.28) : Color.primaryText.opacity(0.1),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: selection == mode ? .black.opacity(0.18) : .clear,
                            radius: 1,
                            y: selection == mode ? 1 : 0
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
    }
}

private struct CompassDial: View {
    let qiblihAngle: CLLocationDirection
    let hasDirection: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.dialFill)
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
                .padding(18)

            Circle()
                .strokeBorder(Color.primaryText.opacity(0.08), lineWidth: 1)
                .padding(18)

            TickRing()
                .stroke(Color.primaryText.opacity(0.16), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(38)

            QiblihDirectionMarker(angle: hasDirection ? qiblihAngle : nil)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: hasDirection ? qiblihAngle : 0)

            ForwardPointer(isActive: hasDirection)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let angle = hasDirection ? "\(Int(qiblihAngle.rounded())) degrees from phone forward" : "unknown direction"
        return "Qiblih direction. Marker is \(angle)."
    }

}

private struct QiblihDirectionMarker: View {
    let angle: CLLocationDirection?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let angle = angle ?? 0
            let radians = CGFloat(angle - 90) * .pi / 180
            let color = self.angle == nil ? Color.secondaryText.opacity(0.34) : Color.qiblihGold
            let innerRadius = side * 0.435
            let outerRadius = side * 0.49
            let labelRadius = side * 0.505

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
                    .font(.system(size: side * 0.035, weight: .bold, design: .rounded))
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

private struct ForwardPointer: View {
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let color = isActive ? Color.primaryText : Color.secondaryText.opacity(0.32)
            let tip = CGPoint(x: center.x, y: center.y - side * 0.34)
            let headBaseY = tip.y + side * 0.09
            let headHalfWidth = side * 0.05
            let shaftHalfWidth = max(side * 0.011, 4)
            let shaftBottomY = center.y + side * 0.02

            ZStack {
                Path { path in
                    path.move(to: tip)
                    path.addLine(to: CGPoint(x: center.x + headHalfWidth, y: headBaseY))
                    path.addLine(to: CGPoint(x: center.x + shaftHalfWidth, y: headBaseY))
                    path.addLine(to: CGPoint(x: center.x + shaftHalfWidth, y: shaftBottomY))
                    path.addLine(to: CGPoint(x: center.x - shaftHalfWidth, y: shaftBottomY))
                    path.addLine(to: CGPoint(x: center.x - shaftHalfWidth, y: headBaseY))
                    path.addLine(to: CGPoint(x: center.x - headHalfWidth, y: headBaseY))
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

private struct ReadingSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 4)

            content
        }
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
}

private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
