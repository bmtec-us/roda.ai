// Sources/RodaAi/Features/Voice/VoiceWaveform.swift
//
// Orbe animado estilo ChatGPT voice mode.
// Reage ao estado de voz com pulsos, ondulacoes e brilho.
import SwiftUI

struct VoiceOrb: View {
    let state: VoiceOrbState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum VoiceOrbState: Equatable {
        case idle
        case listening
        case processing
        case speaking
        case error
    }

    private var baseSize: CGFloat { 200 }

    var body: some View {
        if reduceMotion {
            staticOrb
        } else {
            animatedOrb
        }
    }

    // MARK: - Static (Reduce Motion)

    private var staticOrb: some View {
        Circle()
            .fill(orbGradient)
            .frame(width: baseSize, height: baseSize)
            .shadow(color: glowColor.opacity(0.5), radius: 30)
    }

    // MARK: - Animated Orb

    private var animatedOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = baseSize / 2

                // Layer 1: Outer glow (large, blurred)
                let outerPulse = pulseAmount(t: t, speed: 0.8, range: 0.15)
                let outerRadius = radius * (1.3 + outerPulse)
                drawGlowLayer(
                    context: &context,
                    center: center,
                    radius: outerRadius,
                    color: glowColor.opacity(0.1 + breathe(t: t, speed: 0.5) * 0.08),
                    blur: 40
                )

                // Layer 2: Middle glow ring
                let midPulse = pulseAmount(t: t, speed: 1.2, range: 0.1)
                let midRadius = radius * (1.12 + midPulse)
                drawGlowLayer(
                    context: &context,
                    center: center,
                    radius: midRadius,
                    color: glowColor.opacity(0.2 + breathe(t: t, speed: 0.7) * 0.1),
                    blur: 20
                )

                // Layer 3: Core orb
                let corePulse = pulseAmount(t: t, speed: 1.5, range: 0.05)
                let coreRadius = radius * (1.0 + corePulse)

                // Draw morphed core with slight distortion
                var corePath = Path()
                let segments = 120
                for i in 0..<segments {
                    let angle = (Double(i) / Double(segments)) * 2 * .pi
                    let distortion = morphDistortion(angle: angle, t: t)
                    let r = coreRadius * (1.0 + distortion)
                    let point = CGPoint(
                        x: center.x + cos(angle) * r,
                        y: center.y + sin(angle) * r
                    )
                    if i == 0 {
                        corePath.move(to: point)
                    } else {
                        corePath.addLine(to: point)
                    }
                }
                corePath.closeSubpath()

                // Gradient fill
                let gradientColors: [Color] = orbColors(t: t)
                let gradient = Gradient(colors: gradientColors)
                let shading = GraphicsContext.Shading.radialGradient(
                    gradient,
                    center: CGPoint(
                        x: center.x + sin(t * 0.3) * radius * 0.15,
                        y: center.y + cos(t * 0.4) * radius * 0.15
                    ),
                    startRadius: 0,
                    endRadius: coreRadius * 1.2
                )

                context.fill(corePath, with: shading)

                // Inner specular highlight
                let highlightCenter = CGPoint(
                    x: center.x - coreRadius * 0.2,
                    y: center.y - coreRadius * 0.25
                )
                let highlight = Path(ellipseIn: CGRect(
                    x: highlightCenter.x - coreRadius * 0.3,
                    y: highlightCenter.y - coreRadius * 0.2,
                    width: coreRadius * 0.6,
                    height: coreRadius * 0.4
                ))
                context.fill(highlight, with: .color(.white.opacity(0.08 + breathe(t: t, speed: 0.6) * 0.04)))
            }
            .frame(width: baseSize * 1.8, height: baseSize * 1.8)
        }
    }

    // MARK: - Animation Helpers

    private func pulseAmount(t: Double, speed: Double, range: Double) -> Double {
        switch state {
        case .idle:
            return sin(t * speed) * range * 0.3
        case .listening:
            return sin(t * speed * 2.5) * range * 1.5
        case .processing:
            return sin(t * speed * 3.0) * range * 0.8
        case .speaking:
            return sin(t * speed * 1.8) * range * 1.2 + cos(t * speed * 2.3) * range * 0.4
        case .error:
            return 0
        }
    }

    private func breathe(t: Double, speed: Double) -> Double {
        (sin(t * speed) + 1.0) / 2.0
    }

    private func morphDistortion(angle: Double, t: Double) -> Double {
        switch state {
        case .idle:
            return sin(angle * 3 + t * 0.5) * 0.01
        case .listening:
            return sin(angle * 4 + t * 3) * 0.04 + cos(angle * 6 + t * 2) * 0.025
        case .processing:
            return sin(angle * 5 + t * 4) * 0.03 + sin(angle * 7 - t * 3) * 0.02
        case .speaking:
            return sin(angle * 3 + t * 2) * 0.05 + cos(angle * 5 + t * 2.5) * 0.03
        case .error:
            return 0
        }
    }

    private func orbColors(t: Double) -> [Color] {
        switch state {
        case .idle:
            return [
                .green.opacity(0.6),
                .cyan.opacity(0.4),
                .green.opacity(0.3),
            ]
        case .listening:
            let shift = sin(t * 1.5) * 0.15
            return [
                .green.opacity(0.8 + shift),
                .cyan.opacity(0.6),
                .blue.opacity(0.4 - shift),
            ]
        case .processing:
            let shift = sin(t * 2) * 0.1
            return [
                .blue.opacity(0.7 + shift),
                .purple.opacity(0.5),
                .cyan.opacity(0.4 - shift),
            ]
        case .speaking:
            let shift = sin(t * 1.2) * 0.1
            return [
                .green.opacity(0.9 + shift),
                .teal.opacity(0.6),
                .mint.opacity(0.4 - shift),
            ]
        case .error:
            return [
                .red.opacity(0.7),
                .orange.opacity(0.4),
                .red.opacity(0.3),
            ]
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle: return .green
        case .listening: return .cyan
        case .processing: return .blue
        case .speaking: return .green
        case .error: return .red
        }
    }

    private var orbGradient: some ShapeStyle {
        RadialGradient(
            colors: orbColors(t: 0),
            center: .center,
            startRadius: 0,
            endRadius: baseSize / 2
        )
    }

    private func drawGlowLayer(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        blur: CGFloat
    ) {
        var glowContext = context
        glowContext.addFilter(.blur(radius: blur))
        let circle = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        glowContext.fill(circle, with: .color(color))
    }
}
