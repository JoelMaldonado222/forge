import SwiftUI
import SwiftData

/// The "Workout" tab: home -> active logging (add exercises as you go) -> summary.
struct WorkoutFlowView: View {
    var profile: UserProfile
    @State private var path = NavigationPath()
    @State private var draftStartTime = Date()
    @State private var finishedSession: WorkoutSession?
    @State private var finishedCardio: [CardioEntry] = []
    /// An unfinished workout found on disk, offered on the home screen.
    @State private var savedDraft: WorkoutDraftSnapshot?
    /// The draft the logging screen should open with (nil = fresh workout).
    @State private var resumeDraft: WorkoutDraftSnapshot?
    @State private var showReplaceConfirm = false

    enum Route: Hashable {
        case active
        case summary
    }

    var body: some View {
        NavigationStack(path: $path) {
            WorkoutHomeView(
                savedDraft: savedDraft,
                onNewWorkout: {
                    if savedDraft != nil {
                        showReplaceConfirm = true
                    } else {
                        beginWorkout(from: nil)
                    }
                },
                onResume: { beginWorkout(from: savedDraft) },
                onDiscard: {
                    WorkoutDraftStore.clear(ownerID: profile.id)
                    savedDraft = nil
                }
            )
            .onAppear { savedDraft = WorkoutDraftStore.load(ownerID: profile.id) }
            .confirmationDialog("Start a new workout?", isPresented: $showReplaceConfirm, titleVisibility: .visible) {
                Button("Discard unfinished and start new", role: .destructive) {
                    WorkoutDraftStore.clear(ownerID: profile.id)
                    savedDraft = nil
                    beginWorkout(from: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have an unfinished workout. Starting a new one throws it away \u{2014} tap Resume instead to keep it.")
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .active:
                    ActiveWorkoutView(
                        ownerID: profile.id,
                        bodyweightLbs: profile.weightLbs,
                        startTime: draftStartTime,
                        initialExercises: [],
                        restoredDraft: resumeDraft
                    ) { session, cardio in
                        finishedSession = session
                        finishedCardio = cardio
                        savedDraft = nil
                        resumeDraft = nil
                        // Replace the logging screen with the summary rather
                        // than stacking on top of it. Otherwise "back" from the
                        // summary lands on the still-filled logging screen and
                        // a second Finish saves the same workout twice.
                        var summaryOnly = NavigationPath()
                        summaryOnly.append(Route.summary)
                        path = summaryOnly
                    } onCancel: {
                        WorkoutDraftStore.clear(ownerID: profile.id)
                        savedDraft = nil
                        resumeDraft = nil
                        finishedSession = nil
                        finishedCardio = []
                        path = NavigationPath()
                    }
                case .summary:
                    if let session = finishedSession {
                        WorkoutSummaryView(session: session, profile: profile, cardio: finishedCardio) {
                            finishedSession = nil
                            finishedCardio = []
                            path = NavigationPath()
                        }
                    } else {
                        ContentUnavailableView("No workout found", systemImage: "dumbbell")
                    }
                }
            }
            .navigationTitle("Workout")
        }
    }

    /// Opens the logging screen, fresh or from a saved draft.
    private func beginWorkout(from draft: WorkoutDraftSnapshot?) {
        draftStartTime = draft?.startTime ?? Date()
        resumeDraft = draft
        finishedSession = nil
        finishedCardio = []
        path.append(Route.active)
    }
}

// MARK: - Home

struct WorkoutHomeView: View {
    var savedDraft: WorkoutDraftSnapshot?
    var onNewWorkout: () -> Void
    var onResume: () -> Void
    var onDiscard: () -> Void

