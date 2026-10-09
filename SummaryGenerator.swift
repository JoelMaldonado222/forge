import Foundation

/// Turns a finished workout into a warm, plain-language recap.
/// All physiology numbers are rough estimates, and the copy says so.
enum SummaryGenerator {

    /// - Parameter cardio: cardio bouts logged with this session (defaults to
    ///   none, so historical recaps without cardio keep working).
    static func sessionRecap(name: String, session: WorkoutSession, profile: UserProfile, cardio: [CardioEntry] = []) -> String {
        let sets = session.sets
        let sortedCardio = cardio.sorted { $0.durationMin > $1.durationMin }
        guard !sets.isEmpty || !sortedCardio.isEmpty else {
            return "\(name), this session has no logged sets yet."
        }

        var lines: [String] = []
        lines.append("\(name), here's your session from \(dateString(session.date)).")
        lines.append("")

        // Exercises in the order they were logged.
        let groups = TrainingMath.exerciseGroups(sets: sets)

        for group in groups {
            let exerciseSets = group.sets
            let displayName = group.name.lowercased()
            let count = exerciseSets.count
            let totalReps = exerciseSets.reduce(0) { $0 + $1.reps }
            let topWeight = exerciseSets.map(\.weightLbs).max() ?? 0
            let volume = TrainingMath.volumeLoad(sets: exerciseSets)
            let setWord = count == 1 ? "set" : "sets"

            var line = "You did \(count) \(setWord) of \(displayName) for \(totalReps) total reps"
            if topWeight > 0 {
                line += " at up to \(fmt(topWeight)) lb"
            } else {
                line += " (bodyweight)"
            }
            line += " \u{2014} that's about \(fmt(volume)) lb of volume."

            let best1RM = exerciseSets
                .filter { (1...12).contains($0.reps) }
                .map { TrainingMath.epleyOneRepMax(weightLbs: $0.weightLbs, reps: $0.reps) }
                .max()
            if let best1RM, best1RM > 0 {
                line += " Your best set estimates a \(fmt(best1RM)) lb one-rep max."
            }
            lines.append(line)
            lines.append("")
        }

        let totalVolume = TrainingMath.volumeLoad(sets: sets)
        let calories = TrainingMath.estimatedCalories(session: session, cardio: sortedCardio, bodyWeightLbs: profile.weightLbs)
        let exerciseCount = groups.count
        let exerciseWord = exerciseCount == 1 ? "exercise" : "exercises"

        for entry in sortedCardio {
            var line = "Cardio: \(Int(entry.durationMin)) min of \(entry.exerciseName.lowercased())"
            if let miles = entry.distanceMi, miles > 0 {
                line += " (\(String(format: "%g", miles)) mi)"
            }
            let entryCalories = TrainingMath.cardioCalories(entries: [entry], bodyWeightLbs: profile.weightLbs)
            line += " \u{2014} roughly \(fmt(entryCalories)) calories."
            lines.append(line)
            lines.append("")
        }

        var total = ""
        if !sets.isEmpty {
            total += "All in, you moved about \(fmt(totalVolume)) lb across \(exerciseCount) \(exerciseWord)"
            if let end = session.endTime {
                let minutes = max(1, Int(end.timeIntervalSince(session.startTime) / 60))
                total += " in about \(minutes) minutes"
            }
            total += " and "
        } else {
            total += "In total you "
        }
        total += "burned roughly \(fmt(calories)) calories."
        lines.append(total)
        lines.append("")

        let tops = TrainingMath.topMuscles(sets: sets, limit: 3)
        if !tops.isEmpty {
            let names = tops.map { $0.group.displayName.lowercased() }.joined(separator: ", ")
            lines.append("Biggest contributors: \(names).")
            lines.append("")
        }

        if let firstName = groups.first?.name.lowercased() {
            lines.append("For progressive overload, compare today's top \(firstName) set with last week's \u{2014} small, steady increases beat big jumps. The week-in-context notes below do this comparison for you automatically.")
            lines.append("")
        }

        lines.append("All numbers are estimates from standard training formulas, not medical advice.")
        return lines.joined(separator: "\n")
    }

    /// The session recap plus the top 3 insights for the training week —
    /// per-muscle volume verdicts against evidence-based landmarks and a
    /// week-over-week progressive-overload comparison.
    static func sessionRecapWithInsights(
        name: String,
        session: WorkoutSession,
        profile: UserProfile,
        cardio: [CardioEntry] = [],
        allSessions: [WorkoutSession],
        allCardio: [CardioEntry]
    ) -> String {
        var text = sessionRecap(name: name, session: session, profile: profile, cardio: cardio)
        let insights = InsightsEngine.weeklyInsights(
            profileID: profile.id,
            sessions: allSessions,
            cardio: allCardio,
            bodyWeightKg: profile.weightLbs / 2.20462
        )
        let top = Array(insights.prefix(3))
        if !top.isEmpty {
            text += "\n\nThis week in context:\n"
            for insight in top {
                text += "\n\u{2022} \(insight.title): \(insight.body)"
            }
        }
        return text
    }

    // MARK: - Formatting helpers

    private static func fmt(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
