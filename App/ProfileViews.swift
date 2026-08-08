import SwiftUI
import PhotosUI
import UI

// MARK: - ProfileAvatar
// The circular avatar shown on Home and in the profile editor: the photo if
// set, otherwise the user's initials, otherwise a person glyph — all on the
// green primary tint.
struct ProfileAvatar: View {
    @EnvironmentObject private var profile: ProfileStore
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(KitTheme.primary.opacity(0.15))
            if let image = profile.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !profile.initials.isEmpty {
                Text(profile.initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(KitTheme.primary)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(KitTheme.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - ProfileFormView
// One screen used for both first-run onboarding and later editing: pick a
// photo, type a name, done. Onboarding flips ProfileStore.didOnboard so it
// never shows again; the editing variant is presented as a sheet.
struct ProfileFormView: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let isOnboarding: Bool

    @State private var pickerItem: PhotosPickerItem?
    @State private var draftName: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if isOnboarding {
                        VStack(spacing: 6) {
                            Text("Welcome to Mizan")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(KitTheme.textPrimary)
                            Text("Set up your profile. Everything stays on this device.")
                                .font(.system(size: 13))
                                .foregroundStyle(KitTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatar(size: 120)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 34, height: 34)
                                .background(KitTheme.primary, in: Circle())
                                .overlay(Circle().stroke(KitTheme.canvas, lineWidth: 3))
                        }
                    }
                    .buttonStyle(.plain)

                    KitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your name")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(KitTheme.textSecondary)
                            TextField("", text: $draftName, prompt: Text("e.g. Mark Emad").foregroundColor(KitTheme.textTertiary))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(KitTheme.textPrimary)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    KitPrimaryButton(isOnboarding ? "Get started" : "Save") {
                        profile.name = draftName.trimmingCharacters(in: .whitespaces)
                        if isOnboarding { profile.didOnboard = true }
                        dismiss()
                    }
                }
                .padding(20)
            }
            .kitBackground()
            .navigationTitle(isOnboarding ? "" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.tint(KitTheme.primary)
                    }
                }
            }
            .onAppear { draftName = profile.name }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        profile.setImage(image)
                    }
                }
            }
        }
    }
}
