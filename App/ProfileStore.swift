import SwiftUI
import UIKit

// MARK: - ProfileStore
// The local, on-device profile: a display name and a photo. Mizan has no
// server, so "your account" is just this — the name lives in UserDefaults and
// the photo is a file in Application Support (complete file protection, so it's
// encrypted at rest with the device passcode like everything else). `didOnboard`
// gates the one-time first-run setup screen.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Keys.name) }
    }
    @Published var didOnboard: Bool {
        didSet { UserDefaults.standard.set(didOnboard, forKey: Keys.didOnboard) }
    }
    @Published var image: UIImage?

    private enum Keys {
        static let name = "profileName"
        static let didOnboard = "didOnboard"
    }

    init() {
        name = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        didOnboard = UserDefaults.standard.bool(forKey: Keys.didOnboard)
        if let data = try? Data(contentsOf: Self.imageURL) {
            image = UIImage(data: data)
        }
    }

    /// Initials shown when there's no photo (e.g. "ME" for "Mark Emad").
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "" : letters.uppercased()
    }

    func setImage(_ image: UIImage?) {
        self.image = image
        if let image, let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: Self.imageURL, options: .completeFileProtection)
        } else {
            try? FileManager.default.removeItem(at: Self.imageURL)
        }
    }

    private static var imageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.jpg")
    }
}
