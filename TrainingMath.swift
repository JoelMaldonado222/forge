import Foundation

/// Pure training math for Forge.
///
/// Every value produced here is an *estimate* based on widely used fitness
/// formulas. They are good enough to track trends and progressive overload,
/// but they are not medical advice and should never be presented as exact.
enum TrainingMath {

    /// Total load moved: sum of (reps x weight) across every set, in pounds.
    static func volumeLoad(sets: [LoggedSet]) -> Double {
        sets.reduce(0) { $0 + Double($1.reps) * $1.weightLbs }
    }

    /// Epley estimated one-rep max. Only meaningful for low-rep sets;
    /// callers should ignore results for sets above ~12 reps.
    static func epleyOneRepMax(weightLbs: Double, reps: Int) -> Double {
        weightLbs * (1.0 + Double(reps) / 30.0)
    }

    /// Rough calories burned from the standard MET equation:
    /// calories = MET x 3.5 x bodyweight(kg) / 200 x minutes.
    static func caloriesBurned(met: Double, bodyWeightLbs: Double, minutes: Double) -> Double {
        let kg = bodyWeightLbs / 2.20462
        return met * 3.5 * kg / 200.0 * minutes
    }

    /// Daily water target: a flat 1 gallon (128 oz, ~3.8 L), close to the
    /// IOM adequate intake of 3.7 L/day for men (2.7 L for women) before
    /// exercise. A coaching heuristic, not clinical advice. `weightLbs` is
    /// kept so a bodyweight-scaled target can return without API churn.
    static func waterTargetOz(weightLbs: Double) -> Double {
        128
    }

    /// Evidence-based protein target in grams per day: 1.8 g per kg of
    /// bodyweight, the middle of the 1.6–2.2 g/kg/day range. Anchor: Morton
    /// et al. 2018 (BJSM) meta-regression of 49 trials found the muscle-gain
    /// dose-response flattening at ~1.62 g/kg/day (95% CI 1.03–2.20); the
    /// ISSN position stand gives 1.4–2.0 g/kg/day. 1.8 is a central
    /// estimate, not a pass/fail line.
    static func proteinTargetG(weightLbs: Double) -> Double {
        (weightLbs / 2.20462) * 1.8
    }

    /// The full evidence-based protein range in grams per day.
    static func proteinTargetRangeG(weightLbs: Double) -> (low: Double, high: Double) {
        let kg = weightLbs / 2.20462
        return (kg * 1.6, kg * 2.2)
    }

    /// Volume attributed to each muscle group. Primary muscles get the full
    /// set volume; secondary muscles get half credit. Used to drive the
    /// 3D body highlight and the weekly muscle bars.
    static func muscleVolume(sets: [LoggedSet]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for set in sets {
            guard let definition = ExerciseLibrary.definition(for: set.exerciseId) else { continue }
            let volume = Double(set.reps) * set.weightLbs
            for muscle in definition.primary {
                result[muscle, default: 0] += volume
            }
            for muscle in definition.secondary {
                result[muscle, default: 0] += volume * 0.5
            }
        }
        return result
    }

    /// Sum of volumeLoad across sessions.
    static func totalVolume(sessions: [WorkoutSession]) -> Double {
        sessions.reduce(0) { $0 + volumeLoad(sets: $1.sets) }
    }

    /// Number of distinct exercises in a session.
    static func distinctExerciseCount(session: WorkoutSession) -> Int {
        Set(session.sets.map(\.exerciseId)).count
    }

    /// Estimated session calories. Assumes roughly 4 minutes of work per
    /// distinct exercise block (sets + rest). Unknown exercises use MET 5.0.
    static func estimatedCalories(session: WorkoutSession, bodyWeightLbs: Double) -> Double {
        let minutesPerExercise = 4.0
        let ids = Set(session.sets.map(\.exerciseId))
        return ids.reduce(0.0) { total, id in
            let met = ExerciseLibrary.definition(for: id)?.met ?? 5.0
            return total + caloriesBurned(met: met, bodyWeightLbs: bodyWeightLbs, minutes: minutesPerExercise)
        }
    }

