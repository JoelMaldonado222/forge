import SwiftUI
import SwiftData

/// Profile tab: edit stats and goal, see computed daily targets.
struct ProfileView: View {
    var profile: UserProfile
    @Environment(\.modelContext) private var context

    private enum Field: Hashable {
        case name, height, weight, age, pin
    }

    @FocusState private var focusedField: Field?
    @State private var name: String
    @State private var heightText: String
    @State private var weightText: String
    @State private var ageText: String
    @State private var goal: String
    @State private var pinText: String
    @State private var status: (message: String, isError: Bool)?

    init(profile: UserProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _heightText = State(initialValue: ForgeInput.display(profile.heightInches))
        _weightText = State(initialValue: ForgeInput.display(profile.weightLbs))
        _ageText = State(initialValue: "\(profile.age)")
        _goal = State(initialValue: profile.goal)
        _pinText = State(initialValue: profile.pin ?? "")
    }

    /// Every editable value, so any edit clears a stale "Saved." message.
    private var formValues: [String] { [name, heightText, weightText, ageText, goal, pinText] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                    LabeledContent("Height (in)") {
                        TextField("Inches", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .height)
                    }
                    LabeledContent("Weight (lb)") {
                        TextField("Pounds", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .weight)
                    }
                    LabeledContent("Age") {
                        TextField("Years", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .age)
                    }
                    Picker("Goal", selection: $goal) {
                        ForEach(FitnessGoals.all, id: \.self) { Text($0) }
                    }
                }

                Section("Daily targets") {
                    let water = TrainingMath.waterTargetOz(weightLbs: profile.weightLbs)
                    let proteinRange = TrainingMath.proteinTargetRangeG(weightLbs: profile.weightLbs)
                    LabeledContent("Water", value: "\(Int(water)) oz/day")
                    LabeledContent("Protein", value: "\(Int(proteinRange.low))\u{2013}\(Int(proteinRange.high)) g/day")
                    Text("Protein range: 1.6\u{2013}2.2 g per kg of bodyweight per day (Morton et al. 2018). Water target is a flat 1 gallon (128 oz) a day. Protein updates when you save a new weight. These are coaching estimates, not medical advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Profile PIN") {
                    SecureField("4-digit PIN (optional)", text: $pinText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .pin)
                    Text("Asked for before switching to this profile. Stored as plain text \u{2014} casual privacy, not encryption. Leave blank for no PIN.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save changes", action: save)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if let status {
                        Text(status.message)
                            .foregroundStyle(status.isError ? ForgeTheme.danger : ForgeTheme.success)
                    }
                }

                Section("Profiles") {
                    NavigationLink {
                        ProfileSwitcherView()
                    } label: {
                        Label("Switch profile", systemImage: "person.2")
                    }
                    Text("Everyone gets their own profile \u{2014} workouts, water, and food never mix between profiles.")
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
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Profile")
            .onChange(of: formValues) {
                status = nil
            }
        }
    }

    private func save() {
        focusedField = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            status = (message: "Please enter a name.", isError: true)
            return
        }
        guard let height = ForgeInput.decimal(heightText), height > 0, height < 120 else {
            status = (message: "Enter your height in inches (for example 70).", isError: true)
            return
        }
        guard let weight = ForgeInput.decimal(weightText), weight > 0, weight < 1000 else {
            status = (message: "Enter your weight in pounds.", isError: true)
            return
        }
        guard let age = ForgeInput.whole(ageText), age > 0, age < 120 else {
            status = (message: "Enter a valid age.", isError: true)
            return
        }

        let pin = pinText.trimmingCharacters(in: .whitespaces)
        if !pin.isEmpty {
            let digits = CharacterSet.decimalDigits
            guard pin.count == 4, pin.unicodeScalars.allSatisfy({ digits.contains($0) }) else {
                status = (message: "The PIN must be exactly 4 digits, or left blank.", isError: true)
                return
            }
        }

        profile.name = trimmedName
        profile.heightInches = height
        profile.weightLbs = weight
        profile.age = age
        profile.goal = goal
        profile.pin = pin.isEmpty ? nil : pin
        do {
            try context.save()
            status = (message: "Saved.", isError: false)
        } catch {
            context.rollback()
            status = (message: "Couldn't save: \(error.localizedDescription)", isError: true)
        }
    }
}
