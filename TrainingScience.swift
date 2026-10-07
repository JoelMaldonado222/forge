import Foundation

// MARK: - Weekly volume landmarks (hard sets per week, per muscle group)
//
// Numbers are the Renaissance Periodization MV / MEV / MAV / MRV framework
// (Mike Israetel), corroborated across multiple publications of his table,
// and consistent with the Schoenfeld, Ogborn & Krieger (2017) meta-analysis
// finding a dose-response up to ~10+ weekly sets.
//
// CONFIDENCE: these are practitioner landmarks — expert synthesis, NOT
// per-muscle randomized-trial thresholds. The app must always present them
// as estimates ("expert landmark, not a lab trial") and never as promises.
// Abs and calves have thin evidence (wide inter-source spreads); forearms
// have NO published landmarks at all.

/// One muscle's weekly hard-set landmarks.
struct VolumeLandmarks {
    let muscle: MuscleGroup
    /// Maintenance Volume — minimum to not lose muscle.
    let mv: Double
    /// Minimum Effective Volume — minimum that grows muscle.
    let mev: Double
    /// Maximum Adaptive Volume — the optimal growth zone (inclusive range).
    let mavLow: Double
    let mavHigh: Double
    /// Maximum Recoverable Volume — past this, fatigue exceeds recovery.
    let mrv: Double
    /// .thin where sources disagree widely (abs, calves).
    let evidence: EvidenceQuality

    enum EvidenceQuality {
        case established
        case thin
    }
}

/// Where a week's hard-set count falls against the landmarks.
enum VolumeVerdict {
    case untrained
    case belowMaintenance
    case maintenance
    case growing
    case productive
    case high
    case overreaching
    case noData
}

enum TrainingScience {

    /// Displayed wherever landmarks appear: they are starting estimates.
    static let confidenceNote = "Expert landmark, not a lab trial."

    /// Individual response varies enormously — surfaced in the app so
    /// projections are never read as promises. Hubal et al. (2005): 585
    /// people on the same 12-week program gained 0% to +250% strength and
    /// -2% to +59% muscle size; some gained nothing.
    static let varianceFootnote =
        "One more honest note: in a 12-week study of 585 people on the identical " +
        "program (Hubal et al. 2005), strength gains ranged from 0% to +250%. " +
        "These landmarks describe group averages — your response is your own."

    static let allLandmarks: [VolumeLandmarks] = [
        VolumeLandmarks(muscle: .chest,      mv: 8, mev: 10, mavLow: 12, mavHigh: 20, mrv: 22, evidence: .established),
        VolumeLandmarks(muscle: .back,       mv: 8, mev: 10, mavLow: 14, mavHigh: 22, mrv: 25, evidence: .established),
        VolumeLandmarks(muscle: .shoulders,  mv: 6, mev: 8,  mavLow: 16, mavHigh: 22, mrv: 26, evidence: .established),
        VolumeLandmarks(muscle: .biceps,     mv: 4, mev: 6,  mavLow: 14, mavHigh: 20, mrv: 26, evidence: .established),
        VolumeLandmarks(muscle: .triceps,    mv: 4, mev: 6,  mavLow: 10, mavHigh: 14, mrv: 18, evidence: .established),
        VolumeLandmarks(muscle: .quads,      mv: 6, mev: 8,  mavLow: 12, mavHigh: 18, mrv: 20, evidence: .established),
        VolumeLandmarks(muscle: .hamstrings, mv: 4, mev: 6,  mavLow: 10, mavHigh: 16, mrv: 20, evidence: .established),
        VolumeLandmarks(muscle: .glutes,     mv: 0, mev: 0,  mavLow: 4,  mavHigh: 12, mrv: 16, evidence: .established),
        VolumeLandmarks(muscle: .calves,     mv: 4, mev: 6,  mavLow: 8,  mavHigh: 16, mrv: 20, evidence: .thin),
        VolumeLandmarks(muscle: .abs,        mv: 0, mev: 0,  mavLow: 10, mavHigh: 20, mrv: 25, evidence: .thin),
        // .forearms intentionally absent: no published landmarks exist.
    ]

    static func landmarks(for muscle: MuscleGroup) -> VolumeLandmarks? {
        allLandmarks.first { $0.muscle == muscle }
    }

    /// Hard-set equivalents per muscle for landmark purposes.
    ///
    /// A lifted set counts when it has 5–30 reps (the RP "hard set" rep
    /// range). Only prime-mover (primary) muscles get full credit — indirect
    /// work is already factored into the landmark estimates, so secondary
    /// muscles are not double-counted (RP counting rule).
    ///
    /// Approximation, stated openly: a true "hard set" also requires 0–4
    /// reps in reserve, which the app doesn't track. Cardio bouts count 0.5
    /// hard-set equivalents for their primary muscles — a coaching
    /// assumption, since conditioning volume isn't part of the landmark
    /// research.
    static func hardSetCounts(sets: [LoggedSet], cardio: [CardioEntry]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for set in sets {
            guard (5...30).contains(set.reps),
                  let definition = ExerciseLibrary.definition(for: set.exerciseId) else { continue }
            for muscle in definition.primary {
                result[muscle, default: 0] += 1.0
            }
        }
        for entry in cardio {
            guard let definition = ExerciseLibrary.definition(for: entry.exerciseId) else { continue }
            for muscle in definition.primary {
                result[muscle, default: 0] += 0.5
            }
        }
        return result
    }

    /// Verdict plus a one-line, honestly-framed explanation.
    static func verdict(for muscle: MuscleGroup, hardSets: Double) -> (VolumeVerdict, String) {
        guard let lm = landmarks(for: muscle) else {
            return (.noData, "No published volume landmarks exist for forearms — they get plenty of indirect work from pulling and grip, so train them if you enjoy it.")
        }
        let n = formatSets(hardSets)
        if hardSets <= 0 {
            let start = lm.mv > 0 ? "Maintenance starts around \(formatSets(lm.mv)) hard sets." : "Even a little direct work beats none."
            return (.untrained, "No hard sets logged this week. \(start)")
        }
        if hardSets < lm.mv {
            return (.belowMaintenance, "\(n) hard sets is below the ~\(formatSets(lm.mv))-set maintenance landmark — expect to hold, not build.")
        }
        if hardSets < lm.mev {
            return (.maintenance, "\(n) hard sets sits in the maintenance zone (~\(formatSets(lm.mv))–\(formatSets(lm.mev))). Add sets to move into growth territory.")
        }
        if hardSets < lm.mavLow {
            return (.growing, "\(n) hard sets is in the growing zone — past the ~\(formatSets(lm.mev)) minimum effective dose, with room to add toward \(formatSets(lm.mavLow))–\(formatSets(lm.mavHigh)).")
        }
        if hardSets <= lm.mavHigh {
            let thin = lm.evidence == .thin ? " (thin evidence here — treat as a rough guide)" : ""
            return (.productive, "\(n) hard sets lands in the productive zone (\(formatSets(lm.mavLow))–\(formatSets(lm.mavHigh))\(thin). Research suggests this is where growth is maximized.")
        }
        if hardSets <= lm.mrv {
            return (.high, "\(n) hard sets is high — near your ~\(formatSets(lm.mrv)) recoverable limit. Watch for stalling performance or soreness past 48–72 hours.")
        }
        return (.overreaching, "\(n) hard sets is past the ~\(formatSets(lm.mrv)) recoverable landmark. Consider a deload week: cut volume 30–50% for about a week while keeping weights heavy.")
    }

    /// "4" or "4.5" — hard-set counts can be fractional via cardio.
    static func formatSets(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
