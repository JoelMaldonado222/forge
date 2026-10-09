// Forge build 2026-10-05-c — ExerciseDefinition uses an explicit init.
import Foundation
import SwiftData

// MARK: - Muscle groups

/// Every muscle group Forge can highlight on the 3D body.
enum MuscleGroup: String, CaseIterable, Hashable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case abs
    case glutes
    case quads
    case hamstrings
    case calves

    var displayName: String { rawValue.capitalized }
}

// MARK: - Training goals

struct FitnessGoals {
    static let all = ["Build muscle", "Lose fat", "Strength"]
}

// MARK: - Exercise definition (static catalog, not persisted)

struct ExerciseDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let met: Double
    let instructions: String
    /// True for conditioning work (HIIT, running, swimming...). Cardio bouts
    /// are logged by time rather than sets x reps x weight.
    let isCardio: Bool
    /// True when the load IS the lifter (pull-ups, dips, push-ups...). The
    /// logging card offers one-tap fill from the profile's current bodyweight.
    let usesBodyweight: Bool

    init(id: String, name: String, primary: [MuscleGroup], secondary: [MuscleGroup], met: Double, instructions: String, isCardio: Bool = false, usesBodyweight: Bool = false) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.met = met
        self.instructions = instructions
        self.isCardio = isCardio
        self.usesBodyweight = usesBodyweight
    }
}

// MARK: - Persisted models

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var heightInches: Double
    var weightLbs: Double
    var age: Int
    var goal: String
    var createdAt: Date
    /// Optional 4-digit PIN asked for on the profile switcher. Stored as plain
    /// text — this is casual privacy (keeps honest eyes off), NOT security.
    var pin: String?

    init(id: UUID = UUID(), name: String, heightInches: Double, weightLbs: Double, age: Int, goal: String, pin: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.heightInches = heightInches
        self.weightLbs = weightLbs
        self.age = age
        self.goal = goal
        self.pin = pin
        self.createdAt = createdAt
    }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    /// The UserProfile.id this session belongs to. Every list filters on it.
    var ownerID: UUID
    var date: Date
    var startTime: Date
    var endTime: Date?
    var notes: String
    @Relationship(deleteRule: .cascade) var sets: [LoggedSet]

    init(id: UUID = UUID(), ownerID: UUID, date: Date = Date(), startTime: Date = Date(), endTime: Date? = nil, notes: String = "", sets: [LoggedSet] = []) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.sets = sets
    }
}

@Model
final class LoggedSet {
    @Attribute(.unique) var id: UUID
    var exerciseId: String
    var exerciseName: String
    var setNumber: Int
    var reps: Int
    var weightLbs: Double
    @Relationship(inverse: \WorkoutSession.sets) var session: WorkoutSession?
    /// Position of this set's exercise in the workout (0 = first exercise
    /// logged). SwiftData doesn't keep the order of `WorkoutSession.sets`,
    /// so without this the recap and History reshuffle exercises on reload.
    /// v7 ADDITIVE field: optional, so existing stores migrate untouched;
    /// sets saved before v7 read back as nil.
    var exerciseOrder: Int?

    init(id: UUID = UUID(), exerciseId: String, exerciseName: String, setNumber: Int, reps: Int, weightLbs: Double, exerciseOrder: Int? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.weightLbs = weightLbs
        self.exerciseOrder = exerciseOrder
    }
}

@Model
final class WaterLog {
    @Attribute(.unique) var id: UUID
    /// The UserProfile.id this entry belongs to.
    var ownerID: UUID
    var date: Date
    var ounces: Double

    init(id: UUID = UUID(), ownerID: UUID, date: Date = Date(), ounces: Double) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.ounces = ounces
    }
}

@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    /// The UserProfile.id this entry belongs to.
    var ownerID: UUID
    var date: Date
    var label: String
    var proteinG: Double
    var calories: Double

    init(id: UUID = UUID(), ownerID: UUID, date: Date = Date(), label: String, proteinG: Double, calories: Double) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.label = label
        self.proteinG = proteinG
        self.calories = calories
    }
}

@Model
final class CardioEntry {
    @Attribute(.unique) var id: UUID
    /// The UserProfile.id this entry belongs to. Every list filters on it.
    var ownerID: UUID
    var date: Date
    var exerciseId: String
    var exerciseName: String
    /// Duration in minutes.
    var durationMin: Double
    /// Optional distance in miles (nil when the user didn't track it).
    var distanceMi: Double?
    var notes: String

    init(id: UUID = UUID(), ownerID: UUID, date: Date = Date(), exerciseId: String, exerciseName: String, durationMin: Double, distanceMi: Double? = nil, notes: String = "") {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.durationMin = durationMin
        self.distanceMi = distanceMi
        self.notes = notes
    }
}
