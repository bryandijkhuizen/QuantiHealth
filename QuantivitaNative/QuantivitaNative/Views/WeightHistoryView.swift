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
        /// Longer ranges collapse daily HealthKit samples into weekly averages so the chart doesn't drown in points.
        var aggregatesByWeek: Bool {
            switch self {
            case .week, .month: return false
            case .threeMonths, .sixMonths, .year: return true
            }
        }
    }

    struct ChartPoint: Identifiable, Equatable {
        let date: Date
        let kg: Double
        var id: Date { date }
    }

    @EnvironmentObject private var model: AppModel
    @State private var range: Range = .month

    private var filteredSamples: [WeightSample] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) else {
            return model.weightHistory
        }
        return model.weightHistory.filter { $0.date >= cutoff }
    }

    private var chartPoints: [ChartPoint] {
        Self.chartPoints(from: filteredSamples, aggregatesByWeek: range.aggregatesByWeek)
    }

    static func chartPoints(
        from samples: [WeightSample], aggregatesByWeek: Bool, calendar: Calendar = .current
    ) -> [ChartPoint] {
        guard aggregatesByWeek else { return samples.map { ChartPoint(date: $0.date, kg: $0.kg) } }
        let weeks = Dictionary(grouping: samples) { sample in
            calendar.dateInterval(of: .weekOfYear, for: sample.date)?.start ?? sample.date
        }
        return weeks.map { weekStart, samples in
            ChartPoint(date: weekStart, kg: samples.map(\.kg).reduce(0, +) / Double(samples.count))
        }.sorted { $0.date < $1.date }
    }

    private var yAxisDomain: ClosedRange<Double> {
        Self.yAxisDomain(for: chartPoints)
    }

    static func yAxisDomain(for points: [ChartPoint]) -> ClosedRange<Double> {
        let values = points.map(\.kg)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        guard low < high else { return (low - 1)...(high + 1) }
        let padding = max((high - low) * 0.15, 0.5)
        return (low - padding)...(high + padding)
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
                    Chart(chartPoints) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", point.kg))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value("Weight", point.kg))
                            .symbolSize(32)
                    }
                    .chartYScale(domain: yAxisDomain)
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
