import SwiftUI
import SwiftData

/// Unit for the water input box. Stored values are always oz.
enum WaterUnit: String, CaseIterable {
    case oz
    case ml
}

/// The "Today" tab: greeting, water tracker, fuel tracker, 3D body showing
/// this week's trained muscles, 7-day volume, and a Start Workout shortcut.
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

    @State private var foodLabel = ""
    @State private var foodProtein = ""
    @State private var foodCalories = ""
    @State private var waterAmount = ""
    @State private var waterUnit: WaterUnit = .oz
    @State private var waterError: String?

    private var waterTotal: Double { todaysWater.reduce(0) { $0 + $1.ounces } }
    private var waterTarget: Double { TrainingMath.waterTargetOz(weightLbs: profile.weightLbs) }
    private var proteinTotal: Double { todaysFood.reduce(0) { $0 + $1.proteinG } }
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

                    card {
                        HStack(spacing: 16) {
                            WaterRingView(progress: waterTarget > 0 ? waterTotal / waterTarget : 0)
                                .frame(width: 92, height: 92)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Water").font(.headline)
                                Text("\(Int(waterTotal)) / \(Int(waterTarget)) oz")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("Amount", text: $waterAmount)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Picker("Unit", selection: $waterUnit) {
                                        Text("oz").tag(WaterUnit.oz)
                                        Text("mL").tag(WaterUnit.ml)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 110)
                                    Button("Add", action: logWaterInput)
                                        .buttonStyle(VoltButtonStyle())
                                }
                                if let waterError {
                                    Text(waterError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Fuel").font(.headline)
                            Text("\(Int(proteinTotal)) / \(Int(proteinTarget)) g protein today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("What did you eat?", text: $foodLabel)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                TextField("Protein (g)", text: $foodProtein)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Calories", text: $foodCalories)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                Button("Add", action: logFood)
                                    .buttonStyle(VoltButtonStyle())
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Muscles trained this week").font(.headline)
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
            .navigationTitle("Today")
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
    }

    private func logWater(_ ounces: Double) {
        context.insert(WaterLog(ownerID: profile.id, date: Date(), ounces: ounces))
        try? context.save()
    }

    /// Logs the typed water amount, converting mL to oz behind the scenes
    /// (1 oz = 29.5735 mL). Everything is stored in oz.
    private func logWaterInput() {
        let text = waterAmount.trimmingCharacters(in: .whitespaces)
        guard let amount = Double(text), amount > 0 else {
            waterError = "Enter an amount greater than 0."
            return
        }
        guard amount < 10000 else {
            waterError = "That seems like a lot — double-check the amount."
            return
        }
        let ounces = waterUnit == .ml ? amount / 29.5735 : amount
        logWater(ounces)
        waterAmount = ""
        waterError = nil
    }

    private func logFood() {
        let label = foodLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let protein = Double(foodProtein.trimmingCharacters(in: .whitespaces)) ?? 0
        let calories = Double(foodCalories.trimmingCharacters(in: .whitespaces)) ?? 0
        context.insert(FoodEntry(ownerID: profile.id, date: Date(), label: label, proteinG: protein, calories: calories))
        try? context.save()
        foodLabel = ""
        foodProtein = ""
        foodCalories = ""
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
            Text("\(Int(clamped * 100))%")
                .font(.caption)
                .bold()
        }
    }
}
