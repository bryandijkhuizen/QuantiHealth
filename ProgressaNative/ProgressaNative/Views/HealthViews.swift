import SwiftUI
import MapKit
import UIKit

/// Static GPS route map (polyline + start/finish pins) used in post cards and workout detail.
struct RouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    var height: CGFloat = 150

    var body: some View {
        RouteMap(coordinates: coordinates)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
    }
}

/// MKMapView wrapper so the route renders on iOS 16 (SwiftUI Map polylines are iOS 17+).
private struct RouteMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        guard coordinates.count > 1 else { return }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        if let first = coordinates.first {
            let start = MKPointAnnotation(); start.coordinate = first; start.title = "Start"
            map.addAnnotation(start)
        }
        if let last = coordinates.last {
            let finish = MKPointAnnotation(); finish.coordinate = last; finish.title = "Finish"
            map.addAnnotation(finish)
        }
        map.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

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

struct ProgressaHealthSessionPicker: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let around: Date
    let title: String
    let selection: (ProgressaHealthSession) async -> Bool

    var body: some View {
        NavigationStack {
            List(model.healthSessions) { session in
                Button {
                    Task { if await selection(session) { dismiss() } }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.activityType).font(.headline).foregroundStyle(.primary)
                        Text("\(session.start.formatted(date: .abbreviated, time: .shortened)) · \(duration(session.durationSeconds))")
                            .foregroundStyle(.secondary)
                        let metrics = [
                            session.calories.map { "\(Int($0)) kcal" },
                            session.distanceMeters.map { String(format: "%.2f km", $0 / 1_000) },
                        ].compactMap { $0 }.joined(separator: " · ")
                        if !metrics.isEmpty { Text(metrics).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .overlay {
                if model.isLoadingHealth { ProgressView() }
                else if model.healthSessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.text.square").font(.largeTitle)
                        Text("No Apple Health workouts found").font(.headline)
                        Text("Try a date closer to the workout.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { Button("Cancel") { dismiss() } }
            .task { await model.browseHealthSessions(around: around) }
        }
    }

    private func duration(_ seconds: Int) -> String {
        let hours = seconds / 3_600, minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct ProgressaHealthMetadataSection: View {
    let value: ProgressaHealthMetadata
    @EnvironmentObject private var model: ProgressaModel
    @State private var route: [CLLocationCoordinate2D] = []

    var body: some View {
        Section("Apple Health") {
            Label(value.activityType, systemImage: "heart.fill").foregroundStyle(.red)
            LabeledContent("Time", value: "\(value.start.formatted(date: .omitted, time: .shortened))–\(value.end.formatted(date: .omitted, time: .shortened))")
            if let heartRate = value.averageHeartRate { LabeledContent("Average heart rate", value: "\(Int(heartRate)) bpm") }
            if let maximum = value.maxHeartRate { LabeledContent("Maximum heart rate", value: "\(Int(maximum)) bpm") }
            if let calories = value.calories { LabeledContent("Active energy", value: "\(Int(calories)) kcal") }
            if let distance = value.distanceMeters { LabeledContent("Distance", value: String(format: "%.2f km", distance / 1_000)) }
            LabeledContent("Duration", value: "\(value.durationSeconds / 60) min")
            if !route.isEmpty {
                RouteMapView(coordinates: route).listRowInsets(EdgeInsets())
            }
        }
        .task(id: value.workoutId) { route = await model.healthRoute(for: value) }
    }
}

/// Records a live GPS track (foreground / when-in-use) for an outdoor workout.
final class WorkoutLocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase { case idle, recording, paused }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var coordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var permissionDenied = false

    private let manager = CLLocationManager()
    private var locations: [CLLocation] = []
    private var startDate: Date?
    private var segmentStart: Date?
    private var elapsedBase: TimeInterval = 0
    private var timer: Timer?

    var recordedLocations: [CLLocation] { locations }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = 5
    }

    /// Total distance of a recorded track — kept pure so it can be unit tested.
    static func distance(of locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        return zip(locations, locations.dropFirst()).reduce(0) { $0 + $1.1.distance(from: $1.0) }
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        locations = []; coordinates = []; distanceMeters = 0; elapsed = 0; elapsedBase = 0
        startDate = Date(); segmentStart = Date(); phase = .recording
        manager.startUpdatingLocation(); startTimer()
    }

    func pause() {
        guard phase == .recording else { return }
        elapsedBase += Date().timeIntervalSince(segmentStart ?? Date())
        phase = .paused; manager.stopUpdatingLocation(); stopTimer()
    }

    func resume() {
        guard phase == .paused else { return }
        segmentStart = Date(); phase = .recording
        manager.startUpdatingLocation(); startTimer()
    }

    /// Stops recording and returns the captured span; locations stay available for saving.
    func finish() -> (start: Date, end: Date)? {
        manager.stopUpdatingLocation(); stopTimer()
        let span = startDate.map { ($0, Date()) }
        phase = .idle
        return span
    }

    func reset() {
        manager.stopUpdatingLocation(); stopTimer()
        phase = .idle; locations = []; coordinates = []; distanceMeters = 0
        elapsed = 0; elapsedBase = 0; startDate = nil; segmentStart = nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.phase == .recording, let segmentStart = self.segmentStart else { return }
            self.elapsed = self.elapsedBase + Date().timeIntervalSince(segmentStart)
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permissionDenied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations updates: [CLLocation]) {
        for location in updates where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 {
            if let last = locations.last { distanceMeters += location.distance(from: last) }
            locations.append(location)
            coordinates.append(location.coordinate)
        }
    }
}

struct WorkoutRecordingView: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = WorkoutLocationRecorder()
    @State private var activity: RecordingActivity = .run
    @State private var saving = false
    let onSaved: (Date) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if recorder.coordinates.count > 1 {
                    RouteMapView(coordinates: recorder.coordinates, height: 240)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(height: 240)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "location.viewfinder").font(.largeTitle).foregroundStyle(.secondary)
                                Text(recorder.phase == .idle ? "Press start to record your route." : "Waiting for GPS…")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                }
                Picker("Activity", selection: $activity) {
                    ForEach(RecordingActivity.allCases) { Label($0.rawValue, systemImage: $0.systemImage).tag($0) }
                }.pickerStyle(.segmented).disabled(recorder.phase != .idle)

                HStack(spacing: 28) {
                    stat("Time", durationText(recorder.elapsed))
                    stat("Distance", String(format: "%.2f km", recorder.distanceMeters / 1_000))
                }
                if recorder.permissionDenied {
                    Text("Location access is off. Enable it in Settings to record a route.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
                controls
            }
            .padding()
            .navigationTitle("Record workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { recorder.reset(); dismiss() }.disabled(saving)
                }
            }
            .task { await model.prepareRecordingAuthorization() }
            .interactiveDismissDisabled(recorder.phase != .idle || saving)
        }
    }

    @ViewBuilder private var controls: some View {
        switch recorder.phase {
        case .idle:
            Button { recorder.start() } label: { primaryLabel("Start", "record.circle") }
        case .recording:
            HStack(spacing: 12) {
                Button { recorder.pause() } label: { secondaryLabel("Pause", "pause.circle") }
                Button { Task { await finish() } } label: { primaryLabel("Finish", "stop.circle") }.disabled(saving)
            }
        case .paused:
            HStack(spacing: 12) {
                Button { recorder.resume() } label: { secondaryLabel("Resume", "play.circle") }
                Button { Task { await finish() } } label: { primaryLabel("Finish", "stop.circle") }.disabled(saving)
            }
        }
    }

    private func finish() async {
        saving = true
        let locations = recorder.recordedLocations
        let distance = recorder.distanceMeters
        guard let span = recorder.finish() else { saving = false; dismiss(); return }
        let saved = await model.saveRecordedWorkout(
            activity: activity, start: span.start, end: span.end, distanceMeters: distance, locations: locations
        )
        saving = false
        dismiss()
        if saved { onSaved(span.start) }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func primaryLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
    }

    private func secondaryLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds), hours = total / 3_600, minutes = (total % 3_600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }
}
