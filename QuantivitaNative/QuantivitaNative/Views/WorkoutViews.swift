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
            ForEach(model.workouts) { workout in
                NavigationLink(value: workout) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(workout.title).font(.headline); if workout.progressaDetails != nil { Text("PROGRESSA LINKED").font(.caption2.bold()).foregroundStyle(.purple) } }
                        Text(workout.startTime.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Text("\(Int(workout.effectiveDurationMinutes)) min · \(Int(workout.effectiveEnergyKcal)) kcal").font(.subheadline)
                    }.padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if model.workouts.isEmpty {
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
                NavigationLink { MergeLabView() } label: { Label("Merge Lab", systemImage: "square.stack.3d.up") }
            }
        }
        .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        .refreshable { await model.refreshAll() }
    }
}

struct MergeLabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected = Set<String>()
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeLoading = false

    private var workouts: [Workout] { model.workouts.filter { $0.startTime <= .now } }
    private var chosen: [Workout] { workouts.filter { selected.contains($0.id) } }
    private var selectionToken: String { selected.sorted().joined(separator: ",") }
    private var averageHeartRate: Double { WorkoutFidelity.weightedAverageHeartRate(for: chosen) }
    private var maxHeartRate: Double { chosen.map(\.maxHeartRate).filter { $0 > 0 }.max() ?? 0 }

    var body: some View {
        List {
            Section {
                Text("Select at least two HealthKit or Progressa workouts. Merge Lab writes one combined workout and keeps every source workout unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Workouts") {
                ForEach(workouts) { workout in
                    Button { toggle(workout.id) } label: {
                        HStack {
                            Image(systemName: selected.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(workout.id) ? QuantivitaTheme.accent : .secondary)
                            VStack(alignment: .leading) {
                                Text(workout.title).foregroundStyle(.primary)
                                Text(workout.startTime.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(workout.effectiveDurationMinutes)) min").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if chosen.count >= 2 {
                Section("Merged preview") {
                    LabeledContent("Workouts", value: "\(chosen.count)")
                    LabeledContent("Elapsed", value: "\(Int(elapsedMinutes)) min")
                    LabeledContent("Moving", value: "\(Int(chosen.reduce(0) { $0 + $1.effectiveDurationMinutes })) min")
                    LabeledContent("Energy", value: "\(Int(chosen.reduce(0) { $0 + $1.effectiveEnergyKcal })) kcal")
                    LabeledContent("Distance", value: distanceLabel(chosen.reduce(0) { $0 + $1.distanceMeters }))
                    if averageHeartRate > 0 { LabeledContent("Avg heart rate", value: "\(Int(averageHeartRate)) bpm") }
                    if maxHeartRate > 0 { LabeledContent("Max heart rate", value: "\(Int(maxHeartRate)) bpm") }
                }
                Section("Route") {
                    if routeCoordinates.count >= 2 {
                        RouteMapView(coordinates: routeCoordinates)
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                    } else if routeLoading {
                        Label("Loading GPS route…", systemImage: "map").font(.footnote).foregroundStyle(.secondary)
                    } else if chosen.contains(where: { $0.hasRoute }) {
                        Label("The GPS route couldn’t be read. Allow Quantivita to read Workout Routes in Settings ▸ Health ▸ Data Access & Devices ▸ Quantivita.", systemImage: "mappin.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Label("None of the selected workouts has a GPS route (they weren’t recorded with outdoor GPS).", systemImage: "map")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("Heart rate, GPS route and ambient temperature from each workout are carried into the merged Apple Health workout.", systemImage: "checkmark.seal")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Merge Lab")
        .task(id: selectionToken) {
            guard chosen.count >= 2 else { routeCoordinates = []; routeLoading = false; return }
            routeLoading = true
            routeCoordinates = await model.mergedRouteCoordinates(ids: selected)
            routeLoading = false
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Export to Apple Health") {
                    Task { _ = await model.exportMergedWorkout(ids: selected) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button(model.isUploadingStrava ? "Waiting for Strava…" : (model.stravaConnected ? "Upload directly to Strava" : "Connect and upload to Strava")) {
                    Task { _ = await model.uploadMergedWorkoutToStrava(ids: selected) }
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
            .disabled(chosen.count < 2 || model.isUploadingStrava)
            .padding().frame(maxWidth: .infinity).background(.bar)
        }
    }

    private var elapsedMinutes: Double {
        guard let start = chosen.map(\.startTime).min(),
              let end = chosen.map({ $0.startTime.addingTimeInterval($0.effectiveDurationMinutes * 60) }).max() else { return 0 }
        return end.timeIntervalSince(start) / 60
    }

    private func toggle(_ id: String) {
        if !selected.insert(id).inserted { selected.remove(id) }
    }

    private func distanceLabel(_ meters: Double) -> String {
        meters > 0 ? "\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) km" : "—"
    }
}

struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel {
                    Image(systemName: workout.progressaDetails != nil ? "dumbbell.fill" : "figure.run").font(.largeTitle).foregroundStyle(.purple)
                    Text(workout.title).font(.title.bold())
                    Text(workout.startTime.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    MetricPanel(title: "Duration", value: "\(Int(workout.effectiveDurationMinutes)) min", color: .purple)
                    MetricPanel(title: "Energy", value: "\(Int(workout.effectiveEnergyKcal)) kcal", color: .orange)
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
        if let weight = set.weightKg { parts.append("\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg") }
        if let reps = set.reps { parts.append("× \(reps)") }
        if let rir = set.rir { parts.append("RIR \(rir.formatted(.number.precision(.fractionLength(0...1))))") }
        if let side = set.side, !side.isEmpty { parts.append(side.capitalized) }
        return parts.isEmpty ? "Recorded" : parts.joined(separator: " · ")
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
