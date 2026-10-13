import SwiftUI
import SwiftData

/// History tab. Top to bottom: a week you can page through, with day bars
/// you can tap to see that day's workouts right underneath; that week's
/// per-muscle volume; the top insights; and every workout ever logged.
struct HistoryView: View {
    var profile: UserProfile
    @Environment(\.modelContext) private var context

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var allSessions: [WorkoutSession]

    @Query(sort: \CardioEntry.date, order: .reverse)
    private var allCardio: [CardioEntry]

    /// 0 = this week, -1 = last week, and so on.
    @State private var weekOffset = 0
    /// Tapped day bar (0 = Monday). nil shows the whole week.
    @State private var selectedDay: Int?
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

    // MARK: Week math

    /// Monday-start calendar for the week view, regardless of region.
    private var mondayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Monday, midnight, of the week being shown.
    private var weekStart: Date {
        let calendar = mondayCalendar
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let shifted = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeek) ?? thisWeek
        return calendar.startOfDay(for: shifted)
    }

    private var weekEnd: Date {
        mondayCalendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
    }

    private func dayStart(_ index: Int) -> Date {
        mondayCalendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
    }

    private var weekSessions: [WorkoutSession] {
        sessions.filter { $0.date >= weekStart && $0.date < weekEnd }
    }

    private func sessions(onDay index: Int) -> [WorkoutSession] {
        let start = dayStart(index)
        let end = mondayCalendar.date(byAdding: .day, value: 1, to: start) ?? start
        return weekSessions.filter { $0.date >= start && $0.date < end }
    }

    private var dayVolumes: [Double] {
        (0..<7).map { TrainingMath.totalVolume(sessions: sessions(onDay: $0)) }
    }

    /// Days that have any workout logged (cardio-only days included).
    private var daysWithWorkouts: Set<Int> {
        Set((0..<7).filter { !sessions(onDay: $0).isEmpty })
    }

    /// Today's bar index when the shown week is the current one.
    private var todayIndex: Int? {
        guard weekOffset == 0 else { return nil }
        let days = mondayCalendar.dateComponents([.day], from: weekStart, to: Date()).day ?? 0
        return min(max(days, 0), 6)
    }

    private var weekMuscles: [MuscleVolume] {
        TrainingMath.topMuscles(sets: weekSessions.flatMap(\.sets))
    }

    private var weekCardioMinutes: Double {
        cardioEntries
            .filter { $0.date >= weekStart && $0.date < weekEnd }
            .reduce(0) { $0 + $1.durationMin }
    }

    private var weekTitle: String {
        if weekOffset == 0 { return "This week" }
        if weekOffset == -1 { return "Last week" }
        let end = mondayCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) \u{2013} \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Workouts listed under the bars: the tapped day, or the whole week.
    private var listedSessions: [WorkoutSession] {
        if let selectedDay { return sessions(onDay: selectedDay) }
        return weekSessions
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                weekSection
                musclesSection
                insightsSection
                allWorkoutsSection
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                if let session = sessions.first(where: { $0.id == id }) {
                    SessionDetailView(session: session, profile: profile)
                } else {
                    ContentUnavailableView("Workout not found", systemImage: "dumbbell")
                }
            }
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

    // MARK: Sections

    private var weekSection: some View {
        Section {
            HStack {
                Button {
                    changeWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous week")
                Spacer()
                Text(weekTitle)
                    .font(.headline)
                Spacer()
                Button {
                    changeWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(weekOffset >= 0)
                .accessibilityLabel("Next week")
            }
            // Two buttons in one row: without this, a tap anywhere on the
            // row fires both.
            .buttonStyle(.borderless)

            WeekVolumeBars(
                volumes: dayVolumes,
                todayIndex: todayIndex,
                selectedIndex: selectedDay,
                markedDays: daysWithWorkouts
            ) { index in
                selectedDay = (selectedDay == index) ? nil : index
            }

            Text(selectedDay == nil
                 ? "Tap a day to see just that day."
                 : "Showing \(dayStart(selectedDay ?? 0).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) \u{00B7} tap it again for the whole week.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if listedSessions.isEmpty {
                Text(selectedDay == nil ? "No workouts logged this week." : "Rest day \u{2014} nothing logged.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(listedSessions, id: \.id) { session in
                    sessionLink(session)
                }
            }

            if weekCardioMinutes > 0 {
                Text("\(Int(weekCardioMinutes)) min of cardio this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var musclesSection: some View {
        if !weekMuscles.isEmpty {
            Section {
                let maxVolume = weekMuscles.map(\.volume).max() ?? 1
                ForEach(weekMuscles) { muscle in
                    MuscleVolumeRow(group: muscle.group, volume: muscle.volume, maxVolume: maxVolume)
                }
            } header: {
                Text("Volume by muscle \u{00B7} \(weekTitle.lowercased())")
            } footer: {
                Text("Weight \u{00D7} reps. Main muscles get full credit, helper muscles half.")
            }
        }
    }

    private var insightsSection: some View {
        Section {
            ForEach(insights.prefix(3)) { insight in
                InsightCard(insight: insight)
            }
            NavigationLink {
                InsightsListView(insights: insights)
            } label: {
                Label("All insights (\(insights.count))", systemImage: "lightbulb")
            }
            NavigationLink {
                MetricsExplainerView()
            } label: {
                Label("How Forge measures", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Insights \u{00B7} last 7 days")
        }
    }

    private var allWorkoutsSection: some View {
        Section {
            if sessions.isEmpty {
                Text("No workouts yet \u{2014} start one from the Workout tab.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions, id: \.id) { session in
                    sessionLink(session)
                }
            }
        } header: {
            Text("All workouts")
        } footer: {
            if !sessions.isEmpty {
                Text("Tap a workout for details or to change its date. Swipe left to delete.")
            }
        }
    }

    /// A tappable workout row. Value-based navigation, so the detail screen
    /// is only built when you actually open it.
    private func sessionLink(_ session: WorkoutSession) -> some View {
        NavigationLink(value: session.id) {
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

    // MARK: Actions

    private func changeWeek(by delta: Int) {
        let target = min(0, weekOffset + delta)
        guard target != weekOffset else { return }
        weekOffset = target
        selectedDay = nil
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

/// Every insight for the last 7 days, with the honesty note.
struct InsightsListView: View {
    var insights: [Insight]

    var body: some View {
        List {
            Section {
                Text("Based on your last 7 days. Volume landmarks are expert estimates (Renaissance Periodization MV/MEV/MAV/MRV framework), not lab-measured laws. Ranges, not promises.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One row in a workout list: date, and what was done.
struct SessionRow: View {
    var session: WorkoutSession
    var cardio: [CardioEntry]

    private var detail: String {
        var parts: [String] = []
        let exercises = TrainingMath.distinctExerciseCount(session: session)
        if exercises > 0 {
            let word = exercises == 1 ? "exercise" : "exercises"
            parts.append("\(exercises) \(word)")
            parts.append("\(session.sets.count) sets")
            parts.append("\(Int(TrainingMath.volumeLoad(sets: session.sets).rounded()).formatted()) lb")
        }
        let minutes = cardio.reduce(0) { $0 + $1.durationMin }
        if minutes > 0 {
            parts.append("\(Int(minutes)) min cardio")
        }
        return parts.isEmpty ? "No sets logged" : parts.joined(separator: " \u{00B7} ")
    }

    /// The first few exercise names, so rows are recognizable at a glance.
    private var exerciseNames: String {
        let names = TrainingMath.exerciseGroups(sets: session.sets).map(\.name) + cardio.map(\.exerciseName)
        guard !names.isEmpty else { return "" }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? shown + " +\(names.count - 3)" : shown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.headline)
            if !exerciseNames.isEmpty {
                Text(exerciseNames)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Seven bars, Monday to Sunday, showing volume lifted per day. Each day is
/// a button when `onSelect` is set.
struct WeekVolumeBars: View {
    var volumes: [Double] // 7 values, Mon...Sun
    var todayIndex: Int? = nil
    var selectedIndex: Int? = nil
    /// Days with any workout (a cardio-only day has no lifting volume but
    /// still gets a dot, so it doesn't look empty).
    var markedDays: Set<Int> = []
    var onSelect: ((Int) -> Void)? = nil

    private let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let maxVolume = max(volumes.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let volume = index < volumes.count ? volumes[index] : 0
                let isSelected = index == selectedIndex
                let isDimmed = selectedIndex != nil && !isSelected
                Button {
                    onSelect?(index)
                } label: {
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(volume > 0 ? AnyShapeStyle(ForgeTheme.voltGradient) : AnyShapeStyle(ForgeTheme.track))
                            .frame(height: 8 + 92 * (volume / maxVolume))
                            .opacity(isDimmed ? 0.35 : 1)
                        Circle()
                            .fill(markedDays.contains(index) ? ForgeTheme.volt : .clear)
                            .frame(width: 5, height: 5)
                        Text(dayLetters[index])
                            .font(.caption)
                            .fontWeight(index == todayIndex || isSelected ? .bold : .regular)
                            .foregroundStyle(index == todayIndex || isSelected ? AnyShapeStyle(ForgeTheme.volt) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                // Borderless so each day is its own tap target inside a List
                // row (the default style turns the whole row into one button).
                .buttonStyle(.borderless)
                .disabled(onSelect == nil)
                .accessibilityLabel("\(dayLetters[index]): \(Int(volume)) pounds")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(height: 140)
        .padding(.vertical, 4)
        .animation(.snappy, value: volumes)
        .animation(.snappy, value: selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
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
            Text("\(Int(volume.rounded()).formatted())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
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

/// Full detail for one past session: recap + every logged set, and a way
/// to move the workout to the day it actually happened.
struct SessionDetailView: View {
    var session: WorkoutSession
    var profile: UserProfile

    @Environment(\.modelContext) private var context

    @Query(sort: \CardioEntry.date)
    private var allCardio: [CardioEntry]

    @State private var showDateSheet = false
    @State private var newDate = Date()
    @State private var dateError: String?

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
                Button {
                    newDate = session.startTime
                    showDateSheet = true
                } label: {
                    Label(session.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()), systemImage: "calendar")
                        .font(.subheadline)
                }

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
                                     : "\(set.reps) reps \u{00B7} no added weight")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                        Text("Volume: \(Int(TrainingMath.volumeLoad(sets: group.sets).rounded()).formatted()) lb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .navigationTitle(Text(session.date, format: .dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Change date") {
                    newDate = session.startTime
                    showDateSheet = true
                }
            }
        }
        .sheet(isPresented: $showDateSheet) {
            NavigationStack {
                Form {
                    DatePicker("Workout date", selection: $newDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(ForgeTheme.volt)
                    Text("Moves this workout, and any cardio logged with it, to the day you pick.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dateError {
                        Text(dateError)
                            .foregroundStyle(ForgeTheme.danger)
                    }
                }
                .navigationTitle("Change date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDateSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { moveWorkout(to: newDate) }
                    }
                }
            }
        }
    }

    /// Shifts the workout and its paired cardio by the same amount, so they
    /// stay paired (cardio is matched to a workout by start time).
    private func moveWorkout(to date: Date) {
        let paired = sessionCardio
        let shift = date.timeIntervalSince(session.startTime)
        guard shift != 0 else {
            showDateSheet = false
            return
        }
        session.startTime = session.startTime.addingTimeInterval(shift)
        session.date = session.date.addingTimeInterval(shift)
        session.endTime = session.endTime?.addingTimeInterval(shift)
        for entry in paired {
            entry.date = entry.date.addingTimeInterval(shift)
        }
        do {
            try context.save()
            dateError = nil
            showDateSheet = false
        } catch {
            context.rollback()
            dateError = "Couldn't move it: \(error.localizedDescription)"
        }
    }
}