    @State private var showDiscardConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 64))
                .foregroundStyle(ForgeTheme.volt)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text("Ready to train?")
                .font(.title)
                .bold()
            Text("Start logging and add exercises as you go \u{2014} no planning needed. Log sets by weight and reps, or cardio by time, and Forge estimates your volume, one-rep maxes, and calories, then shows you what you trained.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if let savedDraft {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Unfinished workout", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundStyle(ForgeTheme.volt)
                    Text("Started \(savedDraft.startTime.formatted(.dateTime.weekday(.wide).hour().minute())) \u{00B7} \(savedDraft.summary)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Resume", action: onResume)
                            .buttonStyle(VoltButtonStyle())
                        Spacer()
                        Button("Discard", role: .destructive) { showDiscardConfirm = true }
                            .foregroundStyle(ForgeTheme.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeCard()
                .padding(.horizontal)
                .confirmationDialog("Discard the unfinished workout?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                    Button("Discard workout", role: .destructive, action: onDiscard)
                    Button("Keep it", role: .cancel) {}
                } message: {
                    Text("Its sets were never saved to History and will be gone.")
                }

                Button("Start a new workout instead", action: onNewWorkout)
                    .font(.subheadline)
            } else {
                Button("New Workout", action: onNewWorkout)
                    .buttonStyle(VoltButtonStyle())
                    .controlSize(.large)
            }
            Spacer()
        }
        .navigationTitle("Workout")
    }
}

// MARK: - Exercise picker (searchable strength list for the add-exercise sheet)

/// Searchable strength-exercise list grouped by primary muscle. Cardio is
/// left out on purpose: it's logged by time in its own sheet, not by sets.
struct ExercisePickerList: View {
    var selectedIDs: Set<String>
    var onToggle: (ExerciseDefinition) -> Void
    @State private var query = ""

    private var strengthExercises: [ExerciseDefinition] {
        ExerciseLibrary.all.filter { !$0.isCardio }
    }

