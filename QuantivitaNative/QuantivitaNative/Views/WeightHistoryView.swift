import Charts
import SwiftUI

struct WeightHistoryView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "1W", month = "1M", threeMonths = "3M", sixMonths = "6M", year = "1Y"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            case .sixMonths: return 182
            case .year: return 365
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @State private var range: Range = .month

    private var filteredSamples: [WeightSample] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) else {
            return model.weightHistory
        }
        return model.weightHistory.filter { $0.date >= cutoff }
    }

    private var change: Double? {
        guard filteredSamples.count > 1, let first = filteredSamples.first, let last = filteredSamples.last else { return nil }
        return last.kg - first.kg
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                if filteredSamples.isEmpty {
                    Text("No weight data for this period.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(filteredSamples.last?.kg ?? 0, format: .number.precision(.fractionLength(1))) kg")
                            .font(.title.bold())
                        if let change {
                            Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) kg since \(rangeStartLabel)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Chart(filteredSamples) { sample in
                        LineMark(x: .value("Date", sample.date), y: .value("Weight", sample.kg))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", sample.date), y: .value("Weight", sample.kg))
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }

            if !filteredSamples.isEmpty {
                Section("Entries") {
                    ForEach(filteredSamples.reversed()) { sample in
                        HStack {
                            Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("\(sample.kg.formatted(.number.precision(.fractionLength(1)))) kg")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Weight")
        .task { await model.loadWeightHistory() }
    }

    private var rangeStartLabel: String {
        filteredSamples.first?.date.formatted(date: .abbreviated, time: .omitted) ?? ""
    }
}
