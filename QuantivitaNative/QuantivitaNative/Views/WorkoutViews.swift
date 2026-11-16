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
                        Text(workout.energyAvailable == false ? "\(Int(workout.effectiveDurationMinutes)) min" : "\(Int(workout.effectiveDurationMinutes)) min · \(Int(workout.effectiveEnergyKcal)) kcal").font(.subheadline)
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
                    if preview.workout.distanceAvailable != false, preview.workout.distanceMeters > 0 {
                        LabeledContent("Distance", value: "\((preview.workout.distanceMeters / 1000).formatted(.number.precision(.fractionLength(1)))) km")
                    }
                    if preview.workout.energyAvailable != false { LabeledContent("Energy", value: "\(Int(preview.workout.energyKcal)) kcal") }
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
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var undoing = false
    @State private var undoConfirmation = false
    @State private var mergeError: String?
    let workout: Workout

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(workout.progressaDetails != nil ? "Strength training" : workout.typeCode == 3 ? "Cycling" : "Workout",
                              systemImage: workout.progressaDetails != nil ? "dumbbell.fill" : workout.typeCode == 3 ? "figure.indoor.cycle" : "figure.run")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(workout.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(workout.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)

                    Text(workout.distanceAvailable != false && workout.distanceMeters > 0
                         ? "\((workout.distanceMeters / 1000).formatted(.number.precision(.fractionLength(2)))) km"
                         : "\(Int(workout.effectiveDurationMinutes)) min")
                        .font(.system(size: headlineSize, weight: .bold, design: .rounded)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if routeCoordinates.count >= 2 {
                        RouteMapView(coordinates: routeCoordinates)
                            .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Recorded workout route")
                            .accessibilityIdentifier("workoutRoute")
                    }
                    Divider()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metricWidth), alignment: .leading)], spacing: 12) {
                        metric("Duration", value: workout.effectiveDurationMinutes, unit: "min", symbol: "clock")
                        if workout.energyAvailable != false {
                            metric("Energy", value: workout.effectiveEnergyKcal, unit: "kcal", symbol: "flame")
                        }
                        if workout.elevationGainMeters > 0 {
                            metric("Elevation gain", value: workout.elevationGainMeters, unit: "m", symbol: "mountain.2")
                        }
                        if workout.averageHeartRate > 0 {
                            metric("Average heart rate", value: workout.averageHeartRate, unit: "bpm", symbol: "heart")
                        }
                        if workout.maxHeartRate > 0 {
                            metric("Maximum heart rate", value: workout.maxHeartRate, unit: "bpm", symbol: "heart.fill")
                        }
                        if let value = workout.avgPowerWatts { metric("Average power", value: value, unit: "W", symbol: "bolt") }
                        if let value = workout.maxPowerWatts { metric("Maximum power", value: value, unit: "W", symbol: "bolt.fill") }
                        if let value = workout.normalizedPowerWatts { metric("Normalized power", value: value, unit: "W", symbol: "waveform.path") }
                        if let value = workout.avgCadenceRpm { metric("Average cadence", value: value, unit: "rpm", symbol: "arrow.triangle.2.circlepath") }
                        if let value = workout.maxCadenceRpm { metric("Maximum cadence", value: value, unit: "rpm", symbol: "arrow.triangle.2.circlepath") }
                        if let elapsed = workout.elapsedDurationMinutes, elapsed > workout.effectiveDurationMinutes + 1 {
                            metric("Elapsed duration", value: elapsed, unit: "min", symbol: "stopwatch")
                        }
                    }
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                if let note = workout.metricsNote, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup("Sources") {
                            if let sources = workout.merge?.sources ?? workout.duplicateSources {
                                ForEach(sources) { source in
                                    VStack(alignment: .leading) {
                                        Text(source.title ?? "Workout").font(.subheadline.bold())
                                        Text([source.sourceName ?? source.provider, source.importedVia].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
                                        if let start = source.startTime { Text(start).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            } else { Text("\(workout.sourceName ?? workout.source) · \(workout.importedVia ?? workout.source)") }
                        }
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
        .confirmationDialog("Undo this combination?", isPresented: $undoConfirmation, titleVisibility: .visible) {
            Button("Undo combination") {
                guard let merge = workout.merge else { return }
                Task {
                    undoing = true
                    defer { undoing = false }
                    do { try await model.undoWorkoutMerge(id: merge.id); dismiss() }
                    catch { mergeError = error.localizedDescription }
                }
            }
        } message: { Text("The original activities will appear separately in your log again.") }
        .task(id: workout.id) {
            routeCoordinates = await model.mergedRouteCoordinates(ids: Set(workout.merge?.sourceWorkoutIds ?? [workout.id]))
        }
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
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var metricWidth: CGFloat = 130

    private func metric(_ title: String, value: Double, unit: String, symbol: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)")
                .font(.title2.weight(.semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("\(title), \(value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)")
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
