import SwiftUI

enum Palette {
    static let ember = Color(red: 1.0, green: 0.33, blue: 0.04)
    static let flare = Color(red: 1.0, green: 0.62, blue: 0.16)
    static let core = Color(red: 1.0, green: 0.9, blue: 0.7)
}

/// Gargantua-style black hole: lensed halo, tilted accretion disk, pitch-black event horizon.
struct BlackHoleView: View {
    var diameter: CGFloat
    var intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let spin = Angle.radians(t * (1.4 + intensity * 3))
            let pulse = 1 + 0.04 * intensity * sin(t * 5)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.ember.opacity(0.5 * intensity), .clear],
                                         center: .center, startRadius: diameter * 0.2, endRadius: diameter * 0.75))
                    .frame(width: diameter * 1.5, height: diameter * 1.5)

                ring(width: diameter * 0.62, line: diameter * 0.07)
                    .rotationEffect(-spin)
                    .blur(radius: diameter * 0.03)

                disk
                    .rotationEffect(spin)
                    .scaleEffect(x: 1, y: 0.26)
                    .blur(radius: diameter * 0.015)

                Circle()
                    .fill(.black)
                    .frame(width: diameter * 0.42)
                    .shadow(color: Palette.ember.opacity(intensity), radius: diameter * 0.06)

                Circle()
                    .stroke(Palette.core.opacity(0.9), lineWidth: max(0.6, diameter * 0.012))
                    .frame(width: diameter * 0.45)
                    .blur(radius: 0.5)

                disk
                    .rotationEffect(spin)
                    .scaleEffect(x: 1, y: 0.26)
                    .mask(Rectangle().frame(height: diameter / 2).offset(y: diameter / 4))
            }
            .scaleEffect(pulse)
            .frame(width: diameter, height: diameter)
        }
        .allowsHitTesting(false)
    }

    private var disk: some View {
        ring(width: diameter, line: diameter * 0.2)
    }

    private func ring(width: CGFloat, line: CGFloat) -> some View {
        Circle()
            .strokeBorder(AngularGradient(colors: [.clear, Palette.ember, Palette.flare, Palette.core, Palette.flare,
                                                   Palette.ember, .clear, Palette.ember.opacity(0.6), .clear],
                                          center: .center),
                          lineWidth: line)
            .frame(width: width, height: width)
    }
}

/// Thin light rim tracing the notch's lower edge.
struct EnergyRim: View {
    var radius: CGFloat
    var intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            NotchShape(radius: radius)
                .stroke(AngularGradient(colors: [Palette.ember, Palette.core, Palette.flare, .clear, Palette.ember],
                                        center: .center, angle: .radians(t * 2)),
                        lineWidth: 1.5)
                .opacity(intensity)
                .mask(LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
        }
        .allowsHitTesting(false)
    }
}
