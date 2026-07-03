import SwiftUI

struct ProgressaStatsView: View {
    @EnvironmentObject private var model: ProgressaModel
    private var summary: ProgressaStatsSummary { model.statsSummary }

    var body: some View {
        List {
            Section("Overview") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    stat("Workouts", "\(summary.workoutCount)", "calendar")
                    stat("Sets", "\(summary.setCount)", "square.stack.3d.up")
                    stat("Reps", "\(summary.repCount)", "repeat")
                    stat("Volume", weight(summary.volumeKg), "scalemass")
                }.padding(.vertical, 6)
                if let latest = summary.latestTraining {
                    LabeledContent("Last training", value: latest.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Section("Personal records") {
                if summary.personalRecords.isEmpty {
                    Text("Complete workouts with sets to build your records.").foregroundStyle(.secondary)
                }
                ForEach(summary.personalRecords.prefix(12)) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.exerciseName).font(.headline)
                            Text(record.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.weightType == .bodyweight ? "\(Int(record.value)) reps" : weight(record.value))
                            .bold().monospacedDigit()
                    }
                }
            }
            Section("Cardio") {
                if model.cardioSessions.isEmpty {
                    Text("No Apple Health cardio metadata yet.").foregroundStyle(.secondary)
                }
                ForEach(model.cardioSessions.prefix(20)) { session in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(session.activityType.isEmpty ? session.title : session.activityType).font(.headline)
                            Spacer()
                            Text(session.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if let seconds = session.durationSeconds { Label("\(seconds / 60) min", systemImage: "clock") }
                            if let meters = session.distanceMeters { Label(distance(meters), systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                            if let bpm = session.averageHeartRate { Label("\(Int(bpm)) bpm", systemImage: "heart") }
                        }.font(.caption).foregroundStyle(.secondary)
                        if let location = session.location, !location.isEmpty { Text(location).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("Stats")
        .refreshable { await model.refreshStats() }
        .overlay { if model.isLoadingStats && model.statsSets.isEmpty { ProgressView() } }
        .task { if model.statsSets.isEmpty && model.cardioSessions.isEmpty { await model.refreshStats() } }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func weight(_ kg: Double) -> String {
        let units = model.measurementUnitSystem
        let value = units == .imperial ? kg * 2.204_622_621_8 : kg
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(units == .imperial ? "lb" : "kg")"
    }

    private func distance(_ meters: Double) -> String {
        if model.measurementUnitSystem == .imperial {
            return "\((meters / 1609.344).formatted(.number.precision(.fractionLength(1)))) mi"
        }
        return "\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) km"
    }
}

struct ProgressaMeasurementsView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var showingAdd = false
    @State private var noteTarget: ProgressaMeasurement?

    private var latest: [ProgressaMeasurement] {
        ProgressaMeasurementType.allCases.compactMap { type in model.measurements.first { $0.type == type } }
    }

    var body: some View {
        List {
            Section("Latest") {
                if latest.isEmpty { Text("No measurements yet.").foregroundStyle(.secondary) }
                ForEach(latest) { measurement in
                    HStack {
                        Text(measurement.type.title)
                        Spacer()
                        Text(display(measurement)).bold().monospacedDigit()
                    }
                }
            }
            Section("History") {
                ForEach(model.measurements) { measurement in
                    Button { noteTarget = measurement } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(measurement.type.title).foregroundStyle(.primary)
                                Spacer()
                                Text(display(measurement)).bold().foregroundStyle(.primary)
                            }
                            Text(measurement.measuredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if let note = measurement.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await model.deleteMeasurement(id: measurement.id) } }
                    }
                }
            }
        }
        .navigationTitle("Measurements")
        .toolbar { Button { showingAdd = true } label: { Label("Add", systemImage: "plus") } }
        .refreshable { await model.refreshMeasurements() }
        .overlay { if model.isLoadingMeasurements && model.measurements.isEmpty { ProgressView() } }
        .task { if model.measurements.isEmpty { await model.refreshMeasurements() } }
        .sheet(isPresented: $showingAdd) { AddMeasurementView() }
        .sheet(item: $noteTarget) { EditMeasurementNoteView(measurement: $0) }
    }

    private func display(_ measurement: ProgressaMeasurement) -> String {
        let units = model.measurementUnitSystem
        let value = units.displayValue(measurement.value, type: measurement.type)
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(units.unit(for: measurement.type))"
    }
}

private struct AddMeasurementView: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: ProgressaMeasurementType = .weight
    @State private var value = ""
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) { ForEach(ProgressaMeasurementType.allCases) { Text($0.title).tag($0) } }
                HStack {
                    TextField("Value", text: $value).keyboardType(.decimalPad)
                    Text(model.measurementUnitSystem.unit(for: type)).foregroundStyle(.secondary)
                }
                DatePicker(
                    "Measured", selection: $date,
                    in: Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!...Calendar.current.date(byAdding: .year, value: 1, to: .now)!
                )
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
            .navigationTitle("Add measurement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let number = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
                        Task { if await model.addMeasurement(type: type, displayedValue: number, measuredAt: date, note: note) { dismiss() } }
                    }.disabled(value.isEmpty || model.isLoadingMeasurements)
                }
            }
        }
    }
}

private struct EditMeasurementNoteView: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let measurement: ProgressaMeasurement
    @State private var note: String

    init(measurement: ProgressaMeasurement) {
        self.measurement = measurement
        _note = State(initialValue: measurement.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form { TextField("Note", text: $note, axis: .vertical).lineLimit(3...8) }
                .navigationTitle("Measurement note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { if await model.updateMeasurementNote(id: measurement.id, note: note) { dismiss() } } }
                    }
                }
        }
    }
}
