import SwiftUI
import SwiftData

/// Profile switcher: lists every profile, switches the active one (asking for
/// the PIN first when one is set), and adds new profiles. Each profile's
/// workouts, water, and food are scoped to it via ownerID, so data never mixes.
struct ProfileSwitcherView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @AppStorage("activeProfileID") private var activeProfileID: String = ""

    @State private var showAddSheet = false
    @State private var pinTarget: UserProfile?
    @State private var pinInput = ""
    @State private var pinError: String?

    /// Bool binding driven by the optional pinTarget, so the sheet doesn't
    /// depend on UserProfile's Identifiable conformance.
    private var pinSheetBinding: Binding<Bool> {
        Binding(
            get: { pinTarget != nil },
            set: { if !$0 { pinTarget = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(profiles, id: \.id) { profile in
                    Button { select(profile) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Text(profile.goal)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let pin = (profile.pin ?? "").trimmingCharacters(in: .whitespaces)
                            if !pin.isEmpty {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if profile.id.uuidString == activeProfileID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ForgeTheme.volt)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Switch profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { showAddSheet = true }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddProfileView()
            }
            .sheet(isPresented: pinSheetBinding) {
                if let profile = pinTarget {
                    PinPromptView(
                        profileName: profile.name,
                        pinInput: $pinInput,
                        pinError: $pinError,
                        onSubmit: {
                            if pinInput == (profile.pin ?? "") {
                                activeProfileID = profile.id.uuidString
                                pinTarget = nil
                                pinInput = ""
                                pinError = nil
                                dismiss()
                            } else {
                                pinError = "Wrong PIN \u{2014} try again."
                            }
                        }
                    )
                }
            }
        }
    }

    private func select(_ profile: UserProfile) {
        let pin = (profile.pin ?? "").trimmingCharacters(in: .whitespaces)
        if pin.isEmpty {
            activeProfileID = profile.id.uuidString
            dismiss()
        } else {
            pinInput = ""
            pinError = nil
            pinTarget = profile
        }
    }
}

/// PIN challenge sheet shown before switching to a PIN-protected profile.
/// No lockout — a wrong PIN just shows an error.
struct PinPromptView: View {
    var profileName: String
    @Binding var pinInput: String
    @Binding var pinError: String?
    var onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the PIN for \(profileName).")
                    SecureField("PIN", text: $pinInput)
                        .keyboardType(.numberPad)
                }
                if let pinError {
                    Section {
                        Text(pinError).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Unlock", action: onSubmit)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Profile PIN")
        }
    }
}

/// Creates a new profile (name, stats, goal, optional PIN) and makes it active.
struct AddProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("activeProfileID") private var activeProfileID: String = ""

    @State private var name = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var goal = FitnessGoals.all[0]
    @State private var pinText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
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

                Section("Profile PIN (optional)") {
                    SecureField("4-digit PIN", text: $pinText)
                        .keyboardType(.numberPad)
                    Text("A PIN keeps casual eyes off this profile on the switcher. It is stored as plain text \u{2014} not encryption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Add Profile", action: save)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("New profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a name."
            return
        }
        guard let height = Double(heightText.trimmingCharacters(in: .whitespaces)), height > 0 else {
            errorMessage = "Enter a valid height in inches."
            return
        }
        guard let weight = Double(weightText.trimmingCharacters(in: .whitespaces)), weight > 0 else {
            errorMessage = "Enter a valid weight in pounds."
            return
        }
        guard let age = Int(ageText.trimmingCharacters(in: .whitespaces)), age > 0, age < 120 else {
            errorMessage = "Enter a valid age."
            return
        }
        let pin = pinText.trimmingCharacters(in: .whitespaces)
        if !pin.isEmpty {
            let digits = CharacterSet.decimalDigits
            guard pin.count == 4, pin.unicodeScalars.allSatisfy({ digits.contains($0) }) else {
                errorMessage = "The PIN must be exactly 4 digits, or left blank."
                return
            }
        }

        let profile = UserProfile(
            name: trimmedName,
            heightInches: height,
            weightLbs: weight,
            age: age,
            goal: goal,
            pin: pin.isEmpty ? nil : pin
        )
        context.insert(profile)
        try? context.save()
        activeProfileID = profile.id.uuidString
        dismiss()
    }
}
