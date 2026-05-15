//
//  FloatingStopButton.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI

// Free-floating, drag-positionable stop button. Sits inside the running
// view's safe area; the user can drag it to any corner before tapping
// to disconnect.
struct FloatingStopButton: View {
    let action: () -> Void

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

            Image(systemName: "stop.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.32, blue: 0.32),
                                     Color(red: 0.85, green: 0.18, blue: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .contentShape(Circle())
                .position(current)
                // Plain styled view (not Button) so the drag gesture
                // owns the touch sequence and `drag` updates flow
                // continuously while the finger moves. minimumDistance
                // 0 starts tracking on touch-down; .onEnded
                // distinguishes a tap from a drag by translation
                // magnitude.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($drag) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) < 5 && abs(dy) < 5 {
                                action()
                                return
                            }
                            location = clamp(
                                CGPoint(x: anchor.x + dx, y: anchor.y + dy),
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
