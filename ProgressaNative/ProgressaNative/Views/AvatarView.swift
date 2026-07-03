import SwiftUI

struct ProgressaAvatarView: View {
    let path: String?
    let fallback: String
    let session: ProgressaSession?
    var size: CGFloat = 42
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { fallbackView }
            } else { fallbackView }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: path) {
            guard let path, !path.isEmpty, let session else { url = nil; return }
            url = try? await ProgressaAvatarService.shared.signedURL(path: path, session: session)
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle().fill(.purple.opacity(0.16))
            Text(String(fallback.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "?").uppercased()).font(.headline)
        }
    }
}
