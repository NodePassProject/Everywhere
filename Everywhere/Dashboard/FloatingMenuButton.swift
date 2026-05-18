//
//  FloatingMenuButton.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI

// Free-floating, drag-positionable menu button. Sits inside the running
// view's safe area; the user can drag it to any corner. Tapping the
// button opens a menu with actions for returning to the home screen or
// stopping the VPN.
struct FloatingMenuButton: View {
    let onHome: () -> Void
    let onStop: () -> Void

    @State private var location: CGPoint?
    @GestureState private var drag: CGSize = .zero

    private let buttonSize: CGFloat = 56
    private let marginX: CGFloat = 10
    private let marginY: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let anchor = location ?? defaultLocation(in: geo)
            let current = CGPoint(
                x: anchor.x + drag.width,
                y: anchor.y + drag.height
            )

            Menu {
                Button {
                    onHome()
                } label: {
                    Label("Go Back", systemImage: "arrow.turn.up.left")
                }
                Button(role: .destructive) {
                    onStop()
                } label: {
                    Label("Stop VPN", systemImage: "stop.fill")
                }
            } label: {
                if #available(iOS 26.0, *), false {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: buttonSize, height: buttonSize)
                        .glassEffect(.regular, in: .circle)
                        .contentShape(Circle())
                        .accessibilityLabel("More")
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            Circle()
                                .fill(.gray.opacity(0.1))
                        )
                        .contentShape(Circle())
                        .accessibilityLabel("More")
                }
            }
            .buttonStyle(.plain)
            .position(current)
            // minimumDistance 10 means a quick tap falls through to
            // Menu's tap handling, while a deliberate drag wins and
            // repositions the button without opening the menu.
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .updating($drag) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        location = clamp(
                            CGPoint(
                                x: anchor.x + value.translation.width,
                                y: anchor.y + value.translation.height
                            ),
                            in: geo
                        )
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: location)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func defaultLocation(in geo: GeometryProxy) -> CGPoint {
        CGPoint(
            x: geo.size.width - buttonSize / 2 - marginX,
            y: geo.size.height - buttonSize / 2 - marginY
        )
    }

    private func clamp(_ p: CGPoint, in geo: GeometryProxy) -> CGPoint {
        let minX = buttonSize / 2 + marginX
        let maxX = geo.size.width - buttonSize / 2 - marginX
        let minY = buttonSize / 2 + marginX
        let maxY = geo.size.height - buttonSize / 2 - marginY
        return CGPoint(
            x: min(max(p.x, minX), maxX),
            y: min(max(p.y, minY), maxY)
        )
    }
}
