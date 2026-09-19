import SwiftUI

extension View {
    /// The frosted card every home-screen section sits on, so the body-battery glow shows
    /// through it.
    func dashboardCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.72), in: .rect(cornerRadius: 22))
    }
}

/// A home-screen section: a title, then its content.
struct DashboardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.leading, 4)
            content()
        }
    }
}
