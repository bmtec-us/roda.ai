// Sources/RodaAi/Design/Components/GlassCard.swift
//
// Central Liquid Glass primitives for RodaAi.
//
// Single source of truth for all glass effects in the app. Every feature
// should call into this file rather than using `.glassEffect` directly —
// that keeps the iOS 26 availability gate and the `ultraThinMaterial`
// fallback in one place.
//
// Public API:
//   - GlassCard<Content>            : reusable rounded glass card
//   - GlassContainer<Content>       : wraps GlassEffectContainer (iOS 26+)
//   - .glassShape(_:variant:tint:interactive:)  : universal glass background
//   - .glassID(_:in:)               : scoped morph identifier
//   - GlassEffectVariant            : regular / prominent / clear
//   - GlassNamespaceID              : shared namespace keys for morph scopes
//
import SwiftUI

// MARK: - Variant

/// Abstraction over SwiftUI's `Glass` variants so call sites don't need
/// to reference iOS 26-only types directly.
enum GlassEffectVariant {
    case regular
    case prominent
    case clear
}

// MARK: - Namespace keys

/// Shared identifier keys for scoping glass morph animations per feature.
/// Each top-level view should own its own `@Namespace` and use these as
/// `glassEffectID` keys to prevent cross-feature collisions.
enum GlassNamespaceID: Hashable {
    case composerCapsule
    case composerFileBanner
    case composerImageBanner
    case voiceStateLabel
    case voiceOrbHalo
    case voiceTranscript
    case voiceCancelButton
    case modelCard(String)
}

// MARK: - GlassCard

/// Card com efeito Liquid Glass (iOS 26+) ou material translucido (fallback).
struct GlassCard<Content: View>: View {
    static var cornerRadius: CGFloat { 20 }
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .glassShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}

// MARK: - GlassContainer

/// Wraps `GlassEffectContainer(spacing:)` on iOS 26+, or falls back to a
/// plain container on earlier OS. Use whenever 2+ glass surfaces are
/// visually adjacent so they can blend and morph together.
struct GlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - glassShape modifier

extension View {
    /// Applies a Liquid Glass background in the given shape on iOS 26+,
    /// or an `ultraThinMaterial` fallback on earlier OS.
    ///
    /// - Parameters:
    ///   - shape: any `Shape` (Capsule, Circle, RoundedRectangle, ...).
    ///   - variant: regular / prominent / clear. Ignored on the fallback path.
    ///   - tint: optional tint color (iOS 26+ only).
    ///   - interactive: whether the glass responds to touch/pointer (iOS 26+ only).
    @ViewBuilder
    func glassShape<S: Shape>(
        _ shape: S,
        variant: GlassEffectVariant = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.modifier(
                GlassShapeModifier(
                    shape: shape,
                    variant: variant,
                    tint: tint,
                    interactive: interactive
                )
            )
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(shape)
        }
    }

    /// Wraps `glassEffectID(_:in:)` behind an availability check. No-op on
    /// earlier OS versions.
    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Glass button style helper

/// Abstraction over iOS 26 `.buttonStyle(.glass)` variants so call sites
/// can use a single availability-gated entry point.
enum GlassButtonKind {
    case glass
    case glassProminent
    case glassClear
}

extension View {
    /// Applies a Liquid Glass button style on iOS 26+, or leaves the
    /// button untouched on earlier OS (system default).
    @ViewBuilder
    func glassButtonStyle(_ kind: GlassButtonKind = .glass) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            switch kind {
            case .glass:
                self.buttonStyle(.glass)
            case .glassProminent:
                self.buttonStyle(.glassProminent)
            case .glassClear:
                self.buttonStyle(.glass)
            }
        } else {
            self
        }
    }
}

// MARK: - Private iOS 26 modifier

@available(iOS 26.0, macOS 26.0, *)
private struct GlassShapeModifier<S: Shape>: ViewModifier {
    let shape: S
    let variant: GlassEffectVariant
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(resolvedGlass(), in: shape)
    }

    private func resolvedGlass() -> Glass {
        var glass: Glass
        switch variant {
        case .regular:
            glass = .regular
        case .prominent:
            // `prominent` is exposed via the button style API; use regular
            // with a heavier tint for a surface-level prominent look.
            glass = .regular
        case .clear:
            glass = .clear
        }
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}
