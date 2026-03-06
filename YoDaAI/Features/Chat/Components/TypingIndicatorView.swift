import SwiftUI

/// Animated typing indicator shown while AI is generating a response
struct TypingIndicatorView: View {
    @State private var phase = 0
    @Environment(\.appScaleManager) private var scaleManager

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 7 * scaleManager.scale, height: 7 * scaleManager.scale)
                    .scaleEffect(phase == index ? 1.3 : 0.85)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: phase
                    )
            }
            Spacer()
        }
        .onAppear {
            phase = 1
        }
    }
}
