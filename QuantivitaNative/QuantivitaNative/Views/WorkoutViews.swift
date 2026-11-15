import CoreLocation
import MapKit
import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.progressaConnected {
                Button { Task { await model.syncProgressa() } } label: {
                    if model.isSyncingProgressa {
                        HStack { ProgressView(); Text("Syncing Progressa…") }
                    } else {
                        Label("Sync Progressa", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.isSyncingProgressa)
            }
            Button { Task { await model.forceSyncAllWorkouts() } } label: {
                Label("Force sync all workouts", systemImage: "arrow.triangle.2.circlepath.circle")
            }
            .disabled(model.isLoading)
            ForEach(model.displayWorkouts) { workout in
                NavigationLink(value: workout) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(workout.title).font(.headline); if workout.progressaDetails != nil { Text("PROGRESSA LINKED").font(.caption2.bold()).foregroundStyle(.purple) } }
                        Text(workout.startTime.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Text("\(Int(workout.effectiveDurationMinutes)) min · \(workout.energyAvailable == false ? "Energy unavailable" : "\(Int(workout.effectiveEnergyKcal)) kcal")").font(.subheadline)
                    }.padding(.vertical, 4)
                }
                .task {
                    if workout.id == model.displayWorkouts.last?.id { await model.loadMoreWorkouts() }
                }
            }
            if model.isLoadingMoreWorkouts { ProgressView("Loading older workouts…") }
        }
        .overlay {
            if model.displayWorkouts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "figure.run").font(.largeTitle)
                    Text("No workouts").font(.headline)
                    Text("Connect Apple Health or Progressa to load workout history.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
        }
        .navigationTitle("Workout log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { MergeLabView() } label: { Label("Combine", systemImage: "square.stack.3d.up") }
            }
        }
        .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        .refreshable { await model.refreshAll() }
    }
}