    private var matches: [ExerciseDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return strengthExercises }
        // Tolerate plurals: "squats" should also find "Squat".
        let singular = trimmed.hasSuffix("s") && trimmed.count > 1 ? String(trimmed.dropLast()) : trimmed
        return strengthExercises.filter { definition in
            definition.name.localizedCaseInsensitiveContains(trimmed)
                || definition.name.localizedCaseInsensitiveContains(singular)
                // Searching a muscle ("chest", "quads") lists its exercises.
                || definition.primary.contains { $0.displayName.localizedCaseInsensitiveContains(singular) }
        }
    }

    var body: some View {
        List {
            ForEach(MuscleGroup.allCases, id: \.self) { group in
                let items = matches.filter { $0.primary.first == group }
                if !items.isEmpty {
                    Section(group.displayName) {
                        ForEach(items) { definition in
                            Button {
                                onToggle(definition)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(definition.name)
                                            .foregroundStyle(.primary)
                                        Text(caption(for: definition))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedIDs.contains(definition.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ForgeTheme.success)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Search exercises or muscles")
    }

    private func caption(for definition: ExerciseDefinition) -> String {
        var parts: [String] = []
        if definition.primary.count > 1 {
            parts.append(definition.primary.map(\.displayName).joined(separator: " + "))
        }
        if definition.secondary.isEmpty {
            parts.append("Isolation")
        } else {
            parts.append("Also: " + definition.secondary.map(\.displayName).joined(separator: ", "))
        }
        if definition.usesBodyweight { parts.append("Bodyweight") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Active logging

struct ExerciseDraft: Identifiable {
    let id = UUID()
    var definition: ExerciseDefinition
    var sets: [SetDraft]

    /// True once any rep count has been typed — worth confirming before removal.
    var hasLoggedWork: Bool { sets.contains { !ForgeInput.isBlank($0.reps) } }
}

struct SetDraft: Identifiable {
    let id = UUID()
    var reps = ""
    var weight = ""
}

/// A cardio bout being logged: the exercise plus typed minutes/miles.
struct CardioDraft: Identifiable {
    let id = UUID()
    var definition: ExerciseDefinition
    var minutes = ""
    var miles = ""

    var hasLoggedWork: Bool { !ForgeInput.isBlank(minutes) || !ForgeInput.isBlank(miles) }
}

/// Identifies a single text field on the logging screen so ONE shared
/// keyboard Done button (owned by ActiveWorkoutView) can dismiss whichever
/// field is focused — sets AND cardio. Do not add per-row keyboard toolbars.
enum LoggingField: Hashable {
    case setReps(UUID)
    case setWeight(UUID)
    case cardioMinutes(UUID)
    case cardioMiles(UUID)
}

/// What the logging screen's drafts turn into once validated.
private struct WorkoutCheck {
    /// `order` is the exercise's position on the logging screen.
    var lifts: [(definition: ExerciseDefinition, order: Int, reps: Int, weight: Double)] = []
    var cardio: [(definition: ExerciseDefinition, minutes: Double, miles: Double?)] = []
    /// Typos that block saving (e.g. "185.5.5" lb). Saving them would
    /// silently log the wrong number, so the user fixes them first.
    var problems: [String] = []
    /// Half-filled rows (a weight but no reps, miles but no minutes) that
    /// get left out — the confirmation dialog says how many.
    var skippedSets = 0
    var skippedCardio = 0

    var isEmpty: Bool { lifts.isEmpty && cardio.isEmpty }
}

/// A removal waiting on confirmation because the row already has data.
private enum PendingRemoval: Equatable {
    case exercise(UUID)
    case cardio(UUID)
}

struct ActiveWorkoutView: View {
    var ownerID: UUID
    /// The lifter's current bodyweight, for one-tap fill on bodyweight moves.
    var bodyweightLbs: Double
    var startTime: Date
    var onFinish: (WorkoutSession, [CardioEntry]) -> Void
    /// Discards the in-progress workout without saving.
    var onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @State private var exerciseDrafts: [ExerciseDraft]
    @State private var cardioDrafts: [CardioDraft]
    @State private var showAddSheet = false
    @State private var showCardioSheet = false
    @State private var showFinishConfirm = false
    @State private var finishMessage = ""
    @State private var showDiscardConfirm = false
    @State private var showEmptyAlert = false
    @State private var showProblemsAlert = false
    @State private var problemsMessage = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?
    @State private var pendingRemoval: PendingRemoval?
    @State private var isSaving = false
    @FocusState private var focusedField: LoggingField?

    /// - Parameter restoredDraft: an unfinished workout loaded from disk;
    ///   when present it replaces `initialExercises`.
    init(ownerID: UUID, bodyweightLbs: Double, startTime: Date, initialExercises: [ExerciseDefinition], restoredDraft: WorkoutDraftSnapshot? = nil, onFinish: @escaping (WorkoutSession, [CardioEntry]) -> Void, onCancel: @escaping () -> Void) {
        self.ownerID = ownerID
        self.bodyweightLbs = bodyweightLbs
        self.startTime = startTime
        self.onFinish = onFinish
        self.onCancel = onCancel
        if let restoredDraft, restoredDraft.ownerID == ownerID {
            _exerciseDrafts = State(initialValue: restoredDraft.exerciseDrafts())
            _cardioDrafts = State(initialValue: restoredDraft.cardioDrafts())
        } else {
            _exerciseDrafts = State(initialValue: initialExercises.map {
                ExerciseDraft(definition: $0, sets: [SetDraft(weight: $0.usesBodyweight ? ForgeInput.display(bodyweightLbs) : "")])
            })
            _cardioDrafts = State(initialValue: [])
        }
    }

    private var isEmptyWorkout: Bool { exerciseDrafts.isEmpty && cardioDrafts.isEmpty }

    /// Everything on screen, in a form that can be written to disk.
    private var snapshot: WorkoutDraftSnapshot {
        WorkoutDraftSnapshot(ownerID: ownerID, startTime: startTime, exerciseDrafts: exerciseDrafts, cardioDrafts: cardioDrafts)
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isEmptyWorkout {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(ForgeTheme.volt)
                        Text("What are you training?")
                            .font(.headline)
                        Text("Add your first exercise below \u{2014} add more as you go.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                }

                ForEach($exerciseDrafts) { $draft in
                    ExerciseLoggingCard(draft: $draft, bodyweightLbs: bodyweightLbs, focusedField: $focusedField) {
                        requestRemoval(exercise: draft)
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    focusedField = nil
                    showAddSheet = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Cardio")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach($cardioDrafts) { $draft in
                        CardioLoggingCard(draft: $draft, focusedField: $focusedField) {
                            requestRemoval(cardio: draft)
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button {
                        focusedField = nil
                        showCardioSheet = true
                    } label: {
                        Label("Log cardio", systemImage: "heart.circle")
                    }
                    .padding(.horizontal)
                }

                Button("Finish Workout", action: attemptFinish)
                    .buttonStyle(VoltButtonStyle())
                    .controlSize(.large)
                    .disabled(isSaving)
                    .padding(.vertical)
            }
            .padding(.vertical)
            .animation(.snappy, value: exerciseDrafts.map(\.id))
            .animation(.snappy, value: cardioDrafts.map(\.id))
        }
        .scrollDismissesKeyboard(.interactively)
        // Autosave: every edit is written to a small file, so if iOS closes
        // Forge mid-workout (common when switching to music or the camera),
        // the Workout tab offers to resume exactly where you left off.
        .onChange(of: snapshot) {
            if !isSaving { WorkoutDraftStore.save(snapshot) }
        }
        .navigationBarTitleDisplayMode(.inline)
        // No system back button: a back swipe used to throw away the whole
        // workout with no warning. Cancel (with confirmation) is the way out.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Logging workout")
                        .font(.headline)
                    Text(startTime, style: .timer)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    focusedField = nil
                    if isEmptyWorkout {
                        onCancel()
                    } else {
                        showDiscardConfirm = true
                    }
                }
            }
            // The ONE shared keyboard Done button for every field on this screen.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive, action: onCancel)
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("Your sets will not be saved.")
        }
        .confirmationDialog("Remove from this workout?", isPresented: removalBinding, titleVisibility: .visible, presenting: pendingRemoval) { item in
            // `item` is captured when the dialog opens, so the removal works
            // no matter which order SwiftUI clears pendingRemoval in.
            Button("Remove", role: .destructive) { remove(item) }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text("What you've typed for it will be discarded.")
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                ExercisePickerList(
                    selectedIDs: Set(exerciseDrafts.map { $0.definition.id }),
                    onToggle: toggleExercise
                )
                .navigationTitle("Add exercise")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showAddSheet = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showCardioSheet) {
            NavigationStack {
                List {
                    ForEach(ExerciseLibrary.all.filter(\.isCardio)) { definition in
                        Button {
                            cardioDrafts.append(CardioDraft(definition: definition))
                            showCardioSheet = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(definition.name)
                                    .foregroundStyle(.primary)
                                Text("Logged by time \u{00B7} miles optional")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Log cardio")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCardioSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Finish this workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Save workout", action: finishWorkout)
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text(finishMessage)
        }
        .alert("Nothing logged", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add reps to at least one set, or minutes to one cardio bout, before finishing.")
        }
        .alert("Check these entries", isPresented: $showProblemsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problemsMessage)
        }
        .alert("Couldn't save workout", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Your sets are still on this screen \u{2014} nothing was lost. Try again.")
        }
    }

    // MARK: - Adding & removing

    /// Picker tap: adds the exercise, or removes it again if it was added by
    /// mistake and nothing has been typed into it yet.
    private func toggleExercise(_ definition: ExerciseDefinition) {
        if let existing = exerciseDrafts.first(where: { $0.definition.id == definition.id }) {
            if !existing.hasLoggedWork {
                exerciseDrafts.removeAll { $0.id == existing.id }
            }
            return
        }
        exerciseDrafts.append(ExerciseDraft(
            definition: definition,
            sets: [SetDraft(weight: definition.usesBodyweight ? ForgeInput.display(bodyweightLbs) : "")]
        ))
    }

    private func requestRemoval(exercise draft: ExerciseDraft) {
        focusedField = nil
        if draft.hasLoggedWork {
            pendingRemoval = .exercise(draft.id)
        } else {
            remove(.exercise(draft.id))
        }
    }

    private func requestRemoval(cardio draft: CardioDraft) {
        focusedField = nil
        if draft.hasLoggedWork {
            pendingRemoval = .cardio(draft.id)
        } else {
            remove(.cardio(draft.id))
        }
    }

    private func remove(_ item: PendingRemoval) {
        switch item {
        case .exercise(let id): exerciseDrafts.removeAll { $0.id == id }
        case .cardio(let id): cardioDrafts.removeAll { $0.id == id }
        }
    }

    // MARK: - Finishing

    /// Turns the drafts into numbers, flagging typos instead of guessing.
    private func checkWorkout() -> WorkoutCheck {
        var check = WorkoutCheck()

        for (exerciseIndex, draft) in exerciseDrafts.enumerated() {
            let name = draft.definition.name
            for (index, set) in draft.sets.enumerated() {
                let label = "\(name) set \(index + 1)"
                let repsBlank = ForgeInput.isBlank(set.reps)
                let weightBlank = ForgeInput.isBlank(set.weight)
                if repsBlank {
                    // Untouched row: ignore. Weight but no reps: skip and say so.
                    if !weightBlank { check.skippedSets += 1 }
                    continue
                }
                guard let reps = ForgeInput.whole(set.reps), reps > 0, reps <= 500 else {
                    check.problems.append("\(label): reps should be a whole number like 8.")
                    continue
                }
                // An empty weight box means bodyweight-only (0 added lb).
                var weight = 0.0
                if !weightBlank {
                    guard let typed = ForgeInput.decimal(set.weight), typed >= 0, typed <= 2000 else {
                        check.problems.append("\(label): \"\(set.weight)\" isn't a weight Forge can read.")
                        continue
                    }
                    weight = typed
                }
                check.lifts.append((draft.definition, exerciseIndex, reps, weight))
            }
        }

        for draft in cardioDrafts {
            let name = draft.definition.name
            if ForgeInput.isBlank(draft.minutes) {
                if !ForgeInput.isBlank(draft.miles) { check.skippedCardio += 1 }
                continue
            }
            guard let minutes = ForgeInput.decimal(draft.minutes), minutes > 0, minutes <= 600 else {
                check.problems.append("\(name): minutes should be a number like 20.")
                continue
            }
            var miles: Double?
            if !ForgeInput.isBlank(draft.miles) {
                guard let typed = ForgeInput.decimal(draft.miles), typed >= 0, typed <= 200 else {
                    check.problems.append("\(name): \"\(draft.miles)\" isn't a distance Forge can read.")
                    continue
                }
                miles = typed
            }
            check.cardio.append((draft.definition, minutes, miles))
        }
        return check
    }

    private func attemptFinish() {
        focusedField = nil
        let check = checkWorkout()
        if !check.problems.isEmpty {
            problemsMessage = check.problems.joined(separator: "\n")
            showProblemsAlert = true
            return
        }
        guard !check.isEmpty else {
            showEmptyAlert = true
            return
        }

        var parts: [String] = []
        let setWord = check.lifts.count == 1 ? "set" : "sets"
        if !check.lifts.isEmpty { parts.append("\(check.lifts.count) \(setWord)") }
        if !check.cardio.isEmpty { parts.append("\(check.cardio.count) cardio") }
        var message = "Saving \(parts.joined(separator: " and "))."
        if check.skippedSets > 0 {
            let word = check.skippedSets == 1 ? "set has" : "sets have"
            message += " \(check.skippedSets) \(word) no reps and will be left out."
        }
        if check.skippedCardio > 0 {
            let word = check.skippedCardio == 1 ? "bout has" : "bouts have"
            message += " \(check.skippedCardio) cardio \(word) no minutes and will be left out."
        }
        finishMessage = message
        showFinishConfirm = true
    }

    private func finishWorkout() {
        guard !isSaving else { return }
        let check = checkWorkout()
        guard check.problems.isEmpty, !check.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let now = Date()
        let session = WorkoutSession(ownerID: ownerID, date: startTime, startTime: startTime, endTime: now)
        var counters: [String: Int] = [:]
        for entry in check.lifts {
            let number = (counters[entry.definition.id] ?? 0) + 1
            counters[entry.definition.id] = number
            session.sets.append(LoggedSet(
                exerciseId: entry.definition.id,
                exerciseName: entry.definition.name,
                setNumber: number,
                reps: entry.reps,
                weightLbs: entry.weight,
                exerciseOrder: entry.order
            ))
        }
        context.insert(session)
        // Explicitly insert the sets too — never rely on relationship
        // cascade alone for persistence.
        for set in session.sets {
            context.insert(set)
        }

        var entries: [CardioEntry] = []
        for item in check.cardio {
            // Stamped with the session's start time — that's how History
            // pairs cardio with the workout it belongs to.
            let entry = CardioEntry(
                ownerID: ownerID,
                date: startTime,
                exerciseId: item.definition.id,
                exerciseName: item.definition.name,
                durationMin: item.minutes,
                distanceMi: item.miles,
                notes: ""
            )
            context.insert(entry)
            entries.append(entry)
        }
        do {
            try context.save()
        } catch {
            // Throw away the half-inserted session so a retry doesn't save
            // it twice. The drafts on screen are untouched.
            context.rollback()
            saveErrorMessage = "The save failed (\(error.localizedDescription)). Your sets are still on this screen \u{2014} nothing was lost. Try again."
            showSaveError = true
            return
        }
        // It's in History now, so the autosaved draft has done its job.
        WorkoutDraftStore.clear(ownerID: ownerID)
        onFinish(session, entries)
    }
}

/// One cardio bout's logging card: minutes + optional miles.
struct CardioLoggingCard: View {
    @Binding var draft: CardioDraft
    var focusedField: FocusState<LoggingField?>.Binding
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.definition.name)
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(ForgeTheme.danger)
                }
                .accessibilityLabel("Remove \(draft.definition.name)")
            }

            Text(draft.definition.instructions)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Minutes", text: $draft.minutes)
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: .cardioMinutes(draft.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("Miles (optional)", text: $draft.miles)
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: .cardioMiles(draft.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Spacer()
            }
        }
        .forgeCard()
    }
}

/// One exercise's logging card: set rows, add-set, live volume + est 1RM.
struct ExerciseLoggingCard: View {
    @Binding var draft: ExerciseDraft
    var bodyweightLbs: Double
    var focusedField: FocusState<LoggingField?>.Binding
    var onRemoveExercise: () -> Void

    @State private var showInstructions = false

    private var stats: (volume: Double, best1RM: Double?) {
        var volume = 0.0
        var best: Double?
        for set in draft.sets {
            guard let reps = ForgeInput.whole(set.reps), reps > 0 else { continue }
            // Blank weight = bodyweight-only (0 added lb), same as saving.
            let weight = ForgeInput.isBlank(set.weight) ? 0 : (ForgeInput.decimal(set.weight) ?? -1)
            guard weight >= 0 else { continue }
            volume += Double(reps) * weight
            if (1...12).contains(reps), weight > 0 {
                let estimate = TrainingMath.epleyOneRepMax(weightLbs: weight, reps: reps)
                best = max(best ?? 0, estimate)
            }
        }
        return (volume, best)
    }

    /// Weight to prefill on a new set: bodyweight for bodyweight moves,
    /// otherwise whatever the previous set used (most lifters repeat it).
    private var nextSetWeight: String {
        if draft.definition.usesBodyweight { return ForgeInput.display(bodyweightLbs) }
        return draft.sets.last?.weight ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.definition.name)
                    .font(.headline)
                Button {
                    withAnimation(.snappy) { showInstructions.toggle() }
                } label: {
                    Image(systemName: showInstructions ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(showInstructions ? "Hide instructions" : "Show instructions")
                Spacer()
                Button(role: .destructive, action: onRemoveExercise) {
                    Image(systemName: "trash")
                        .foregroundStyle(ForgeTheme.danger)
                }
                .accessibilityLabel("Remove \(draft.definition.name)")
            }

            if showInstructions {
                Text(draft.definition.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if draft.definition.usesBodyweight {
                Button {
                    let bw = ForgeInput.display(bodyweightLbs)
                    for i in draft.sets.indices where ForgeInput.isBlank(draft.sets[i].weight) {
                        draft.sets[i].weight = bw
                    }
                } label: {
                    Label("Fill bodyweight (\(ForgeInput.display(bodyweightLbs)) lb)", systemImage: "person.fill")
                        .font(.subheadline)
                }
            }

            ForEach(Array(draft.sets.enumerated()), id: \.element.id) { index, set in
                if let binding = binding(for: set.id) {
                    SetRowView(
                        draft: binding,
                        setNumber: index + 1,
                        canDelete: draft.sets.count > 1,
                        focusedField: focusedField,
                        onDelete: { draft.sets.removeAll { $0.id == set.id } }
                    )
                }
            }

            Button {
                draft.sets.append(SetDraft(weight: nextSetWeight))
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.subheadline)
            }

            HStack {
                Text("Volume: \(Int(stats.volume)) lb")
                if let best1RM = stats.best1RM {
                    Text("\u{00B7} Est 1RM: \(Int(best1RM)) lb")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
        .forgeCard()
    }

    /// A binding to one set by id, so deleting a row mid-list can never
    /// index past the end of the array.
    private func binding(for id: UUID) -> Binding<SetDraft>? {
        guard draft.sets.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { draft.sets.first(where: { $0.id == id }) ?? SetDraft() },
            set: { newValue in
                if let i = draft.sets.firstIndex(where: { $0.id == id }) {
                    draft.sets[i] = newValue
                }
            }
        )
    }
}

/// One set's reps/weight input row.
struct SetRowView: View {
    @Binding var draft: SetDraft
    var setNumber: Int
    var canDelete: Bool
    var focusedField: FocusState<LoggingField?>.Binding
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Set \(setNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            TextField("Reps", text: $draft.reps)
                .keyboardType(.numberPad)
                .focused(focusedField, equals: .setReps(draft.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Weight", text: $draft.weight)
                .keyboardType(.decimalPad)
                .focused(focusedField, equals: .setWeight(draft.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            Text("lb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(ForgeTheme.danger)
                }
                .accessibilityLabel("Delete set \(setNumber)")
            }
        }
    }
}

// MARK: - Workout autosave

/// A Codable copy of the logging screen: which exercises, and exactly what
/// was typed in each box (kept as text, so a half-typed "18" comes back as
/// "18"). Not a SwiftData model — it's a throwaway file, so it can never
/// affect the database schema.
struct WorkoutDraftSnapshot: Codable, Equatable {
    struct Exercise: Codable, Equatable {
        var exerciseId: String
        var sets: [SetEntry]
    }

    struct SetEntry: Codable, Equatable {
        var reps: String
        var weight: String
    }

    struct Cardio: Codable, Equatable {
        var exerciseId: String
        var minutes: String
        var miles: String
    }

    var ownerID: UUID
    var startTime: Date
    var exercises: [Exercise]
    var cardio: [Cardio]

    var isEmpty: Bool { exercises.isEmpty && cardio.isEmpty }

    /// "3 exercises, 1 cardio" for the resume card.
    var summary: String {
        var parts: [String] = []
        if !exercises.isEmpty {
            parts.append("\(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises")")
        }
        if !cardio.isEmpty {
            parts.append("\(cardio.count) cardio")
        }
        return parts.joined(separator: ", ")
    }

    init(ownerID: UUID, startTime: Date, exerciseDrafts: [ExerciseDraft], cardioDrafts: [CardioDraft]) {
        self.ownerID = ownerID
        self.startTime = startTime
        self.exercises = exerciseDrafts.map { draft in
            Exercise(
                exerciseId: draft.definition.id,
                sets: draft.sets.map { SetEntry(reps: $0.reps, weight: $0.weight) }
            )
        }
        self.cardio = cardioDrafts.map {
            Cardio(exerciseId: $0.definition.id, minutes: $0.minutes, miles: $0.miles)
        }
    }

    /// Back to editable drafts. Exercises no longer in the library are skipped.
    func exerciseDrafts() -> [ExerciseDraft] {
        exercises.compactMap { saved in
            guard let definition = ExerciseLibrary.definition(for: saved.exerciseId) else { return nil }
            let sets = saved.sets.map { SetDraft(reps: $0.reps, weight: $0.weight) }
            return ExerciseDraft(definition: definition, sets: sets.isEmpty ? [SetDraft()] : sets)
        }
    }

    func cardioDrafts() -> [CardioDraft] {
        cardio.compactMap { saved in
            guard let definition = ExerciseLibrary.definition(for: saved.exerciseId) else { return nil }
            return CardioDraft(definition: definition, minutes: saved.minutes, miles: saved.miles)
        }
    }
}

/// Reads and writes the unfinished-workout file. One file per profile, so
/// profiles never see each other's drafts. Lives in Application Support
/// (UserDefaults only ever holds the active profile ID).
enum WorkoutDraftStore {
    private static func fileURL(for ownerID: UUID) -> URL? {
        guard let folder = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return folder.appendingPathComponent("unfinished-workout-\(ownerID.uuidString).json")
    }

    /// The saved draft for this profile, or nil when there isn't a usable one.
    static func load(ownerID: UUID) -> WorkoutDraftSnapshot? {
        guard let url = fileURL(for: ownerID),
              let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(WorkoutDraftSnapshot.self, from: data),
              draft.ownerID == ownerID,
              !draft.isEmpty
        else { return nil }
        return draft
    }

    /// Writes the draft, or removes the file when there's nothing to keep.
    static func save(_ draft: WorkoutDraftSnapshot) {
        guard !draft.isEmpty else {
            clear(ownerID: draft.ownerID)
            return
        }
        guard let url = fileURL(for: draft.ownerID),
              let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear(ownerID: UUID) {
        guard let url = fileURL(for: ownerID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
