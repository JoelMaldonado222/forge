import SwiftUI
import SwiftData

/// The "Workout" tab: home -> active logging (add exercises as you go) -> summary.
struct WorkoutFlowView: View {
    var profile: UserProfile
    @State private var path = NavigationPath()
    @State private var draftStartTime = Date()
    @State private var finishedSession: WorkoutSession?
    @State private var finishedCardio: [CardioEntry] = []

    enum Route: Hashable {
        case active
        case summary
    }

    var body: some View {
        NavigationStack(path: $path) {
            WorkoutHomeView {
                draftStartTime = Date()
                finishedSession = nil
                finishedCardio = []
                path.append(Route.active)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .active:
                    ActiveWorkoutView(
                        ownerID: profile.id,
                        bodyweightLbs: profile.weightLbs,
                        startTime: draftStartTime,
                        initialExercises: []
                    ) { session, cardio in
                        finishedSession = session
                        finishedCardio = cardio
                        path.append(Route.summary)
                    } onCancel: {
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
}

// MARK: - Home

struct WorkoutHomeView: View {
    var onNewWorkout: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 64))
                .foregroundStyle(ForgeTheme.volt)
            Text("Ready to train?")
                .font(.title)
                .bold()
            Text("Start logging and add exercises as you go \u{2014} no need to plan the workout first. Log sets with weight and reps — or log cardio by time — and Forge will estimate volume, one-rep maxes, and calories \u{2014} then show you exactly what you trained.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("New Workout", action: onNewWorkout)
                .buttonStyle(VoltButtonStyle())
                .controlSize(.large)
            Spacer()
        }
        .navigationTitle("Workout")
    }
}

// MARK: - Exercise picker (searchable list, reused by the add-exercise sheet)

/// Searchable exercise list grouped by primary muscle. Reused by the picker
/// screen and the "add exercise" sheet inside active logging.
struct ExercisePickerList: View {
    var selectedIDs: Set<String>
    var onToggle: (ExerciseDefinition) -> Void
    @State private var query = ""

    private var matches: [ExerciseDefinition] {
        guard !query.isEmpty else { return ExerciseLibrary.all }
        // Tolerate plurals: "squats" should also find "Squat".
        let singular = query.hasSuffix("s") && query.count > 1 ? String(query.dropLast()) : query
        return ExerciseLibrary.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(singular)
        }
    }

