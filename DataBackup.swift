// DataBackup.swift — Forge build 2026-10-06
// Export every profile, workout, set, water log, food entry, and cardio entry
// to a single JSON file, and restore from one. The file is yours: save it to
// the Files app, AirDrop it, or email it to yourself.
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup payload (plain Codable structs, decoupled from SwiftData)

/// Versioned envelope so future Forge versions can still read old backups.
struct ForgeBackup: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var profiles: [BackupProfile]
    var sessions: [BackupSession]
    var waterLogs: [BackupWaterLog]
    var foodEntries: [BackupFoodEntry]
    var cardioEntries: [BackupCardioEntry]
}

struct BackupProfile: Codable {
    var id: UUID
    var name: String
    var heightInches: Double
    var weightLbs: Double
    var age: Int
    var goal: String
    var createdAt: Date
    var pin: String?
}

struct BackupLoggedSet: Codable {
    var id: UUID
    var exerciseId: String
    var exerciseName: String
    var setNumber: Int
    var reps: Int
    var weightLbs: Double
    /// Added in v7. Optional, so backups from earlier versions (which don't
    /// have the key) still decode, and schemaVersion stays 1.
    var exerciseOrder: Int?
}

struct BackupSession: Codable {
    var id: UUID
    var ownerID: UUID
    var date: Date
    var startTime: Date
    var endTime: Date?
    var notes: String
    var sets: [BackupLoggedSet]
}

struct BackupWaterLog: Codable {
    var id: UUID
    var ownerID: UUID
    var date: Date
    var ounces: Double
}

struct BackupFoodEntry: Codable {
    var id: UUID
    var ownerID: UUID
    var date: Date
    var label: String
    var proteinG: Double
    var calories: Double
}

struct BackupCardioEntry: Codable {
    var id: UUID
    var ownerID: UUID
    var date: Date
    var exerciseId: String
    var exerciseName: String
    var durationMin: Double
    var distanceMi: Double?
    var notes: String
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case notABackup
    case restoreIncomplete(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "This backup was made by a newer version of Forge (schema v\(v)). Update Forge, then try again."
        case .notABackup:
            return "That file doesn't look like a Forge backup."
        case .restoreIncomplete(let reason):
            return "The restore stopped partway (\(reason)). Your backup file is fine \u{2014} run Restore again with the same file."
        }
    }
}

// MARK: - Export / import

enum BackupManager {
    static let schemaVersion = 1

