import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("dashboardWidgets") private var dashboardWidgets = DashboardWidget.defaultStorage
    @State private var showingComposer = false
    @State private var showSyncComplete = false

    private var enabled: Set<DashboardWidget> { DashboardWidget.decode(dashboardWidgets) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TodayHeader(showSyncComplete: showSyncComplete)
                if enabled.contains(.readiness) { Panel {
                    BodyBatteryHero(score: model.dailyScores.bodyBattery.score)
                } }
                if enabled.contains(.scores) { LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricPanel(title: "Strain", value: model.dailyScores.strain.score.formatted(.number.precision(.fractionLength(1))), color: .orange)
                    MetricPanel(title: "Recovery", value: "\(model.recovery.score)%", color: .green)
                } }
                if enabled.contains(.metrics) { LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricPanel(title: "Sleep", value: model.summary.hasSleepData ? "\(model.dailyScores.sleep.score)% · \(minutes(model.summary.sleepMinutes))" : "No data", color: .indigo)
                    MetricPanel(title: "HRV", value: model.summary.hrvMs > 0 ? "\(Int(model.summary.hrvMs)) ms" : "No data", color: .green)
                } }
                if enabled.contains(.nutrition) { Panel {
                    Text("Nutrition & hydration").font(.headline)
                    HStack {
                        nutritionValue("Energy", value: model.summary.dietaryEnergyKcal, unit: "kcal")
                        nutritionValue("Water", value: model.summary.dietaryWaterMl, unit: "ml")
                    }
                    Divider()
                    HStack {
                        nutritionValue("Carbs", value: model.summary.dietaryCarbohydratesG, unit: "g")
                        nutritionValue("Protein", value: model.summary.dietaryProteinG, unit: "g")
                        nutritionValue("Fat", value: model.summary.dietaryFatG, unit: "g")
                    }
                } }
                if enabled.contains(.activity) { LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricPanel(title: "Steps", value: model.summary.steps.formatted(.number.precision(.fractionLength(0))), color: .cyan)
                    MetricPanel(title: "Active", value: "\(Int(model.summary.activeEnergyKcal)) kcal", color: .orange)
                } }
                if enabled.contains(.workout), let latest = model.displayWorkouts.first {
                    NavigationLink(value: latest) {
                        Panel {
                            Text("Latest workout").font(.headline)
                            Text(latest.title).font(.title3.bold())
                            Text("\(Int(latest.effectiveDurationMinutes)) min · \(latest.energyAvailable == false ? "Energy unavailable" : "\(Int(latest.effectiveEnergyKcal)) kcal")")
                                .foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 18)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { showingComposer = true } label: { Label("Customize dashboard", systemImage: "slider.horizontal.3") } }
        .sheet(isPresented: $showingComposer) {
            DashboardComposer(selection: Binding(
                get: { DashboardWidget.decode(dashboardWidgets) },
                set: { dashboardWidgets = DashboardWidget.encode($0) }
            ))
        }
        .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        .refreshable {
            await model.refreshHealth()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                showSyncComplete = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.2)) { showSyncComplete = false }
            }
        }
        .background(QuantivitaTheme.background.ignoresSafeArea())
    }

    private func nutritionValue(_ name: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value > 0 ? "\(Int(value)) \(unit)" : "No data").font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricColumns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible())] }
}

private struct TodayHeader: View {
    let showSyncComplete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                if showSyncComplete {
                    Label("Sync Complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.green.opacity(0.14), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.55)) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Button {} label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
            }
            Text("Today, \(Self.dateText)")
                .font(.system(size: 39, weight: .black, design: .rounded))
        }
    }

    private static var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: Date())
    }
}

private struct BodyBatteryHero: View {
    let score: Int

