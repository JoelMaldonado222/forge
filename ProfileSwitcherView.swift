import SwiftUI
import SwiftData

/// Profile switcher: lists every profile, switches the active one (asking for
/// the PIN first when one is set), and adds new profiles. Each profile's
/// workouts, water, and food are scoped to it via ownerID, so data never mixes.
///
/// Pushed from the Profile tab's NavigationStack, so it must NOT wrap itself
/// in another NavigationStack (a nested stack breaks the back button and the
/// toolbar on push).
struct ProfileSwitcherView: View {
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

    /// The profile the app is showing right now (same fallback as RootView).
    private var currentID: UUID? {
        (profiles.first { $0.id.uuidString == activeProfileID } ?? profiles.first)?.id
    }

    var body: some View {
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
                        if !(profile.pin ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if profile.id == currentID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ForgeTheme.volt)
                        }
                    }
                    .contentShape(Rectangle())
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
                    onSubmit: { checkPin(for: profile) }
                )
                .presentationDetents([.medium])
            }
        }
    }

    private func select(_ profile: UserProfile) {
        // Tapping the profile you're already on just goes back.
        if profile.id == currentID {
            dismiss()
            return
        }
        let pin = (profile.pin ?? "").trimmingCharacters(in: .whitespaces)
        if pin.isEmpty {
            activeProfileID = profile.id.uuidString
        } else {
            pinInput = ""
            pinError = nil
            pinTarget = profile
        }
    }

    private func checkPin(for profile: UserProfile) {
        let expected = (profile.pin ?? "").trimmingCharacters(in: .whitespaces)
        if pinInput.trimmingCharacters(in: .whitespaces) == expected {
            pinTarget = nil
            pinInput = ""
            pinError = nil
            // Switching profiles rebuilds every tab for the new owner, which
            // also takes this screen away — no manual dismiss needed.
            activeProfileID = profile.id.uuidString
        } else {
            pinInput = ""
            pinError = "Wrong PIN \u{2014} try again."
        }
    }
}

/// PIN challenge sheet shown before switching to a PIN-protected profile.
/// No lockout — a wrong PIN just shows an error. Unlocks on its own once
/// four digits are typed.
struct PinPromptView: View {
    var profileName: String
    @Binding var pinInput: String
    @Binding var pinError: String?
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var pinFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the PIN for \(profileName).")
                    SecureField("PIN", text: $pinInput)
                        .keyboardType(.numberPad)
                        .focused($pinFocused)
                }
                if let pinError {
                    Section {
                        Text(pinError).foregroundStyle(ForgeTheme.danger)
                    }
                }
                Section {
                    Button("Unlock", action: onSubmit)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(pinInput.isEmpty)
                }
            }
            .navigationTitle("Profile PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { pinFocused = true }
            .onChange(of: pinInput) {
                if pinInput.count == 4 { onSubmit() }
            }
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
                        Text(errorMessage).foregroundStyle(ForgeTheme.danger)
                    }
                }

                Section {
                    Button("Add Profile", action: save)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a name."
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
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "Couldn't save the profile: \(error.localizedDescription)"
            return
        }
        activeProfileID = profile.id.uuidString
        dismiss()
    }
}
