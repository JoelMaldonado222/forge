import SwiftUI
import SwiftData

/// Profile tab: edit stats and goal, see computed daily targets.
struct ProfileView: View {
    var profile: UserProfile
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var heightText: String
    @State private var weightText: String
    @State private var ageText: String
    @State private var goal: String
    @State private var pinText: String
    @State private var savedMessage: String?

    init(profile: UserProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _heightText = State(initialValue: String(format: "%g", profile.heightInches))
        _weightText = State(initialValue: String(format: "%g", profile.weightLbs))
        _ageText = State(initialValue: "\(profile.age)")
        _goal = State(initialValue: profile.goal)
        _pinText = State(initialValue: profile.pin ?? "")
        _savedMessage = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Height (inches)", text: $heightText)
                        .keyboardType(.decimalPad)
                    TextField("Weight (lbs)", text: $weightText)
                        .keyboardType(.decimalPad)
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                    Picker("Goal", selection: $goal) {
                        ForEach(FitnessGoals.all, id: \.self) { Text($0) }
                    }
                }

                Section("Daily targets") {
                    let water = TrainingMath.waterTargetOz(weightLbs: profile.weightLbs)
                    let proteinRange = TrainingMath.proteinTargetRangeG(weightLbs: profile.weightLbs)
                    HStack {
                        Text("Water")
                        Spacer()
                        Text("\(Int(water)) oz/day")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(Int(proteinRange.low))\u{2013}\(Int(proteinRange.high)) g/day")
                            .foregroundStyle(.secondary)
                    }
                    Text("Evidence-based targets: 1.6\u{2013}2.2 g of protein per kg of bodyweight per day (Morton et al. 2018). Water target is a flat 1 gallon (128 oz) a day. Protein targets update automatically when you save new stats. They are coaching heuristics, not medical advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save changes", action: save)
                }

                Section("Profiles") {
                    NavigationLink {
                        ProfileSwitcherView()
                    } label: {
                        Label("Switch profile", systemImage: "person.2")
                    }
                    Text("Everyone gets their own profile — workouts, water, and food never mix between profiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Back up & restore", systemImage: "externaldrive")
                    }
                    Text("Save all your gym data to a file, or restore everything from a backup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Profile PIN") {
                    SecureField("4-digit PIN (optional)", text: $pinText)
                        .keyboardType(.numberPad)
                    Text("Asked for before switching to this profile. Stored as plain text — casual privacy, not encryption. Leave blank for no PIN.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let savedMessage {
                    Section {
                        Text(savedMessage)
                            .foregroundStyle(savedMessage == "Saved." ? .green : .red)
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let height = Double(heightText.trimmingCharacters(in: .whitespaces)), height > 0,
              let weight = Double(weightText.trimmingCharacters(in: .whitespaces)), weight > 0,
              let age = Int(ageText.trimmingCharacters(in: .whitespaces)), age > 0, age < 120
        else {
            savedMessage = "Check your entries \u{2014} name, height, weight, and age must all be valid."
            return
        }

        let pin = pinText.trimmingCharacters(in: .whitespaces)
        if !pin.isEmpty {
            let digits = CharacterSet.decimalDigits
            guard pin.count == 4, pin.unicodeScalars.allSatisfy({ digits.contains($0) }) else {
                savedMessage = "The PIN must be exactly 4 digits, or left blank."
                return
            }
        }

        profile.name = trimmedName
        profile.heightInches = height
        profile.weightLbs = weight
        profile.age = age
        profile.goal = goal
        profile.pin = pin.isEmpty ? nil : pin
        try? context.save()
        savedMessage = "Saved."
    }
}
