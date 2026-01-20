import SwiftUI
import Combine

/// Animated typing indicator shown while AI is generating a response
struct TypingIndicatorView: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack {
            Text("aha" + String(repeating: ".", count: dotCount))
                .font(.system(size: 14 * scaleManager.scale))
                .foregroundStyle(.secondary)
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 4
                }
            Spacer()
        }
    }
}
