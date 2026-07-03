import SwiftUI

struct ProgressaAppearanceView: View {
    @AppStorage("progressa.theme") private var theme = ProgressaThemeMode.system.rawValue
    @AppStorage("progressa.accent") private var accent = ProgressaAccent.presets[0].id

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsCard(title: "Theme", subtitle: "System follows your iPhone automatically.") {
                    HStack(spacing: 10) {
                        ForEach(ProgressaThemeMode.allCases) { option in
                            choiceButton(
                                title: option.title, icon: option.icon,
                                selected: theme == option.rawValue
                            ) { theme = option.rawValue }
                        }
                    }
                }

                settingsCard(title: "Accent color", subtitle: "Used for buttons, icons, charts and selected tabs.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], spacing: 14) {
                        ForEach(ProgressaAccent.presets) { option in
                            Button { accent = option.id } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle().fill(option.color.gradient).frame(width: 46, height: 46)
                                        if accent == option.id { Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(.white) }
                                    }
                                    Text(option.title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.plain).accessibilityAddTraits(accent == option.id ? .isSelected : [])
                        }
                    }
                }

                HStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(ProgressaAccent.color(for: accent))
                    VStack(alignment: .leading) {
                        Text("Live preview").font(.headline)
                        Text("Your choice applies throughout Progressa.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(ProgressaAccent.color(for: accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
            }.padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Appearance")
    }

    private func settingsCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold()); Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func choiceButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) { Image(systemName: icon).font(.title2); Text(title).font(.caption.bold()) }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? ProgressaAccent.color(for: accent) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