struct MergeLabView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []
    @State private var preview: WorkoutMergePreview?
    @State private var strategy = "concatenate"
    @State private var busy = false
    @State private var error: String?
    @State private var confirming = false

    private var workouts: [Workout] { model.displayWorkouts.filter { $0.merge == nil && $0.progressaDetails == nil } }
    var body: some View {
        List {
            Section {
                Text("Combine parts of one training inside Quantivita. Original activities stay unchanged in Apple Health and Strava.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Select activities") {
                if preview != nil {
                    Button("Change selection") { preview = nil; strategy = "concatenate" }
                }
                ForEach(preview == nil ? workouts : workouts.filter { selected.contains($0.id) }) { workout in
                    Button {
                        if selected.contains(workout.id) { selected.removeAll { $0 == workout.id } }
                        else { selected.append(workout.id) }
                        preview = nil; strategy = "concatenate"
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selected.contains(workout.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title).foregroundStyle(.primary)
                                Text(workout.startTime.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                                Text("\(Int(workout.durationMinutes)) min · \(workout.sourceName ?? workout.source)")
                                Text("Ends \((workout.startTime.addingTimeInterval((workout.elapsedDurationMinutes ?? workout.durationMinutes) * 60)).formatted(date: .abbreviated, time: .shortened))")
                                if selected.first == workout.id { Text("First selected source").foregroundStyle(.tint) }
                            }.font(.subheadline)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected.contains(workout.id) ? .isSelected : [])
                }
            }.disabled(busy)
            if let preview {
                Section("Preview") {
                    LabeledContent("Activities", value: "\(preview.sources.count)")
                    LabeledContent("Active duration", value: "\(Int(preview.workout.durationMinutes)) min")
                    if let elapsed = preview.workout.elapsedDurationMinutes { LabeledContent("Elapsed duration", value: "\(Int(elapsed)) min") }
                    LabeledContent("Distance", value: preview.workout.distanceAvailable == false ? "Unavailable" : "\((preview.workout.distanceMeters / 1000).formatted(.number.precision(.fractionLength(1)))) km")
                    LabeledContent("Energy", value: preview.workout.energyAvailable == false ? "Unavailable" : "\(Int(preview.workout.energyKcal)) kcal")
                    if preview.overlapSeconds > 1 { LabeledContent("Overlap", value: "\(Int(preview.overlapSeconds / 60)) min") }
                    ForEach(preview.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                    if let note = preview.workout.metricsNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                if preview.overlapSeconds > 1 {
                    Section("Handle overlap") {
                        Button("Keep measurements from first selected source") { strategy = "duplicate"; Task { await loadPreview() } }
                        Button("Combine time; leave distance and energy unknown") { strategy = "time_only"; Task { await loadPreview() } }
                    }.disabled(busy)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Combine activities")
        .safeAreaInset(edge: .bottom) {
            Button {
                if preview?.canMerge == true { confirming = true }
                else { Task { await loadPreview() } }
            } label: {
                HStack { if busy { ProgressView() }; Text(preview?.canMerge == true ? "Confirm combination" : "Preview combination") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(selected.count < 2 || busy || (preview != nil && preview?.canMerge == false))
            .padding().background(.bar)
        }
        .confirmationDialog("Combine these activities?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Combine in Quantivita") {
                Task {
                    busy = true; defer { busy = false }
                    do { try await model.confirmWorkoutMerge(ids: selected, strategy: strategy); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("You can undo this from the combined activity. Source activities remain unchanged.") }
    }
    private func loadPreview() async {
        busy = true; error = nil; preview = nil
        defer { busy = false }
        do { preview = try await model.previewWorkoutMerge(ids: selected, strategy: strategy) }
        catch { self.error = error.localizedDescription }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var undoing = false
    @State private var undoConfirmation = false
    @State private var mergeError: String?
    let workout: Workout

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: workout.progressaDetails != nil ? "dumbbell.fill" : workout.typeCode == 3 ? "figure.indoor.cycle" : "figure.run").font(.largeTitle).foregroundStyle(.tint)
                        Text(workout.title).font(.title.bold())
                        Text(workout.startTime.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    MetricPanel(title: "Duration", value: "\(Int(workout.effectiveDurationMinutes)) min", color: .purple)
                    MetricPanel(title: "Energy", value: workout.energyAvailable == false ? "—" : "\(Int(workout.effectiveEnergyKcal)) kcal", color: .orange)
                }
                if workout.typeCode == 3 || workout.merge != nil {
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Measurements").font(.headline)
                            LabeledContent("Distance", value: workout.distanceAvailable == false ? "Unavailable" : "\((workout.distanceMeters / 1000).formatted(.number.precision(.fractionLength(1)))) km")
                            LabeledContent("Average heart rate", value: workout.averageHeartRate > 0 ? "\(Int(workout.averageHeartRate)) bpm" : "Unavailable")
                            LabeledContent("Maximum heart rate", value: workout.maxHeartRate > 0 ? "\(Int(workout.maxHeartRate)) bpm" : "Unavailable")
                            LabeledContent("Average power", value: measurement(workout.avgPowerWatts, unit: "W"))
                            LabeledContent("Maximum power", value: measurement(workout.maxPowerWatts, unit: "W"))
                            LabeledContent("Normalized power", value: measurement(workout.normalizedPowerWatts, unit: "W"))
                            LabeledContent("Average cadence", value: measurement(workout.avgCadenceRpm, unit: "rpm"))
                            LabeledContent("Maximum cadence", value: measurement(workout.maxCadenceRpm, unit: "rpm"))
                            if let elapsed = workout.elapsedDurationMinutes { LabeledContent("Elapsed duration", value: "\(Int(elapsed)) min") }
                            if let note = workout.metricsNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sources").font(.headline)
                        if let sources = workout.merge?.sources ?? workout.duplicateSources {
                            ForEach(sources) { source in
                                VStack(alignment: .leading) {
                                    Text(source.title ?? "Workout").font(.subheadline.bold())
                                    Text("\(source.sourceName ?? source.provider ?? "Unknown") · \(source.importedVia ?? "Unknown channel")").font(.caption)
                                    if let start = source.startTime { Text(start).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        } else { Text("\(workout.sourceName ?? workout.source) · \(workout.importedVia ?? workout.source)") }
                        if let merge = workout.merge {
                            Text("Combined \(merge.createdAt)").font(.caption).foregroundStyle(.secondary)
                            ForEach(merge.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                            Button(undoing ? "Undoing…" : "Undo combination") { undoConfirmation = true }.disabled(undoing)
                        }
                        if let mergeError { Text(mergeError).foregroundStyle(.red) }
                    }
                }
                if let details = workout.progressaDetails {
                    Panel {
                        Text(workout.progressaWorkoutTitle ?? "Progressa workout").font(.title2.bold())
                        Text("Linked Progressa details").font(.caption).foregroundStyle(.purple)
                        Text("Exercises").font(.title2.bold())
                        Text("\(details.exerciseCount) exercises · \(details.totalSets) sets")
                            .foregroundStyle(.secondary)
                        if details.exercises.isEmpty {
                            Text("This cached workout has no exercise details yet. Sync Progressa again.").padding(.top, 8)
                        }
                        ForEach(details.exercises) { exercise in
                            Divider().padding(.vertical, 6)
                            Text(exercise.name).font(.headline)
                            if let group = exercise.muscleGroup, !group.isEmpty { Text(group).font(.caption).foregroundStyle(.secondary) }
                            ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                                HStack {
                                    Text("Set \(index + 1)")
                                    if set.isWarmup == true { Text("WARM-UP").font(.caption2.bold()).foregroundStyle(.orange) }
                                    Spacer()
                                    Text(setLabel(set)).monospacedDigit()
                                }.font(.subheadline).padding(.top, 3)
                            }
                        }
                        if let id = workout.externalWorkoutId,
                           let url = URL(string: "progressa:///workout/\(id)") {
                            Link("Open full workout in Progressa", destination: url)
                                .buttonStyle(.bordered).padding(.top, 10)
                        }
                    }
                }
            }.padding()
        }.background(QuantivitaTheme.background).navigationBarTitleDisplayMode(.inline)
    }

    private func setLabel(_ set: ProgressaSet) -> String {
        var parts: [String] = []
        if let base = set.baseWeightKg, base > 0, let added = set.addedWeightKg { parts.append("Base \(base.formatted()) + added \(added.formatted()) kg") }
        if let weight = set.totalWeightKg ?? set.weightKg { parts.append("\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg") }
        if let reps = set.reps { parts.append("× \(reps)") }
        if let rir = set.rir { parts.append("RIR \(rir.formatted(.number.precision(.fractionLength(0...1))))") }
        if let side = set.side, !side.isEmpty { parts.append(side.capitalized) }
        return parts.isEmpty ? "Recorded" : parts.joined(separator: " · ")
    }
    private func measurement(_ value: Double?, unit: String) -> String {
        value.map { "\(Int($0)) \(unit)" } ?? "Unavailable"
    }

}

/// Non-interactive map that draws the combined GPS route as a polyline.
/// Uses MKMapView so it works on the iOS 16 deployment target.
struct RouteMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard coordinates.count >= 2 else { return }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        map.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemOrange
            renderer.lineWidth = 4
            return renderer
        }
    }
}
