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

    private var intensities: [MuscleGroup: Double] {
        TrainingMath.highlightIntensities(sets: sets, cardio: cardio)
    }

    @State private var showExplainer = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Volume (weight \u{00D7} reps)", value: "\(Int(totalVolume.rounded()).formatted()) lb", icon: "scalemass")
                    StatTile(title: "Est. calories", value: "~\(Int(calories.rounded()))", icon: "flame")
                    StatTile(title: "Exercises", value: "\(exerciseCount)", icon: "dumbbell")
                    StatTile(title: "Sets", value: "\(sets.count)", icon: "square.stack.3d.up")
                    if cardioMinutes > 0 {
                        StatTile(title: "Cardio", value: "\(Int(cardioMinutes)) min", icon: "heart.fill")
                    }
                }
                .padding(.horizontal)

                Button {
                    showExplainer = true
                } label: {
                    Label("What do these numbers mean?", systemImage: "questionmark.circle")
                        .font(.subheadline)
                }

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
                .forgeCard()
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session recap")
                        .font(.headline)
                    Text(recap)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeCard()
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
        .sheet(isPresented: $showExplainer) {
            NavigationStack {
                MetricsExplainerView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplainer = false }
                        }
                    }
            }
        }
    }
}

/// Plain-language explanation of every number Forge shows, with a worked
/// example. Reachable from the workout summary and from History.
struct MetricsExplainerView: View {
    var body: some View {
        List {
            Section {
                Text("Weight \u{00D7} reps, added up across every set. It's the standard way coaches and researchers count how much training you did.")
                Text("Example: 5 sets of 15 reps with the empty 45 lb bar = 5 \u{00D7} 15 \u{00D7} 45 = 3,375 lb.")
                    .foregroundStyle(.secondary)
                Text("It is not force and not \u{201C}work\u{201D} in the physics sense (that would need how far the bar moved). Use it to compare the same lift week to week: more volume on bench than last week means you did more bench. Don't compare it across lifts \u{2014} 3,375 lb of curls is not 3,375 lb of squats.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Volume (lb)")
            }

            Section {
                Text("Type the total weight you moved. For barbell lifts that's plates plus the bar: two 25s on a standard bar is 25 + 25 + 45 = 95 lb. The \u{201C}Empty bar\u{201D} button fills 45.")
                Text("For bodyweight moves Forge fills the share of you that actually moves: all of you on pull-ups and dips, about 64% on push-ups (your feet hold the rest), about a third on hanging leg raises (just your legs). Wearing a weight belt? Add the plate to that number.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("What to type in the weight box")
            }

            Section {
                Text("Estimated with the Epley formula: weight \u{00D7} (1 + reps \u{00F7} 30). Only sets of 12 reps or fewer count, because the formula drifts badly past that \u{2014} a set of 15 shows no estimate on purpose.")
                Text("Example: 135 lb for 8 reps \u{2248} 135 \u{00D7} 1.27 \u{2248} 171 lb. A guide for picking weights, not a promise of what you can lift.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Estimated 1-rep max")
            }

            Section {
                Text("Forge doesn't time workouts, so it assumes about 2 minutes per set (work plus rest) and uses the standard MET formula with your bodyweight. Cardio uses the minutes you log. These are rough estimates \u{2014} real burn can differ by a lot.")
            } header: {
                Text("Calories")
            }

            Section {
                Text("History's weekly insights count sets of 5\u{2013}30 reps toward each muscle's primary target and compare the count to expert volume landmarks (Renaissance Periodization). Forge can't tell how hard a set was, so warm-up sets count too \u{2014} only log your working sets if you want these to be accurate.")
            } header: {
                Text("Hard sets")
            }
        }
        .navigationTitle("How Forge measures")
        .navigationBarTitleDisplayMode(.inline)
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(ForgeTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