    var body: some View {
        VStack(spacing: 12) {
            ScoreDial(title: "Body Battery", value: score, color: .green)
                .frame(maxWidth: .infinity)
            Text("Body Battery")
                .font(.title3.weight(.bold))
            Text("Your current energy reserve based on recovery, sleep, activity and stress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScoreDial: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Gauge(value: Double(value), in: 0...100) {
                Text("\(value)%")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(color)
            .scaleEffect(1.45)
            .frame(height: 110)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum DashboardWidget: String, CaseIterable, Identifiable {
    case readiness, scores, metrics, nutrition, activity, workout
    var id: String { rawValue }
    var title: String {
        switch self {
        case .readiness: "Recovery"
        case .scores: "Body Battery & strain"
        case .metrics: "Sleep & HRV"
        case .nutrition: "Nutrition & hydration"
        case .activity: "Daily activity"
        case .workout: "Latest workout"
        }
    }
    var icon: String {
        switch self {
        case .readiness: "gauge.with.dots.needle.67percent"
        case .scores: "battery.75percent"
        case .metrics: "waveform.path.ecg"
        case .nutrition: "drop.fill"
        case .activity: "figure.walk"
        case .workout: "dumbbell.fill"
        }
    }
    static var defaultStorage: String { encode(Set(allCases)) }
    static func decode(_ value: String) -> Set<Self> {
        let result = Set(value.split(separator: ",").compactMap { Self(rawValue: String($0)) })
        return result.isEmpty ? [.readiness] : result
    }
    static func encode(_ value: Set<Self>) -> String {
        let safe = value.isEmpty ? Set([Self.readiness]) : value
        return allCases.filter(safe.contains).map(\.rawValue).joined(separator: ",")
    }
}

private struct DashboardComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<DashboardWidget>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DashboardWidget.allCases) { widget in
                        Button {
                            if selection.contains(widget) {
                                if selection.count > 1 { selection.remove(widget) }
                            } else { selection.insert(widget) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: widget.icon).frame(width: 32).font(.title3)
                                Text(widget.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selection.contains(widget) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundColor(selection.contains(widget) ? .accentColor : .secondary)
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }
                } header: { Text("Visible cards") } footer: { Text("Choose which health cards appear on Today. At least one card remains visible.") }
            }
            .navigationTitle("Customize Today")
            .toolbar { Button("Done") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}

struct BiomarkersView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section("Cardiovascular") {
                BiomarkerRow(name: "Heart-rate variability", value: model.summary.hrvMs, unit: "ms")
                BiomarkerRow(name: "Resting heart rate", value: model.summary.restingHeartBpm, unit: "bpm")
            }
            Section("Respiratory") {
                BiomarkerRow(name: "Respiratory rate", value: model.summary.respiratoryRate, unit: "br/min")
                BiomarkerRow(name: "Oxygen saturation", value: model.summary.oxygenSaturation, unit: "%")
            }
            Section("Temperature") {
                BiomarkerRow(name: "Body temperature", value: model.summary.bodyTemperatureC, unit: "°C")
                BiomarkerRow(name: "Wrist temperature", value: model.summary.wristTemperatureC, unit: "°C")
            }
            Section("Body") {
                NavigationLink(destination: WeightHistoryView()) {
                    BiomarkerRow(name: "Weight", value: model.summary.bodyMassKg, unit: "kg")
                }
                BiomarkerRow(name: "Height", value: model.summary.heightCm, unit: "cm")
                BiomarkerRow(name: "Body fat", value: model.summary.bodyFatPercent, unit: "%")
            }
        }.navigationTitle("Trends")
    }
}

struct MetricPanel: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay { Image(systemName: "waveform.path.ecg").foregroundStyle(color) }
                Text(value).font(.title.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(minHeight: 92)
    }
}

private struct BiomarkerRow: View {
    let name: String
    let value: Double
    let unit: String
    var body: some View {
        HStack { Text(name); Spacer(); Text(value > 0 ? "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)" : "No data").foregroundStyle(.secondary) }
    }
}

private func minutes(_ value: Double) -> String {
    let total = Int(value.rounded())
    return "\(total / 60)h \(total % 60)m"
}