    /// Estimated session calories including cardio, which is counted by its
    /// real duration: MET x duration for each cardio bout.
    static func estimatedCalories(session: WorkoutSession, cardio: [CardioEntry], bodyWeightLbs: Double) -> Double {
        estimatedCalories(session: session, bodyWeightLbs: bodyWeightLbs)
            + cardioCalories(entries: cardio, bodyWeightLbs: bodyWeightLbs)
    }

    /// Calories from cardio entries via the MET equation and logged minutes.
    static func cardioCalories(entries: [CardioEntry], bodyWeightLbs: Double) -> Double {
        entries.reduce(0.0) { total, entry in
            let met = ExerciseLibrary.definition(for: entry.exerciseId)?.met ?? 7.0
            return total + caloriesBurned(met: met, bodyWeightLbs: bodyWeightLbs, minutes: entry.durationMin)
        }
    }

    /// Cardio-attributed minutes per muscle: primary muscles get full
    /// minutes, secondary get half. Drives the 3D highlight for conditioning.
    static func cardioMuscleMinutes(entries: [CardioEntry]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for entry in entries {
            guard let definition = ExerciseLibrary.definition(for: entry.exerciseId) else { continue }
            for muscle in definition.primary {
                result[muscle, default: 0] += entry.durationMin
            }
            for muscle in definition.secondary {
                result[muscle, default: 0] += entry.durationMin * 0.5
            }
        }
        return result
    }

    /// 0...1 highlight intensities combining lifting volume and cardio.
    /// Each source is normalized independently (by its own max), then the
    /// stronger signal wins per muscle — lifting and cardio use different
    /// units, so they are never added together.
    /// Any muscle touched by at least one set gets a base glow of 0.35, so
    /// a light session still lights up what you trained.
    static func highlightIntensities(sets: [LoggedSet], cardio: [CardioEntry]) -> [MuscleGroup: Double] {
        let liftVolumes = muscleVolume(sets: sets)
        let liftMax = liftVolumes.values.max() ?? 0
        let cardioMinutes = cardioMuscleMinutes(entries: cardio)
        let cardioMax = cardioMinutes.values.max() ?? 0

        var touched: Set<MuscleGroup> = []
        for set in sets {
            guard let definition = ExerciseLibrary.definition(for: set.exerciseId) else { continue }
            touched.formUnion(definition.primary)
            touched.formUnion(definition.secondary)
        }

        var out: [MuscleGroup: Double] = [:]
        for muscle in MuscleGroup.allCases {
            let lift = liftMax > 0 ? (liftVolumes[muscle] ?? 0) / liftMax : 0
            let cond = cardioMax > 0 ? (cardioMinutes[muscle] ?? 0) / cardioMax : 0
            let base: Double = touched.contains(muscle) ? 0.35 : 0
            let combined = max(lift, cond, base)
            if combined > 0 {
                out[muscle] = min(combined, 1.0)
            }
        }
        return out
    }

    /// Cardio bouts logged in the same workout as `session`. The workout
    /// screen stamps each cardio entry with the session's start time, so a
    /// match is "same owner, start times within a couple of seconds" (the
    /// slack covers backups, which store dates to the whole second). This
    /// keeps two workouts on the same day from showing each other's cardio.
    static func cardio(for session: WorkoutSession, in entries: [CardioEntry]) -> [CardioEntry] {
        entries.filter {
            $0.ownerID == session.ownerID
                && abs($0.date.timeIntervalSince(session.startTime)) < 2
        }
    }

    /// Muscle groups ranked by attributed volume, highest first.
    static func topMuscles(sets: [LoggedSet], limit: Int? = nil) -> [MuscleVolume] {
        let sorted = muscleVolume(sets: sets).sorted { $0.value > $1.value }
        let sliced: [(key: MuscleGroup, value: Double)]
        if let limit {
            sliced = Array(sorted.prefix(limit))
        } else {
            sliced = sorted
        }
        return sliced.map { MuscleVolume(group: $0.key, volume: $0.value) }
    }
}

/// A muscle group paired with its attributed training volume.
struct MuscleVolume: Identifiable {
    let group: MuscleGroup
    let volume: Double
    var id: MuscleGroup { group }
}
