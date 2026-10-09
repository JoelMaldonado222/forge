import SwiftUI
import SwiftData

/// Unit for the water input box. Stored values are always oz.
enum WaterUnit: String, CaseIterable {
    case oz
    case ml
}

/// The "Today" tab: greeting, water tracker, fuel tracker, 3D body showing
/// the last 7 days' trained muscles, 7-day volume, and a Start Workout shortcut.
struct DashboardView: View {
    var profile: UserProfile
    @Binding var selectedTab: Int
    @Environment(\.modelContext) private var context

    private static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private static var sevenDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    @Query(sort: \WaterLog.date)
    private var allWater: [WaterLog]

    @Query(sort: \FoodEntry.date)
    private var allFood: [FoodEntry]

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var allSessions: [WorkoutSession]

    @Query(sort: \CardioEntry.date, order: .reverse)
    private var allCardio: [CardioEntry]

    /// Everything below is scoped to the active profile via ownerID, so each
    /// person's water, food, and workouts stay separate.
    private var todaysWater: [WaterLog] {
        allWater.filter { $0.ownerID == profile.id && $0.date >= Self.startOfToday }
    }

    private var todaysFood: [FoodEntry] {
        allFood.filter { $0.ownerID == profile.id && $0.date >= Self.startOfToday }
    }

    private var weekSessions: [WorkoutSession] {
        allSessions.filter { $0.ownerID == profile.id && $0.date >= Self.sevenDaysAgo }
    }

    private var weekCardio: [CardioEntry] {
        allCardio.filter { $0.ownerID == profile.id && $0.date >= Self.sevenDaysAgo }
    }

    /// The text fields on this screen, so logging an entry (or dragging the
    /// page) puts the keyboard away — the number pads have no return key.
    private enum Field: Hashable {
        case water, foodLabel, foodProtein, foodCalories
    }

    @FocusState private var focusedField: Field?
    @State private var foodLabel = ""
    @State private var foodProtein = ""
    @State private var foodCalories = ""
    @State private var foodError: String?
    @State private var waterAmount = ""
    @State private var waterUnit: WaterUnit = .oz
    @State private var waterError: String?

    private var waterTotal: Double { todaysWater.reduce(0) { $0 + $1.ounces } }
    private var waterTarget: Double { TrainingMath.waterTargetOz(weightLbs: profile.weightLbs) }
    private var proteinTotal: Double { todaysFood.reduce(0) { $0 + $1.proteinG } }
    private var caloriesTotal: Double { todaysFood.reduce(0) { $0 + $1.calories } }
    private var proteinTarget: Double {
        TrainingMath.proteinTargetG(weightLbs: profile.weightLbs)
    }
    private var weekVolume: Double { TrainingMath.totalVolume(sessions: weekSessions) }
    private var weekCardioMinutes: Double { weekCardio.reduce(0) { $0 + $1.durationMin } }

