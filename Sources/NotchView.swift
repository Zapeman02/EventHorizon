import SwiftUI

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var shelf: Shelf

    var body: some View {
        let size = state.size
        ZStack(alignment: .top) {
            Group {
                NotchShape(radius: cornerRadius)
                    .fill(.black)
                    .shadow(color: Palette.ember.opacity(glowOpacity), radius: glowRadius)
                    .shadow(color: Palette.flare.opacity(glowOpacity * 0.6), radius: state.showsVortex ? 32 : glowRadius * 0.5)
                if state.isOpen || state.dragProximity != nil {
                    EnergyRim(radius: cornerRadius, intensity: state.showsVortex ? 1 : max(0.35, state.dragProximity ?? 0))
                }
            }
            .scaleEffect(state.isOpen ? 1 : 1 + 0.08 * (state.dragProximity ?? 0), anchor: .top)
            content
        }
        .frame(width: size.width, height: size.height)
        .contentShape(NotchShape(radius: 10))
        .onDrop(of: [.fileURL], isTargeted: $state.isTargeted) { providers, location in
            guard !state.isDraggingOut else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await provider.loadFileURL() { urls.append(url) }
                }
                state.absorb(urls, from: location)
            }
            return true
        }
        .contextMenu {
            Button("Clear Shelf") { withAnimation { shelf.clear() } }
                .disabled(shelf.items.isEmpty)
            Divider()
            Button("Quit EventHorizon") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static let contentInset = NotchState.ear + 12

    private var cornerRadius: CGFloat { state.isOpen ? 20 : 10 }

    private var glowOpacity: Double {
        if state.showsVortex { return 0.95 }
        if let proximity = state.dragProximity { return 0.55 + 0.45 * proximity }
        return state.isOpen ? 0.45 : 0
    }

    private var glowRadius: CGFloat {
        if let proximity = state.dragProximity { return 8 + 26 * proximity }
        return state.isOpen ? 16 : 0
    }

    private var clearButton: some View {
        Button {
            withAnimation(.spring(response: 0.35)) { shelf.clear() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "trash")
                Text("Clear")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.flare)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.ember.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if state.isOpen {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !shelf.items.isEmpty && !state.showsVortex {
                        clearButton.transition(.opacity)
                    }
                }
                .frame(height: state.notchSize.height)
                ZStack { body(for: state) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Self.contentInset)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
        } else if !shelf.items.isEmpty {
            HStack {
                BlackHoleView(diameter: 18, intensity: 0.5).frame(width: NotchState.wing)
                Spacer()
                Text("\(shelf.items.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.flare)
                    .frame(width: NotchState.wing)
            }
            .padding(.horizontal, NotchState.ear)
            .frame(height: state.notchSize.height)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func body(for state: NotchState) -> some View {
        if state.showsVortex {
            ZStack {
                BlackHoleView(diameter: 76, intensity: state.isTargeted ? 1 : 0.8)
                ForEach(state.incoming) { SuckedInIcon(url: $0.url, start: $0.offset) }
            }
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        } else if shelf.items.isEmpty {
            VStack(spacing: 8) {
                BlackHoleView(diameter: 40, intensity: 0.45)
                Text("Drop files here")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .transition(.opacity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shelf.items) { item in
                        ItemView(item: item,
                                 onRemove: { withAnimation(.spring(response: 0.35)) { shelf.remove(item) } },
                                 onDragChanged: { state.isDraggingOut = $0 })
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .frame(minWidth: NotchState.openSize.width - 2 * Self.contentInset)
            }
            .transition(.opacity)
        }
    }
}

private extension NSItemProvider {
    func loadFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }
}