    /// Reads the whole store, encodes it as JSON, and writes it to a temp
    /// file. Returns the file URL for sharing.
    static func makeBackup(in context: ModelContext) throws -> URL {
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let waterLogs = try context.fetch(FetchDescriptor<WaterLog>())
        let foodEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        let cardioEntries = try context.fetch(FetchDescriptor<CardioEntry>())

        let backup = ForgeBackup(
            schemaVersion: schemaVersion,
            exportedAt: Date(),
            profiles: profiles.map { p in
                BackupProfile(id: p.id, name: p.name, heightInches: p.heightInches,
                              weightLbs: p.weightLbs, age: p.age, goal: p.goal,
                              createdAt: p.createdAt, pin: p.pin)
            },
            sessions: sessions.map { s in
                BackupSession(id: s.id, ownerID: s.ownerID, date: s.date,
                              startTime: s.startTime, endTime: s.endTime, notes: s.notes,
                              sets: s.sets.map { ls in
                                  BackupLoggedSet(id: ls.id, exerciseId: ls.exerciseId,
                                                  exerciseName: ls.exerciseName, setNumber: ls.setNumber,
                                                  reps: ls.reps, weightLbs: ls.weightLbs,
                                                  exerciseOrder: ls.exerciseOrder)
                              })
            },
            waterLogs: waterLogs.map { w in
                BackupWaterLog(id: w.id, ownerID: w.ownerID, date: w.date, ounces: w.ounces)
            },
            foodEntries: foodEntries.map { f in
                BackupFoodEntry(id: f.id, ownerID: f.ownerID, date: f.date, label: f.label,
                                proteinG: f.proteinG, calories: f.calories)
            },
            cardioEntries: cardioEntries.map { c in
                BackupCardioEntry(id: c.id, ownerID: c.ownerID, date: c.date,
                                  exerciseId: c.exerciseId, exerciseName: c.exerciseName,
                                  durationMin: c.durationMin, distanceMi: c.distanceMi, notes: c.notes)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Forge-Backup-\(stamp.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    struct RestoreSummary {
        var profiles = 0
        var sessions = 0
        var sets = 0
        var waterLogs = 0
        var foodEntries = 0
        var cardioEntries = 0
    }

    /// Replaces everything in the store with the backup's contents.
    /// Original IDs are preserved so profile links stay intact.
    static func restore(from url: URL, in context: ModelContext) throws -> RestoreSummary {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: ForgeBackup
        do {
            backup = try decoder.decode(ForgeBackup.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        guard backup.schemaVersion == schemaVersion else {
            throw BackupError.unsupportedVersion(backup.schemaVersion)
        }

        // Phase 1: wipe current data and commit the wipe. The backup reuses
        // the same unique IDs as the rows being deleted, and inserting an ID
        // while its old row is still pending deletion in the same save is
        // undefined territory for SwiftData's unique constraint. Committing
        // the delete first keeps phase 2 a clean insert.
        // (Sessions cascade-delete their sets; sets are also deleted
        // explicitly in case any are orphaned.)
        do {
            for session in try context.fetch(FetchDescriptor<WorkoutSession>()) { context.delete(session) }
            for set in try context.fetch(FetchDescriptor<LoggedSet>()) { context.delete(set) }
            for w in try context.fetch(FetchDescriptor<WaterLog>()) { context.delete(w) }
            for f in try context.fetch(FetchDescriptor<FoodEntry>()) { context.delete(f) }
            for c in try context.fetch(FetchDescriptor<CardioEntry>()) { context.delete(c) }
            for p in try context.fetch(FetchDescriptor<UserProfile>()) { context.delete(p) }
            try context.save()
        } catch {
            // Nothing was committed — the current data is untouched.
            context.rollback()
            throw error
        }

        // Phase 2: insert everything from the file.
        var summary = RestoreSummary()
        for b in backup.profiles {
            context.insert(UserProfile(id: b.id, name: b.name, heightInches: b.heightInches,
                                       weightLbs: b.weightLbs, age: b.age, goal: b.goal,
                                       pin: b.pin, createdAt: b.createdAt))
            summary.profiles += 1
        }
        for s in backup.sessions {
            let session = WorkoutSession(id: s.id, ownerID: s.ownerID, date: s.date,
                                         startTime: s.startTime, endTime: s.endTime, notes: s.notes)
            context.insert(session)
            for bs in s.sets {
                let set = LoggedSet(id: bs.id, exerciseId: bs.exerciseId, exerciseName: bs.exerciseName,
                                    setNumber: bs.setNumber, reps: bs.reps, weightLbs: bs.weightLbs,
                                    exerciseOrder: bs.exerciseOrder)
                set.session = session
                session.sets.append(set)
                context.insert(set)
                summary.sets += 1
            }
            summary.sessions += 1
        }
        for w in backup.waterLogs {
            context.insert(WaterLog(id: w.id, ownerID: w.ownerID, date: w.date, ounces: w.ounces))
            summary.waterLogs += 1
        }
        for f in backup.foodEntries {
            context.insert(FoodEntry(id: f.id, ownerID: f.ownerID, date: f.date, label: f.label,
                                     proteinG: f.proteinG, calories: f.calories))
            summary.foodEntries += 1
        }
        for c in backup.cardioEntries {
            context.insert(CardioEntry(id: c.id, ownerID: c.ownerID, date: c.date,
                                       exerciseId: c.exerciseId, exerciseName: c.exerciseName,
                                       durationMin: c.durationMin, distanceMi: c.distanceMi, notes: c.notes))
            summary.cardioEntries += 1
        }

        do {
            try context.save()
        } catch {
            // Don't leave half-inserted rows sitting in the context. The
            // backup file itself is untouched, so the restore can be retried.
            context.rollback()
            throw BackupError.restoreIncomplete(error.localizedDescription)
        }
        return summary
    }
}

// MARK: - UI

/// Profile tab → "Back up & restore".
struct BackupView: View {
    @Environment(\.modelContext) private var context

    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImportURL: URL?
    @State private var showRestoreConfirm = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                Button {
                    doExport()
                } label: {
                    Label("Back up my data", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share backup file", systemImage: "square.and.arrow.up.on.square")
                    }
                }

                Text("Saves every profile, workout, set, water log, food entry, and cardio entry into one file. Share it to the Files app, AirDrop, or email so you keep a copy outside Forge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Backup")
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from backup", systemImage: "square.and.arrow.down")
                }

                Text("Replaces everything currently in Forge with the backup file. Only needed if your data was lost or you moved to a new phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Restore")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(statusIsError ? ForgeTheme.danger : ForgeTheme.success)
                }
            }
        }
        .navigationTitle("Backup & restore")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showRestoreConfirm = true
            case .failure(let error):
                setStatus("Couldn't open that file: \(error.localizedDescription)", isError: true)
            }
        }
        .alert("Replace all data?", isPresented: $showRestoreConfirm) {
            Button("Restore backup", role: .destructive) { doRestore() }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("This deletes everything currently in Forge and replaces it with the backup file. This can't be undone.")
        }
    }

    private func doExport() {
        isExporting = true
        defer { isExporting = false }
        do {
            exportURL = try BackupManager.makeBackup(in: context)
            setStatus("Backup ready — tap \"Share backup file\" to save it somewhere safe.", isError: false)
        } catch {
            setStatus("Backup failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func doRestore() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        do {
            let s = try BackupManager.restore(from: url, in: context)
            exportURL = nil
            setStatus("Restored \(s.profiles) profiles, \(s.sessions) workouts (\(s.sets) sets), \(s.waterLogs) water logs, \(s.foodEntries) food entries, \(s.cardioEntries) cardio entries.", isError: false)
        } catch {
            setStatus("Restore failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
