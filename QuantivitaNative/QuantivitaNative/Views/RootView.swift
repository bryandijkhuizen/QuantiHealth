import AuthenticationServices
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("accentColor") private var accentColor = "violet"

    var body: some View {
        Group {
            switch model.stage {
            case .authentication: AuthView()
            case .permissions: HealthPermissionView()
            case .dashboard: MainTabView()
            }
        }
        .tint(QuantivitaAppearance.color(accentColor))
        .alert("Quantivita", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }
}

private struct AuthView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            QuantivitaTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 68))
                        .foregroundStyle(QuantivitaTheme.accent)
                        .padding(22)
                        .background(.regularMaterial, in: Circle())
                    Text("Quantivita")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                    Text("Recovery, sleep and training in one private health companion.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        switch result {
                        case let .success(authorization):
                            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                            Task { await model.signInWithApple(userIdentifier: apple.user) }
                        case let .failure(error):
                            if (error as? ASAuthorizationError)?.code != .canceled {
                                model.message = error.localizedDescription
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                    .disabled(model.isLoading)

                    Button { Task { await model.continueOffline() } } label: {
                        Label("Continue offline", systemImage: "icloud.slash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.45), lineWidth: 1)
                    }
                    .disabled(model.isLoading)
                    .opacity(model.isLoading ? 0.55 : 1)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
                    .frame(maxWidth: .infinity)

                if model.isLoading {
                    ProgressView()
                }
            }
            .padding(28)
        }
    }
}

private struct HealthPermissionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 64)).foregroundStyle(.red)
            Text("Connect Apple Health").font(.largeTitle.bold())
            Text("Quantivita reads only the health categories needed for recovery, sleep and workout insights. You control every permission in Apple Health.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await model.authorizeHealth() } } label: {
                if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
                else { Text("Review Health permissions").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(28).background(QuantivitaTheme.background.ignoresSafeArea())
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "sun.max.fill") }
            NavigationStack { BiomarkersView() }.tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            NavigationStack { WorkoutsView() }.tabItem { Label("Log", systemImage: "figure.run") }
            NavigationStack { StrengthIndexView() }.tabItem { Label("Progress Index", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { SettingsView() }.tabItem { Label("You", systemImage: "person.crop.circle") }
        }
    }
}

enum QuantivitaTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.70, green: 0.95, blue: 0.40, alpha: 1)
            : UIColor(red: 0.32, green: 0.78, blue: 0.36, alpha: 1)
    })
    static let background = LinearGradient(
        colors: [
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.03, green: 0.07, blue: 0.10, alpha: 1) : UIColor(red: 0.92, green: 0.97, blue: 0.98, alpha: 1) }),
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.06, green: 0.09, blue: 0.13, alpha: 1) : UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 1) }),
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1) : UIColor(red: 1.00, green: 0.95, blue: 0.94, alpha: 1) }),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 12)
    }
}

private struct StrengthIndexView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dates: [String] = []
    @State private var from = ""
    @State private var to = ""
    @State private var rows: [StrengthIndex.Exercise] = []
    @State private var error: String?
    @State private var loading = true
    @State private var retry = 0

    var body: some View {
        List {
            if !dates.isEmpty {
                Section("Logged workout dates") {
                    Picker("From", selection: $from) {
                        ForEach(dates.filter { $0 <= to }, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Through", selection: $to) {
                        ForEach(dates.filter { $0 >= from }, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            if loading { ProgressView() }
            else if let error {
                Text(error)
                Button("Retry") { retry += 1 }
            } else if rows.isEmpty {
                Text("No weighted working sets in this period.")
            } else {
                Section {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name).font(.headline)
                            if row.days > 1 {
                                Text("Index \(row.index.formatted(.number.precision(.fractionLength(2)))) · \((row.index - 1).formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())))")
                                    .font(.title3.bold())
                            } else { Text("Baseline · 1.00").font(.subheadline) }
                            measurement(row.baseline)
                            if row.days > 1 { measurement(row.current) }
                        }.padding(.vertical, 4)
                    }
                } footer: { Text("Each exercise starts at 1.00. The index compares the best estimated 1RM on its first and last logged days in this period, using total weight × (1 + reps / 30).") }
            }
        }
        .navigationTitle("Progress Index")
        .task(id: "\(from)|\(to)|\(retry)|\(model.progressaConnected)") {
            loading = true
            error = nil
            do {
                let result = try await model.progressIndex(from: from.isEmpty ? nil : from, to: to.isEmpty ? nil : to)
                try Task.checkCancellation()
                dates = result.loggedDates
                if from.isEmpty { from = dates.first ?? ""; to = dates.last ?? "" }
                rows = result.exercises
                loading = false
            } catch where Task.isCancelled {} catch { self.error = error.localizedDescription; loading = false }
        }
    }

    private func measurement(_ set: StrengthIndex.Measurement) -> some View {
        VStack(alignment: .leading) {
            Text("\(set.day) · \(set.total.formatted()) kg × \(set.reps) · e1RM \(set.estimate.formatted(.number.precision(.fractionLength(0...1)))) kg")
            if set.base > 0 { Text("Base \(set.base.formatted()) + added \(set.added.formatted()) kg") }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
