import SwiftUI

/// Inline banner for errors / notices (never a system alert per product spec).
struct BannerView: View {
    let banner: MainWindowModel.Banner
    let onDismiss: () -> Void


    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tintColor)
            Text(banner.message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch banner {
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tintColor: Color {
        switch banner {
        case .error: .red
        case .info: .accentColor
        }
    }
}
