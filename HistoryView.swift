import SwiftUI
import SwiftData

/// History tab: this week's at-a-glance bars (Mon-Sun volume + per-muscle
/// volume) so busy weeks stop blurring together, plus the full session list.
struct HistoryView: View {
    var profile: UserProfile

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var allSessions: [WorkoutSession]

    @Query(sort: \CardioEntry.date, order: .reverse)
    private var allCardio: [CardioEntry]

    /// Only the active profile's sessions — each person's history is separate.
    private var sessions: [WorkoutSession] {
        allSessions.filter { $0.ownerID == profile.id }
    }

    private var cardioEntries: [CardioEntry] {
        allCardio.filter { $0.ownerID == profile.id }
    }

    private var insights: [Insight] {
        InsightsEngine.weeklyInsights(
            profileID: profile.id,
            sessions: sessions,
            cardio: cardioEntries,
            bodyWeightKg: profile.weightLbs / 2.20462
        )
    }

    /// Start of the current week (Monday).
    private var weekStart: Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let start = calendar.date(from: components) ?? Date()
        return calendar.startOfDay(for: start)
    }

    private var dayVolumes: [Double] {
        let calendar = Calendar.current
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let daySessions = sessions.filter { $0.date >= start && $0.date < end }
            return TrainingMath.totalVolume(sessions: daySessions)
        }
    }

    private var weekMuscles: [MuscleVolume] {
        let calendar = Calendar.current
        let start = weekStart
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? Date()
        let weekSessions = sessions.filter { $0.date >= start && $0.date < end }
        return TrainingMath.topMuscles(sets: weekSessions.flatMap(\.sets))
    }

    private var weekCardioMinutes: Double {
        let calendar = Calendar.current
        let start = weekStart
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? Date()
        return cardioEntries
            .filter { $0.date >= start && $0.date < end }
            .reduce(0) { $0 + $1.durationMin }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This week") {
                    WeekVolumeBars(volumes: dayVolumes)
                    if weekCardioMinutes > 0 {
                        Text("\(Int(weekCardioMinutes)) min of cardio this week")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if weekMuscles.isEmpty {
                        Text("No training logged in the last 7 days.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        let maxVolume = weekMuscles.map(\.volume).max() ?? 1
                        ForEach(weekMuscles) { muscle in
                            MuscleVolumeRow(group: muscle.group, volume: muscle.volume, maxVolume: maxVolume)
                        }
                    }
                }

                Section("Insights") {
                    Text("Volume landmarks are expert estimates (Renaissance Periodization MV/MEV/MAV/MRV framework), not lab-measured laws. Ranges, not promises.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(insights) { insight in
                        InsightCard(insight: insight)
                    }
                }

                Section("Sessions") {
                    if sessions.isEmpty {
                        Text("No workouts yet \u{2014} start one from the Workout tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session, profile: profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.date, style: .date)
                                        .font(.headline)
                                    Text("\(TrainingMath.distinctExerciseCount(session: session)) exercises \u{00B7} \(Int(TrainingMath.volumeLoad(sets: session.sets))) lb")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

/// Seven bars, Monday to Sunday, showing volume lifted per day.
struct WeekVolumeBars: View {
    var volumes: [Double] // 7 values, Mon...Sun

    private let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let maxVolume = max(volumes.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(volumes[index] > 0 ? ForgeTheme.volt : Color.gray.opacity(0.25))
                        .frame(height: 8 + 92 * (volumes[index] / maxVolume))
                    Text(dayLetters[index])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 132)
        .padding(.vertical, 4)
    }
}

/// One horizontal bar of volume for a muscle group.
struct MuscleVolumeRow: View {    var group: MuscleGroup
    var volume: Double
    var maxVolume: Double

    var body: some View {
        HStack {
            Text(group.displayName)
                .font(.subheadline)
                .frame(width: 92, alignment: .leading)
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(ForgeTheme.volt.opacity(0.85))
                    .frame(width: max(4, geometry.size.width * CGFloat(volume / max(maxVolume, 1))))
            }
            .frame(height: 10)
            Text("\(Int(volume))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

/// One evidence-framed observation card, colored by tone.
struct InsightCard: View {
    var insight: Insight

    private var toneColor: Color {
        switch insight.tone {
        case .good: return ForgeTheme.volt
        case .warning: return .orange
        case .info: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(toneColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline)
                    .bold()
                Text(insight.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Full detail for one past session: recap + every logged set.
struct SessionDetailView: View {
    var session: WorkoutSession
    var profile: UserProfile

    @Query(sort: \CardioEntry.date)
    private var allCardio: [CardioEntry]

    /// Cardio logged on the same calendar day as this session, for this profile.
    private var sessionCardio: [CardioEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: session.date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return allCardio.filter { $0.ownerID == profile.id && $0.date >= start && $0.date < end }
    }

    private var grouped: [(id: String, name: String, sets: [LoggedSet])] {
        var order: [String] = []
        var dict: [String: [LoggedSet]] = [:]
        for set in session.sets {
            if dict[set.exerciseId] == nil { order.append(set.exerciseId) }
            dict[set.exerciseId, default: []].append(set)
        }
        return order.compactMap { id in
            guard let sets = dict[id] else { return nil }
            return (id, sets.first?.exerciseName ?? "Exercise", sets.sorted { $0.setNumber < $1.setNumber })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(SummaryGenerator.sessionRecap(name: profile.name, session: session, profile: profile, cardio: sessionCardio))
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                ForEach(grouped, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name)
                            .font(.headline)
                        ForEach(group.sets) { set in
                            HStack {
                                Text("Set \(set.setNumber)")
                                Spacer()
                                Text("\(set.reps) reps \u{00D7} \(String(format: "%g", set.weightLbs)) lb")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ForEach(sessionCardio, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.exerciseName)
                            .font(.headline)
                        HStack {
                            Text("\(Int(entry.durationMin)) min")
                            Spacer()
                            if let miles = entry.distanceMi, miles > 0 {
                                Text("\(String(format: "%g", miles)) mi")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle(Text(session.date, style: .date))
        .navigationBarTitleDisplayMode(.inline)
    }
}