    var body: some View {
        List {
            ForEach(MuscleGroup.allCases, id: \.self) { group in
                let items = matches.filter { $0.primary.contains(group) }
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
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search exercises")
    }

    private func caption(for definition: ExerciseDefinition) -> String {
        if definition.secondary.isEmpty {
            return "Isolation \u{00B7} MET \(String(format: "%.1f", definition.met))"
        }
        let names = definition.secondary.map(\.displayName).joined(separator: ", ")
        return "Also: \(names) \u{00B7} MET \(String(format: "%.1f", definition.met))"
    }
}

// MARK: - Active logging

struct ExerciseDraft: Identifiable {
    let id = UUID()
    var definition: ExerciseDefinition
    var sets: [SetDraft]
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
}

/// Identifies a single text field on the logging screen so one shared
/// keyboard Done button can dismiss whichever field is focused.
enum LoggingField: Hashable {
    case setReps(UUID)
    case setWeight(UUID)
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
    @State private var cardioDrafts: [CardioDraft] = []
    @State private var showAddSheet = false
    @State private var showCardioSheet = false
    @State private var showFinishConfirm = false
    @State private var showDiscardConfirm = false
    @State private var showEmptyAlert = false
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: LoggingField?

    init(ownerID: UUID, bodyweightLbs: Double, startTime: Date, initialExercises: [ExerciseDefinition], onFinish: @escaping (WorkoutSession, [CardioEntry]) -> Void, onCancel: @escaping () -> Void) {
        self.ownerID = ownerID
        self.bodyweightLbs = bodyweightLbs
        self.startTime = startTime
        self.onFinish = onFinish
        self.onCancel = onCancel
        _exerciseDrafts = State(initialValue: initialExercises.map {
            ExerciseDraft(definition: $0, sets: [SetDraft(weight: $0.usesBodyweight ? String(format: "%g", bodyweightLbs) : "")])
        })
    }

    /// Formatted bodyweight for prefilling set fields.
    private var bodyweightString: String { String(format: "%g", bodyweightLbs) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if exerciseDrafts.isEmpty && cardioDrafts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(ForgeTheme.volt)
                        Text("What are you training?")
                            .font(.headline)
                        Text("Add your first exercise below — add more as you go.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                }

                ForEach($exerciseDrafts) { $draft in
                    ExerciseLoggingCard(draft: $draft, bodyweightLbs: bodyweightLbs, focusedField: $focusedField) {
                        exerciseDrafts.removeAll { $0.id == draft.id }
                    }
                    .padding(.horizontal)
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Cardio")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach($cardioDrafts) { $draft in
                        CardioLoggingCard(draft: $draft) {
                            cardioDrafts.removeAll { $0.id == draft.id }
                        }
                        .padding(.horizontal)
                    }

                    Button {
                        showCardioSheet = true
                    } label: {
                        Label("Log cardio", systemImage: "heart.circle")
                    }
                    .padding(.horizontal)
                }

                Button("Finish Workout") {
                    showFinishConfirm = true
                }
                .buttonStyle(VoltButtonStyle())
                .controlSize(.large)
                .padding(.vertical)
            }
            .padding(.vertical)
        }
        .navigationTitle("Logging workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showDiscardConfirm = true }
            }
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
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                ExercisePickerList(
                    selectedIDs: Set(exerciseDrafts.map { $0.definition.id }),
                    onToggle: { definition in
                        guard !exerciseDrafts.contains(where: { $0.definition.id == definition.id }) else { return }
                        exerciseDrafts.append(ExerciseDraft(
                            definition: definition,
                            sets: [SetDraft(weight: definition.usesBodyweight ? bodyweightString : "")]
                        ))
                    }
                )
                .navigationTitle("Add exercise")
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
                                Text("Timed \u{00B7} MET \(String(format: "%.1f", definition.met))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Log cardio")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCardioSheet = false }
                    }
                }
            }
        }
        .confirmationDialog("Finish this workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Save workout", action: finishWorkout)
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("Your sets and cardio will be saved and summarized.")
        }
        .alert("Nothing logged", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add at least one set or one cardio bout before finishing.")
        }
        .alert("Couldn't save workout", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Your sets are still on this screen — nothing was lost. Try again.")
        }
    }

    private func finishWorkout() {
        var logged: [(definition: ExerciseDefinition, reps: Int, weight: Double)] = []
        for draft in exerciseDrafts {
            for set in draft.sets {
                let repsText = set.reps.trimmingCharacters(in: .whitespaces)
                let weightText = set.weight.trimmingCharacters(in: .whitespaces)
                // Reps are required; an empty weight box means bodyweight-only
                // (0 added lb) rather than a dropped set.
                guard let reps = Int(repsText), reps > 0 else { continue }
                let weight = max(0, Double(weightText) ?? 0)
                logged.append((draft.definition, reps, weight))
            }
        }
        var cardioLogged: [(definition: ExerciseDefinition, minutes: Double, miles: Double?)] = []
        for draft in cardioDrafts {
            guard let minutes = Double(draft.minutes.trimmingCharacters(in: .whitespaces)),
                  minutes > 0 else { continue }
            let milesText = draft.miles.trimmingCharacters(in: .whitespaces)
            let miles: Double? = milesText.isEmpty ? nil : Double(milesText)
            cardioLogged.append((draft.definition, minutes, miles))
        }
        guard !logged.isEmpty || !cardioLogged.isEmpty else {
            showEmptyAlert = true
            return
        }

        let now = Date()
        let session = WorkoutSession(ownerID: ownerID, date: startTime, startTime: startTime, endTime: now)
        var counters: [String: Int] = [:]
        for entry in logged {
            let number = (counters[entry.definition.id] ?? 0) + 1
            counters[entry.definition.id] = number
            session.sets.append(LoggedSet(
                exerciseId: entry.definition.id,
                exerciseName: entry.definition.name,
                setNumber: number,
                reps: entry.reps,
                weightLbs: entry.weight
            ))
        }
        context.insert(session)
        // Explicitly insert the sets too — never rely on relationship
        // cascade alone for persistence.
        for set in session.sets {
            context.insert(set)
        }

        var entries: [CardioEntry] = []
        for item in cardioLogged {
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
            saveErrorMessage = "The save failed (\(error.localizedDescription)). Your sets are still on this screen — nothing was lost. Try again."
            showSaveError = true
            return
        }
        onFinish(session, entries)
    }
}

/// One cardio bout's logging card: minutes + optional miles.
struct CardioLoggingCard: View {
    @Binding var draft: CardioDraft
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.definition.name)
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
            }

            Text(draft.definition.instructions)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Minutes", text: $draft.minutes)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("Miles (optional)", text: $draft.miles)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// One exercise's logging card: set rows, add-set, live volume + est 1RM.
struct ExerciseLoggingCard: View {
    @Binding var draft: ExerciseDraft
    var bodyweightLbs: Double
    var focusedField: FocusState<LoggingField?>.Binding
    var onRemoveExercise: () -> Void

    private var stats: (volume: Double, best1RM: Double?) {
        var volume = 0.0
        var best: Double?
        for set in draft.sets {
            guard let reps = Int(set.reps.trimmingCharacters(in: .whitespaces)), reps > 0,
                  let weight = Double(set.weight.trimmingCharacters(in: .whitespaces)), weight >= 0 else { continue }
            volume += Double(reps) * weight
            if (1...12).contains(reps) {
                let estimate = TrainingMath.epleyOneRepMax(weightLbs: weight, reps: reps)
                best = max(best ?? 0, estimate)
            }
        }
        return (volume, best)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.definition.name)
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onRemoveExercise) {
                    Image(systemName: "trash")
                }
            }

            Text(draft.definition.instructions)
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.definition.usesBodyweight {
                Button {
                    let bw = String(format: "%g", bodyweightLbs)
                    for i in draft.sets.indices {
                        if draft.sets[i].weight.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft.sets[i].weight = bw
                        }
                    }
                } label: {
                    Label("Fill bodyweight (\(Int(bodyweightLbs)) lb)", systemImage: "person.fill")
                        .font(.subheadline)
                }
            }

            ForEach($draft.sets) { $set in
                let number = (draft.sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1
                SetRowView(
                    draft: $set,
                    setNumber: number,
                    canDelete: draft.sets.count > 1,
                    focusedField: focusedField,
                    onDelete: { draft.sets.removeAll { $0.id == set.id } }
                )
            }

            Button {
                let prefill = draft.definition.usesBodyweight ? String(format: "%g", bodyweightLbs) : ""
                draft.sets.append(SetDraft(weight: prefill))
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
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