    private var weekIntensities: [MuscleGroup: Double] {
        TrainingMath.highlightIntensities(sets: weekSessions.flatMap(\.sets), cardio: weekCardio)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(greeting), \(profile.name)")
                            .font(.largeTitle)
                            .bold()
                        Text(Date(), style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    card { waterCard }
                    card { fuelCard }

                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Muscles trained \u{00B7} last 7 days").font(.headline)
                            Text("Drag to rotate \u{00B7} pinch to zoom")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Body3DView(intensities: weekIntensities)
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    card {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("7-day volume").font(.headline)
                                Text("\(Int(weekVolume)) lb")
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(ForgeTheme.voltGradient)
                                    .contentTransition(.numericText())
                                Text("total weight lifted" + (weekCardioMinutes > 0 ? " \u{00B7} \(Int(weekCardioMinutes)) min cardio" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Start Workout") { selectedTab = 1 }
                                .buttonStyle(VoltButtonStyle())
                        }
                    }
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Today")
        }
    }

    // MARK: - Cards

    private var waterCard: some View {
        HStack(spacing: 16) {
            WaterRingView(progress: waterTarget > 0 ? waterTotal / waterTarget : 0)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Water").font(.headline)
                    Spacer()
                    if let last = todaysWater.last {
                        Button("Undo \(Int(last.ounces.rounded())) oz") { undoWater(last) }
                            .font(.caption)
                    }
                }
                Text("\(Int(waterTotal)) / \(Int(waterTarget)) oz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                HStack(spacing: 8) {
                    TextField("Amount", text: $waterAmount)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .water)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Picker("Unit", selection: $waterUnit) {
                        Text("oz").tag(WaterUnit.oz)
                        Text("mL").tag(WaterUnit.ml)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    Button("Add", action: logWaterInput)
                        .buttonStyle(VoltButtonStyle())
                }
                if let waterError {
                    Text(waterError)
                        .font(.caption)
                        .foregroundStyle(ForgeTheme.danger)
                }
            }
        }
    }

    private var fuelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fuel").font(.headline)
            Text("\(Int(proteinTotal)) / \(Int(proteinTarget)) g protein \u{00B7} \(Int(caloriesTotal)) kcal today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            TextField("What did you eat?", text: $foodLabel)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .foodLabel)
                .submitLabel(.next)
                .onSubmit { focusedField = .foodProtein }
            HStack {
                TextField("Protein (g)", text: $foodProtein)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .foodProtein)
                    .textFieldStyle(.roundedBorder)
                TextField("Calories", text: $foodCalories)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .foodCalories)
                    .textFieldStyle(.roundedBorder)
                Button("Add", action: logFood)
                    .buttonStyle(VoltButtonStyle())
            }
            if let foodError {
                Text(foodError)
                    .font(.caption)
                    .foregroundStyle(ForgeTheme.danger)
            }
            if !todaysFood.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(todaysFood, id: \.id) { entry in
                    HStack {
                        Text(entry.label)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(entry.proteinG)) g \u{00B7} \(Int(entry.calories)) kcal")
                            .foregroundStyle(.secondary)
                        Button {
                            deleteFood(entry)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(entry.label)")
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .forgeCard()
            .padding(.horizontal)
    }

    /// Logs the typed water amount, converting mL to oz behind the scenes
    /// (1 oz = 29.5735 mL). Everything is stored in oz.
    private func logWaterInput() {
        guard let amount = ForgeInput.decimal(waterAmount), amount > 0 else {
            waterError = "Enter an amount greater than 0."
            return
        }
        let ounces = waterUnit == .ml ? amount / 29.5735 : amount
        guard ounces <= 256 else {
            waterError = "That's over 2 gallons in one go \u{2014} double-check the amount."
            return
        }
        context.insert(WaterLog(ownerID: profile.id, date: Date(), ounces: ounces))
        try? context.save()
        waterAmount = ""
        waterError = nil
        focusedField = nil
    }

    private func undoWater(_ entry: WaterLog) {
        context.delete(entry)
        try? context.save()
    }

    private func logFood() {
        let label = foodLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            foodError = "Give the food a name first."
            return
        }
        // Blank = 0 is fine; a typo like "30.5.5" is not.
        let protein = ForgeInput.isBlank(foodProtein) ? 0 : ForgeInput.decimal(foodProtein)
        let calories = ForgeInput.isBlank(foodCalories) ? 0 : ForgeInput.decimal(foodCalories)
        guard let protein, let calories, protein >= 0, calories >= 0 else {
            foodError = "Protein and calories need to be numbers."
            return
        }
        context.insert(FoodEntry(ownerID: profile.id, date: Date(), label: label, proteinG: protein, calories: calories))
        try? context.save()
        foodLabel = ""
        foodProtein = ""
        foodCalories = ""
        foodError = nil
        focusedField = nil
    }

    private func deleteFood(_ entry: FoodEntry) {
        context.delete(entry)
        try? context.save()
    }
}

/// Circular progress ring for the water tracker.
struct WaterRingView: View {
    /// 0...1
    var progress: Double

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(ForgeTheme.voltWash, lineWidth: 12)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(ForgeTheme.volt, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: clamped)
            Text("\(Int(clamped * 100))%")
                .font(.caption)
                .bold()
                .contentTransition(.numericText())
        }
    }
}
