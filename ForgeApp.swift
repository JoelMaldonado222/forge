import SwiftUI
import SwiftData

@main
struct ForgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            LoggedSet.self,
            WaterLog.self,
            FoodEntry.self,
            CardioEntry.self,
        ])
    }
}

/// Shows onboarding when no profiles exist, otherwise the main tab bar for the
/// active profile. The active profile id is kept in UserDefaults so the app
/// reopens on whoever used it last.
struct RootView: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @AppStorage("activeProfileID") private var activeProfileID: String = ""
    @State private var selectedTab = 0

    private var activeProfile: UserProfile? {
        profiles.first { $0.id.uuidString == activeProfileID } ?? profiles.first
    }

    var body: some View {
        if let profile = activeProfile {
            TabView(selection: $selectedTab) {
                DashboardView(profile: profile, selectedTab: $selectedTab)
                    .tabItem { Label("Today", systemImage: "sun.max") }
                    .tag(0)
                    .id(profile.id)
                WorkoutFlowView(profile: profile)
                    .tabItem { Label("Workout", systemImage: "dumbbell") }
                    .tag(1)
                    .id(profile.id)
                HistoryView(profile: profile)
                    .tabItem { Label("History", systemImage: "chart.bar") }
                    .tag(2)
                    .id(profile.id)
                ProfileView(profile: profile)
                    .tabItem { Label("Profile", systemImage: "person") }
                    .tag(3)
                    .id(profile.id)
            }
            .tint(ForgeTheme.volt)
        } else {
            OnboardingView()
        }
    }
}

/// First-launch setup: creates the first UserProfile and makes it active.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("activeProfileID") private var activeProfileID: String = ""

    @State private var name = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var goal = FitnessGoals.all[0]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Height (inches)", text: $heightText)
                        .keyboardType(.decimalPad)
                    TextField("Weight (lbs)", text: $weightText)
                        .keyboardType(.decimalPad)
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                }

                Section("Primary goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(FitnessGoals.all, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(ForgeTheme.danger)
                    }
                }

                Section {
                    Button("Start Training", action: save)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Welcome to Forge")
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter your name."
            return
        }
        guard let height = ForgeInput.decimal(heightText), height > 0, height < 120 else {
            errorMessage = "Enter a valid height in inches."
            return
        }
        guard let weight = ForgeInput.decimal(weightText), weight > 0, weight < 1000 else {
            errorMessage = "Enter a valid weight in pounds."
            return
        }
        guard let age = ForgeInput.whole(ageText), age > 0, age < 120 else {
            errorMessage = "Enter a valid age."
            return
        }

        let profile = UserProfile(
            name: trimmedName,
            heightInches: height,
            weightLbs: weight,
            age: age,
            goal: goal
        )
        context.insert(profile)
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "Couldn't save your profile: \(error.localizedDescription)"
            return
        }
        activeProfileID = profile.id.uuidString
        errorMessage = nil
    }
}
