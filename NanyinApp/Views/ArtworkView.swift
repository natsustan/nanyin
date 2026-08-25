//
//  ArtworkView.swift
//  Nanyin
//

import SwiftUI

/// Artwork renderer that paints memory hits synchronously and only fades new loads.
struct ArtworkView<Placeholder: View>: View {
    private struct TaskID: Hashable {
        let url: URL?
        let size: CGFloat
    }

    let url: URL?
    let size: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loaded: (id: TaskID, image: NSImage)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var taskID: TaskID {
        TaskID(url: url, size: size)
    }

    var body: some View {
        let cached = url.flatMap {
            ArtworkCache.shared.cachedImage(for: $0, targetSize: size)
        }
        let image = cached ?? (loaded?.id == taskID ? loaded?.image : nil)

        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            guard cached == nil, let url,
                  let image = await ArtworkCache.shared.image(for: url, targetSize: size),
                  !Task.isCancelled else { return }
            if reduceMotion {
                loaded = (taskID, image)
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    loaded = (taskID, image)
                }
            }
        }
    }
}
