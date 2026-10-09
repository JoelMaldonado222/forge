import SwiftUI
import SwiftData

/// Post-workout summary: the plain-language recap, stat tiles, and a 3D
/// body highlighting the muscles just trained.
struct WorkoutSummaryView: View {
    var session: WorkoutSession
    var profile: UserProfile
    var cardio: [CardioEntry] = []
    var onDone: () -> Void

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var allSessions: [WorkoutSession]

    @Query(sort: \CardioEntry.date, order: .reverse)
    private var allCardio: [CardioEntry]

    private var sets: [LoggedSet] { session.sets }
    private var totalVolume: Double { TrainingMath.volumeLoad(sets: sets) }
    private var calories: Double {
        TrainingMath.estimatedCalories(session: session, cardio: cardio, bodyWeightLbs: profile.weightLbs)
    }
    private var exerciseCount: Int { TrainingMath.distinctExerciseCount(session: session) }
    private var cardioMinutes: Double { cardio.reduce(0) { $0 + $1.durationMin } }

    private var recap: String {
        SummaryGenerator.sessionRecapWithInsights(
            name: profile.name,
            session: session,
            profile: profile,
            cardio: cardio,
            allSessions: allSessions.filter { $0.ownerID == profile.id },
            allCardio: allCardio.filter { $0.ownerID == profile.id }
        )
    }

    private var durationText: String {
        guard let end = session.endTime else { return "\u{2014}" }
        let minutes = max(1, Int(end.timeIntervalSince(session.startTime) / 60))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var intensities: [MuscleGroup: Double] {
        TrainingMath.highlightIntensities(sets: sets, cardio: cardio)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session recap")
                        .font(.headline)
                    Text(recap)
                        .font(.body)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Total volume", value: "\(Int(totalVolume)) lb", icon: "scalemass")
                    StatTile(title: "Est. calories", value: "\(Int(calories))", icon: "flame")
                    StatTile(title: "Exercises", value: "\(exerciseCount)", icon: "dumbbell")
                    StatTile(title: "Duration", value: durationText, icon: "timer")
                    if cardioMinutes > 0 {
                        StatTile(title: "Cardio", value: "\(Int(cardioMinutes)) min", icon: "heart.fill")
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Muscles trained")
                        .font(.headline)
                    Text("Drag to rotate \u{00B7} pinch to zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Body3DView(intensities: intensities)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Button("Done", action: onDone)
                    .buttonStyle(VoltButtonStyle())
                    .controlSize(.large)
                    .padding(.bottom)
            }
            .padding(.vertical)
        }
        .navigationTitle("Workout complete")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

/// Small stat tile for the summary grid.
struct StatTile: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(ForgeTheme.volt)
            Text(value)
                .font(.title3)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
