import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentColor") private var accentColor = "violet"
    @State private var confirmReset = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System (\(systemColorScheme == .dark ? "Dark" : "Light"))").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent color").font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                        ForEach(QuantivitaAppearance.accents) { accent in
                            Button { accentColor = accent.id } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle().fill(accent.color.gradient).frame(width: 42, height: 42)
                                        if accentColor == accent.id { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                                    }
                                    Text(accent.name).font(.caption2.weight(.medium)).foregroundStyle(.primary)
                                }
                            }.buttonStyle(.plain).accessibilityAddTraits(accentColor == accent.id ? .isSelected : [])
                        }
                    }
                }.padding(.vertical, 8)
            }
            Section("Connections") {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                    Spacer()
                    Text(model.healthConnectionLabel)
                        .foregroundStyle(model.healthConnectionLabel == "Data available" ? .green : .secondary)
                }
                HStack {
                    Label("Progressa", systemImage: "dumbbell.fill")
                    Spacer()
                    Text(model.progressaConnected ? "Connected" : "Not connected").foregroundStyle(model.progressaConnected ? .green : .secondary)
                }
                if model.progressaConnected {
                    Button("Disconnect Progressa", role: .destructive) { Task { await model.disconnectProgressa() } }
                } else {
                    Button("Connect Progressa") { Task { await model.connectProgressa() } }
                }
                HStack {
                    Label("Strava", systemImage: "figure.run.circle.fill")
                    Spacer()
                    Text(model.stravaConnected ? "Connected" : "Not connected").foregroundStyle(model.stravaConnected ? .green : .secondary)
                }
                if model.stravaConnected {
                    Button("Disconnect Strava", role: .destructive) { Task { await model.disconnectStrava() } }
                } else {
                    Button("Connect Strava") { Task { await model.connectStrava() } }
                }
            }
            Section("Privacy") {
                Text("Health data is cached on this device and synced only to your authenticated Quantivita account.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Health profile") {
                LabeledContent("Date of birth", value: birthDateLabel)
                LabeledContent("Biological sex", value: biologicalSexLabel)
                LabeledContent("Weight", value: measurement(model.summary.bodyMassKg, unit: "kg"))
                LabeledContent("Height", value: measurement(model.summary.heightCm, unit: "cm"))
                LabeledContent("Body fat", value: measurement(model.summary.bodyFatPercent, unit: "%"))
                NavigationLink { HealthProfileEditor() } label: {
                    Label("Edit health profile", systemImage: "person.text.rectangle")
                }
            }
            Section {
                Button { model.signOut() } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset cached data", systemImage: "arrow.counterclockwise")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete account", systemImage: "trash")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Sign out keeps your cached data on this device. Delete account removes your data from Quantivita servers and this device permanently.")
            }
            Section("About") { LabeledContent("Version", value: "0.1 native preview") }
        }
        .navigationTitle("You")
        .confirmationDialog("Reset cached data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await model.resetLocalData() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the on-device cache and re-reads everything from Apple Health.")
        }
        .confirmationDialog("Delete account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await model.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Quantivita account and all data on the server and this device. This cannot be undone.")
        }
    }

    private var birthDateLabel: String {
        guard model.summary.birthYear > 0 else { return "No data" }
        return String(format: "%04d-%02d-%02d", model.summary.birthYear, model.summary.birthMonth, model.summary.birthDay)
    }

    private var biologicalSexLabel: String {
        switch model.summary.biologicalSex {
        case 1: return "Female"
        case 2: return "Male"
        case 3: return "Other"
        default: return "Not set"
        }
    }

    private func measurement(_ value: Double, unit: String) -> String {
        value > 0 ? "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" : "No data"
    }
}

private struct HealthProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var hasBirthdate = false
    @State private var birthdate = Date.now
    @State private var biologicalSex = 0
    @State private var weight = ""
    @State private var height = ""
    @State private var bodyFat = ""
    @State private var saving = false

    var body: some View {
        Form {
            Section("Personal") {
                Toggle("Set date of birth", isOn: $hasBirthdate)
                if hasBirthdate { DatePicker("Date of birth", selection: $birthdate, in: ...Date.now, displayedComponents: .date) }
                Picker("Biological sex", selection: $biologicalSex) {
                    Text("Not set").tag(0); Text("Female").tag(1); Text("Male").tag(2); Text("Other").tag(3)
                }
            }
            Section("Body measurements") {
                measurementField("Weight", value: $weight, unit: "kg")
                measurementField("Height", value: $height, unit: "cm")
                measurementField("Body fat", value: $bodyFat, unit: "%")
            }
            Section {
                Button {
                    Task {
                        saving = true
                        await model.saveHealthProfile(
                            birthdate: hasBirthdate ? birthdate : nil, biologicalSex: biologicalSex,
                            bodyMassKg: number(weight), heightCm: number(height), bodyFatPercent: number(bodyFat)
                        )
                        saving = false; dismiss()
                    }
                } label: {
                    if saving { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Save profile").frame(maxWidth: .infinity) }
                }.disabled(saving)
            } footer: {
                Text("These values personalize scoring and are stored in your protected Quantivita account cache.")
            }
        }
        .navigationTitle("Health profile")
        .onAppear {
            biologicalSex = model.summary.biologicalSex
            weight = display(model.summary.bodyMassKg); height = display(model.summary.heightCm); bodyFat = display(model.summary.bodyFatPercent)
            if model.summary.birthYear > 0,
               let date = Calendar.current.date(from: DateComponents(
                year: model.summary.birthYear, month: model.summary.birthMonth, day: model.summary.birthDay
               )) { hasBirthdate = true; birthdate = date }
        }
    }

    private func measurementField(_ title: String, value: Binding<String>, unit: String) -> some View {
        HStack { TextField(title, text: value).keyboardType(.decimalPad); Text(unit).foregroundStyle(.secondary) }
    }
    private func number(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    private func display(_ value: Double) -> String { value > 0 ? value.formatted(.number.precision(.fractionLength(0...1))) : "" }
}
