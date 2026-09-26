import SwiftUI

/// The five places the app goes.
enum TwinTab: String, CaseIterable, Identifiable {
    case twin, predictions, activity, plan, you

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .twin: "figure.stand"
        case .predictions: "chart.line.uptrend.xyaxis"
        case .activity: "flame.fill"
        case .plan: "calendar"
        case .you: "person.crop.circle"
        }
    }

    /// The page after this one, for scrolling past the bottom.
    var next: TwinTab? {
        let all = TwinTab.allCases
        guard let here = all.firstIndex(of: self), here + 1 < all.count else { return nil }
        return all[here + 1]
    }

    /// And the one before, for scrolling back past the top.
    var previous: TwinTab? {
        let all = TwinTab.allCases
        guard let here = all.firstIndex(of: self), here > 0 else { return nil }
        return all[here - 1]
    }

    var name: String {
        switch self {
        case .twin: "Dash"
        case .predictions: "Predictions"
        case .activity: "Activity"
        case .plan: "Plan"
        case .you: "You"
        }
    }
}

/// A bar that floats over the page: dark glass, with a pill sliding behind whichever tab
/// you're on.
struct TwinTabBar: View {
    @Binding var tab: TwinTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TwinTab.allCases) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.3)) { tab = item }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if tab == item {
                                Capsule()
                                    .fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .padding(.horizontal, 24)
    }
}

#Preview("Tab bar") {
    @Previewable @State var tab = TwinTab.twin
    ZStack {
        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        VStack { Spacer(); TwinTabBar(tab: $tab) }
    }
}
