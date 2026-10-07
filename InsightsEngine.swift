import Foundation

/// One evidence-framed observation about the user's training week.
/// Tones drive the card color in the UI: good = green, warning = orange,
/// info = blue.
struct Insight: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let tone: Tone

    enum Tone {
        case good
        case warning
        case info
    }
}

/// Turns a week of training into honest, research-framed observations.
/// Everything is a range or a suggestion — never a promised outcome.
enum InsightsEngine {

    /// - Parameters:
    ///   - profileID: only this profile's data is considered.
    ///   - sessions: all of the profile's sessions (the engine picks its own
    ///     7-day windows, so callers pass everything and stay simple).
    ///   - cardio: all of the profile's cardio entries.
    ///   - bodyWeightKg: currently informational (kept for API stability as
    ///     future insights may scale by bodyweight).
    static func weeklyInsights(
        profileID: UUID,
        sessions: [WorkoutSession],
        cardio: [CardioEntry],
        bodyWeightKg: Double
    ) -> [Insight] {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let thisWeekSessions = sessions.filter { $0.ownerID == profileID && $0.date >= weekAgo }
        let lastWeekSessions = sessions.filter { $0.ownerID == profileID && $0.date >= twoWeeksAgo && $0.date < weekAgo }
        let thisWeekCardio = cardio.filter { $0.ownerID == profileID && $0.date >= weekAgo }
        let lastWeekCardio = cardio.filter { $0.ownerID == profileID && $0.date >= twoWeeksAgo && $0.date < weekAgo }

        guard !thisWeekSessions.isEmpty || !thisWeekCardio.isEmpty else {
            return [Insight(
                title: "No training logged in the last 7 days",
                body: "Log a workout and Forge will compare your per-muscle volume against evidence-based landmarks (\(TrainingScience.confidenceNote))",
                tone: .info
            )]
        }

        var insights: [Insight] = []

        let thisCounts = TrainingScience.hardSetCounts(
            sets: thisWeekSessions.flatMap(\.sets), cardio: thisWeekCardio)
        let lastCounts = TrainingScience.hardSetCounts(
            sets: lastWeekSessions.flatMap(\.sets), cardio: lastWeekCardio)

        // 1. Per-muscle verdicts against the landmarks.
        for muscle in MuscleGroup.allCases {
            let count = thisCounts[muscle, default: 0]
            let (verdict, message) = TrainingScience.verdict(for: muscle, hardSets: count)
            switch verdict {
            case .noData:
                continue // Forearms: no published landmarks; skip quietly.
            case .untrained:
                insights.append(Insight(title: "\(muscle.displayName): not trained", body: message, tone: .info))
            case .belowMaintenance:
                insights.append(Insight(title: "\(muscle.displayName): below maintenance", body: message, tone: .warning))
            case .maintenance:
                insights.append(Insight(title: "\(muscle.displayName): maintenance", body: message, tone: .info))
            case .growing:
                insights.append(Insight(title: "\(muscle.displayName): growing zone", body: message, tone: .info))
            case .productive:
                insights.append(Insight(title: "\(muscle.displayName): productive zone", body: message, tone: .good))
            case .high:
                insights.append(Insight(title: "\(muscle.displayName): high volume", body: message, tone: .info))
            case .overreaching:
                insights.append(Insight(title: "\(muscle.displayName): above recoverable", body: message, tone: .warning))
            }
        }

        // 2. Frequency check: research favors ~2x per muscle per week
        // (Schoenfeld et al. 2016) over 1x for hypertrophy.
        let daysTrained = trainingDaysByMuscle(
            sessions: thisWeekSessions, cardio: thisWeekCardio, since: weekAgo)
        for muscle in MuscleGroup.allCases {
            guard let lm = TrainingScience.landmarks(for: muscle), lm.mev > 0 else { continue }
            let days = daysTrained[muscle, default: 0]
            let count = thisCounts[muscle, default: 0]
            if days == 1 && count >= lm.mev {
                insights.append(Insight(
                    title: "\(muscle.displayName): trained once this week",
                    body: "Research (Schoenfeld et al. 2016) finds training a muscle about twice per week beats once per week for growth. Splitting these \(TrainingScience.formatSets(count)) sets across two days could help.",
                    tone: .info
                ))
            }
        }

        // 3. Progressive overload: this week vs last week, per muscle.
        let hasHistory = !lastWeekSessions.isEmpty || !lastWeekCardio.isEmpty
        if hasHistory {
            let movers = MuscleGroup.allCases.compactMap { muscle -> (MuscleGroup, Double, Double)? in
                let thisC = thisCounts[muscle, default: 0]
                let lastC = lastCounts[muscle, default: 0]
                guard thisC > 0 || lastC > 0 else { return nil }
                return (muscle, thisC, lastC)
            }.sorted { abs($0.1 - $0.2) > abs($1.1 - $1.2) }

            if let (muscle, thisC, lastC) = movers.first {
                let delta = thisC - lastC
                let name = muscle.displayName.lowercased()
                if delta > 0.5 {
                    insights.append(Insight(
                        title: "Progressive overload: \(name)",
                        body: "Up from \(TrainingScience.formatSets(lastC)) to \(TrainingScience.formatSets(thisC)) hard sets vs last week. Small, steady increases like this are what drive long-term progress.",
                        tone: .good
                    ))
                } else if delta < -0.5 {
                    insights.append(Insight(
                        title: "\(muscle.displayName) volume dipped",
                        body: "Down from \(TrainingScience.formatSets(lastC)) to \(TrainingScience.formatSets(thisC)) hard sets vs last week. One easy week is fine — two in a row is a plateau signal.",
                        tone: .warning
                    ))
                } else if thisC > 0 {
                    insights.append(Insight(
                        title: "Steady week for \(name)",
                        body: "Volume held at \(TrainingScience.formatSets(thisC)) hard sets, matching last week. To keep progressing, add a set or a rep next time out.",
                        tone: .info
                    ))
                }
            }
        } else {
            insights.append(Insight(
                title: "First week logged",
                body: "Keep training and Forge will compare each week against the last to track progressive overload.",
                tone: .info
            ))
        }

        // 4. Always close with the honesty footnote.
        insights.append(Insight(
            title: "A note on individual response",
            body: TrainingScience.varianceFootnote,
            tone: .info
        ))

        // Warnings first, then info, then good news.
        let priority: [Insight.Tone: Int] = [.warning: 0, .info: 1, .good: 2]
        return insights.sorted { (priority[$0.tone] ?? 3) < (priority[$1.tone] ?? 3) }
    }

    // MARK: - Helpers

    /// Distinct days each muscle got meaningful work (>= 0.5 hard-set
    /// equivalents) inside the window.
    private static func trainingDaysByMuscle(
        sessions: [WorkoutSession],
        cardio: [CardioEntry],
        since: Date
    ) -> [MuscleGroup: Int] {
        let calendar = Calendar.current
        var daysByMuscle: [MuscleGroup: Set<Date>] = [:]

        for session in sessions where session.date >= since {
            let day = calendar.startOfDay(for: session.date)
            let counts = TrainingScience.hardSetCounts(sets: session.sets, cardio: [])
            for (muscle, count) in counts where count >= 0.5 {
                daysByMuscle[muscle, default: []].insert(day)
            }
        }
        for entry in cardio where entry.date >= since {
            let day = calendar.startOfDay(for: entry.date)
            let counts = TrainingScience.hardSetCounts(sets: [], cardio: [entry])
            for (muscle, count) in counts where count >= 0.5 {
                daysByMuscle[muscle, default: []].insert(day)
            }
        }

        var result: [MuscleGroup: Int] = [:]
        for (muscle, days) in daysByMuscle {
            result[muscle] = days.count
        }
        return result
    }
}
