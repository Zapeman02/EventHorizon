import QuickLookThumbnailing
import SwiftUI

struct ItemView: View {
    let item: ShelfItem
    let onRemove: () -> Void
    let onDragChanged: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            stack
                .shadow(color: Palette.ember.opacity(hovering ? 0.8 : 0), radius: 10)
            Text(item.title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 60)
        }
        .scaleEffect(hovering ? 1.06 : 1)
        .overlay {
            FileDragSource(urls: item.urls,
                           onHover: { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } },
                           onDragChanged: onDragChanged,
                           onRemove: onRemove)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, Palette.ember)
                }
                .buttonStyle(.plain)
                .offset(x: -2, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var stack: some View {
        ZStack {
            ForEach(Array(item.urls.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                Thumbnail(url: url, size: 44)
                    .rotationEffect(.degrees(Double(index) * (hovering ? 9 : 6)))
                    .offset(x: CGFloat(index) * (hovering ? 5 : 3))
            }
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .bottomTrailing) {
            if item.urls.count > 1 {
                Text("\(item.urls.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Palette.flare, in: Capsule())
                    .offset(x: 6, y: 3)
            }
        }
    }
}

struct SuckedInIcon: View {
    let url: URL
    let start: CGSize
    @State private var progress: CGFloat = 0

    var body: some View {
        Thumbnail(url: url, size: 40)
            .modifier(SpiralEffect(progress: progress, start: start))
            .onAppear { withAnimation(.easeIn(duration: NotchState.absorbDuration)) { progress = 1 } }
    }
}

/// Moves a view along an inward spiral into its center while spinning and shrinking to nothing.
struct SpiralEffect: GeometryEffect {
    var progress: CGFloat
    let start: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = progress * .pi * 1.8
        let remaining = 1 - progress
        let x = (start.width * cos(angle) - start.height * sin(angle)) * remaining
        let y = (start.width * sin(angle) + start.height * cos(angle)) * remaining
        let scale = max(0.001, remaining)
        let transform = CGAffineTransform(translationX: x + size.width / 2, y: y + size.height / 2)
            .rotated(by: angle * 1.5)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

struct Thumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: size, height: size)
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                           scale: 2, representationTypes: .thumbnail)
                image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
    }
}
