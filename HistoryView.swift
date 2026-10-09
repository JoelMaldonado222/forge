import SwiftUI
import SwiftData

/// History tab: this week's at-a-glance bars (Mon-Sun volume + per-muscle
/// volume) so busy weeks stop blurring together, plus the full session list.
struct HistoryView: View {
    var profile: UserProfile
    @Environment(\.modelContext) private var context

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var allSessions: [WorkoutSession]

    @Query(sort: \CardioEntry.date, order: .reverse)
    private var allCardio: [CardioEntry]

    @State private var pendingDelete: WorkoutSession?
    @State private var deleteError: String?

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

    /// Monday-start calendar for the week view, regardless of region.
    private var mondayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Start of the current week (Monday, midnight).
    private var weekStart: Date {
        let calendar = mondayCalendar
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.startOfDay(for: start)
    }

    private var weekEnd: Date {
        mondayCalendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
    }

    private var thisWeekSessions: [WorkoutSession] {
        sessions.filter { $0.date >= weekStart && $0.date < weekEnd }
    }

    private var dayVolumes: [Double] {
        let calendar = mondayCalendar
        return (0..<7).map { offset in
            let start = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let daySessions = thisWeekSessions.filter { $0.date >= start && $0.date < end }
            return TrainingMath.totalVolume(sessions: daySessions)
        }
    }

    /// 0 = Monday ... 6 = Sunday, for highlighting today's bar.
    private var todayIndex: Int {
        let days = mondayCalendar.dateComponents([.day], from: weekStart, to: Date()).day ?? 0
        return min(max(days, 0), 6)
    }

    private var weekMuscles: [MuscleVolume] {
        TrainingMath.topMuscles(sets: thisWeekSessions.flatMap(\.sets))
    }

    private var weekCardioMinutes: Double {
        cardioEntries
            .filter { $0.date >= weekStart && $0.date < weekEnd }
            .reduce(0) { $0 + $1.durationMin }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This week") {
                    WeekVolumeBars(volumes: dayVolumes, todayIndex: todayIndex)
                    if weekCardioMinutes > 0 {
                        Text("\(Int(weekCardioMinutes)) min of cardio this week")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if weekMuscles.isEmpty {
                        Text("No lifting logged yet this week (since Monday).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        let maxVolume = weekMuscles.map(\.volume).max() ?? 1
                        ForEach(weekMuscles) { muscle in
                            MuscleVolumeRow(group: muscle.group, volume: muscle.volume, maxVolume: maxVolume)
                        }
                    }
                }

                Section {
                    Text("Based on your last 7 days. Volume landmarks are expert estimates (Renaissance Periodization MV/MEV/MAV/MRV framework), not lab-measured laws. Ranges, not promises.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(insights) { insight in
                        InsightCard(insight: insight)
                    }
                } header: {
                    Text("Insights")
                }

                Section {
                    if sessions.isEmpty {
                        Text("No workouts yet \u{2014} start one from the Workout tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions, id: \.id) { session in
                            NavigationLink {
                                SessionDetailView(session: session, profile: profile)
                            } label: {
                                SessionRow(session: session, cardio: TrainingMath.cardio(for: session, in: cardioEntries))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = session
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Sessions")
                } footer: {
                    if !sessions.isEmpty {
                        Text("Swipe left on a workout to delete it.")
                    }
                }
            }
            .navigationTitle("History")
            .confirmationDialog("Delete this workout?", isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete) { session in
                Button("Delete workout", role: .destructive) { delete(session) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its sets and any cardio logged with it are removed for good. A backup file is the only way to get it back.")
            }
            .alert("Couldn't delete", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func delete(_ session: WorkoutSession) {
        let pairedCardio = TrainingMath.cardio(for: session, in: cardioEntries)
        let sets = session.sets
        for entry in pairedCardio { context.delete(entry) }
        for set in sets { context.delete(set) }
        context.delete(session)
        do {
            try context.save()
        } catch {
            context.rollback()
            deleteError = error.localizedDescription
        }
    }
}

/// One row in the session list: date, time, and what was done.
struct SessionRow: View {
    var session: WorkoutSession
    var cardio: [CardioEntry]

    private var detail: String {
        var parts: [String] = []
        let exercises = TrainingMath.distinctExerciseCount(session: session)
        if exercises > 0 {
            let word = exercises == 1 ? "exercise" : "exercises"
            parts.append("\(exercises) \(word)")
            parts.append("\(Int(TrainingMath.volumeLoad(sets: session.sets))) lb")
        }
        let minutes = cardio.reduce(0) { $0 + $1.durationMin }
        if minutes > 0 {
            parts.append("\(Int(minutes)) min cardio")
        }
        return parts.isEmpty ? "No sets logged" : parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(session.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.headline)
                Text(session.date, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Seven bars, Monday to Sunday, showing volume lifted per day.
struct WeekVolumeBars: View {
    var volumes: [Double] // 7 values, Mon...Sun
    var todayIndex: Int? = nil

    private let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let maxVolume = max(volumes.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let volume = index < volumes.count ? volumes[index] : 0
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(volume > 0 ? AnyShapeStyle(ForgeTheme.voltGradient) : AnyShapeStyle(ForgeTheme.track))
                        .frame(height: 8 + 92 * (volume / maxVolume))
                    Text(dayLetters[index])
                        .font(.caption)
                        .fontWeight(index == todayIndex ? .bold : .regular)
                        .foregroundStyle(index == todayIndex ? AnyShapeStyle(ForgeTheme.volt) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dayLetters[index]): \(Int(volume)) pounds")
            }
        }
        .frame(height: 132)
        .padding(.vertical, 4)
        .animation(.snappy, value: volumes)
    }
}

/// One horizontal bar of volume for a muscle group.
struct MuscleVolumeRow: View {
    var group: MuscleGroup
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
        case .good: return ForgeTheme.success
        case .warning: return ForgeTheme.warning
        case .info: return ForgeTheme.info
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

    /// Cardio logged in this same workout (not just the same day), for this profile.
    private var sessionCardio: [CardioEntry] {
        TrainingMath.cardio(for: session, in: allCardio.filter { $0.ownerID == profile.id })
    }

    /// Exercises in the order they were logged.
    private var grouped: [ExerciseGroup] {
        TrainingMath.exerciseGroups(sets: session.sets)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(SummaryGenerator.sessionRecap(name: profile.name, session: session, profile: profile, cardio: sessionCardio))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeCard(cornerRadius: 12)

                ForEach(grouped) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name)
                            .font(.headline)
                        ForEach(group.sets, id: \.id) { set in
                            HStack {
                                Text("Set \(set.setNumber)")
                                Spacer()
                                Text(set.weightLbs > 0
                                     ? "\(set.reps) reps \u{00D7} \(ForgeInput.display(set.weightLbs)) lb"
                                     : "\(set.reps) reps \u{00B7} bodyweight")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeCard(cornerRadius: 12)
                }

                ForEach(sessionCardio, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.exerciseName)
                            .font(.headline)
                        HStack {
                            Text("\(ForgeInput.display(entry.durationMin)) min")
                            Spacer()
                            if let miles = entry.distanceMi, miles > 0 {
                                Text("\(ForgeInput.display(miles)) mi")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeCard(cornerRadius: 12)
                }
            }
            .padding()
        }
        .navigationTitle(Text(session.date, style: .date))
        .navigationBarTitleDisplayMode(.inline)
    }
}
