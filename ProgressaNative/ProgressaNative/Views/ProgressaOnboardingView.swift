import SwiftUI

struct ProgressaOnboardingView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var fullName = ""
    @State private var country = ""
    @State private var birthdate: Date?
    @State private var showingBirthdate = false
    @State private var candidateBirthdate = Calendar.current.date(byAdding: .year, value: -25, to: .now)!

    private var countries: [(code: String, name: String)] {
        Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.compactMap { code in
            Locale.current.localizedString(forRegionCode: code).map { (code, $0) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canContinue: Bool {
        let nameValid = model.session?.isAppleUser == true || !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameValid && country.count == 2 && birthdate != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Let’s set up your profile")
                        .font(.title2.bold())
                    Text("Your country and birthdate help Progressa personalize units and recommendations.")
                        .foregroundStyle(.secondary)
                }
                Section("Personal details") {
                    TextField(model.session?.isAppleUser == true ? "Full name (optional)" : "Full name", text: $fullName)
                        .textContentType(.name)
                    Picker("Country", selection: $country) {
                        Text("Select country").tag("")
                        ForEach(countries, id: \.code) { item in
                            Text(item.name).tag(item.code)
                        }
                    }
                    Button {
                        candidateBirthdate = birthdate ?? Calendar.current.date(byAdding: .year, value: -25, to: .now)!
                        showingBirthdate = true
                    } label: {
                        LabeledContent("Birthdate", value: birthdate?.formatted(date: .numeric, time: .omitted) ?? "Select")
                    }
                }
                Section {
                    Button {
                        guard let birthdate else { return }
                        Task { await model.saveProfile(fullName: fullName, country: country, birthdate: birthdate) }
                    } label: {
                        if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Continue").frame(maxWidth: .infinity) }
                    }
                    .disabled(!canContinue || model.isLoading)
                }
                Section {
                    Button("Sign out", role: .destructive) { model.signOut() }
                }
            }
            .navigationTitle("Personal details")
            .interactiveDismissDisabled()
            .task {
                guard fullName.isEmpty, country.isEmpty, birthdate == nil else { return }
                fullName = model.profile?.fullName ?? ""
                country = model.profile?.country?.uppercased() ?? ""
                birthdate = model.profile?.birthdate
            }
            .sheet(isPresented: $showingBirthdate) {
                NavigationStack {
                    DatePicker(
                        "Birthdate", selection: $candidateBirthdate,
                        in: Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!...Calendar.current.date(byAdding: .year, value: -10, to: .now)!,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select birthdate")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingBirthdate = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { birthdate = candidateBirthdate; showingBirthdate = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
