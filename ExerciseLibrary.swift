import Foundation

/// Built-in exercise catalog. MET values are approximate, drawn from the
/// Compendium of Physical Activities ranges for resistance training.
enum ExerciseLibrary {
    static let all: [ExerciseDefinition] = [
        ExerciseDefinition(
            id: "bench-press",
            name: "Bench Press",
            primary: [.chest],
            secondary: [.shoulders, .triceps],
            met: 6.0,
            instructions: "Lie on a flat bench with feet planted. Grip slightly wider than shoulders, lower the bar to mid-chest with control, then press up without bouncing."
        ),
        ExerciseDefinition(
            id: "incline-dumbbell-press",
            name: "Incline Dumbbell Press",
            primary: [.chest],
            secondary: [.shoulders, .triceps],
            met: 6.0,
            instructions: "Set the bench to 30-45 degrees. Press dumbbells from chest height to full extension, keeping a slight tuck in the elbows."
        ),
        ExerciseDefinition(
            id: "dips",
            name: "Dips",
            primary: [.triceps, .chest],
            secondary: [.shoulders],
            met: 7.0,
            instructions: "Support yourself on parallel bars, lean slightly forward, lower until shoulders are near elbow height, then press back up.",
            usesBodyweight: true
        ),
        ExerciseDefinition(
            id: "overhead-press",
            name: "Overhead Press",
            primary: [.shoulders],
            secondary: [.triceps],
            met: 6.0,
            instructions: "Standing or seated, brace your core and press the bar or dumbbells overhead until arms are straight, without arching your lower back."
        ),
        ExerciseDefinition(
            id: "lateral-raise",
            name: "Lateral Raise",
            primary: [.shoulders],
            secondary: [],
            met: 5.0,
            instructions: "With light dumbbells at your sides, raise your arms out to shoulder height with a soft elbow bend, then lower slowly."
        ),
        ExerciseDefinition(
            id: "bicep-curl",
            name: "Bicep Curl",
            primary: [.biceps],
            secondary: [.forearms],
            met: 4.5,
            instructions: "Stand tall with dumbbells at your sides, palms forward. Curl to shoulder height without swinging, then lower under control."
        ),
        ExerciseDefinition(
            id: "hammer-curl",
            name: "Hammer Curl",
            primary: [.biceps],
            secondary: [.forearms],
            met: 4.5,
            instructions: "Hold dumbbells with a neutral grip, thumbs up. Curl across your body line and lower slowly."
        ),
        ExerciseDefinition(
            id: "tricep-pushdown",
            name: "Tricep Pushdown",
            primary: [.triceps],
            secondary: [],
            met: 4.5,
            instructions: "At a cable station, pin your elbows to your sides and push the handle down until arms are straight. Let it rise slowly."
        ),
        ExerciseDefinition(
            id: "skullcrusher",
            name: "Skullcrusher",
            primary: [.triceps],
            secondary: [],
            met: 5.0,
            instructions: "Lying on a bench, hold a bar or dumbbells over your chest, then bend only at the elbows to lower the weight toward your forehead."
        ),
        ExerciseDefinition(
            id: "pull-up",
            name: "Pull-Up",
            primary: [.back],
            secondary: [.biceps],
            met: 8.0,
            instructions: "Hang from a bar with an overhand grip. Pull your chest to the bar, then lower to a full hang. Use assistance if needed.",
            usesBodyweight: true
        ),
        ExerciseDefinition(
            id: "barbell-row",
            name: "Barbell Row",
            primary: [.back],
            secondary: [.biceps],
            met: 7.0,
            instructions: "Hinge at the hips with a flat back, grip the bar, and row it to your lower ribs, squeezing your shoulder blades together."
        ),
        ExerciseDefinition(
            id: "lat-pulldown",
            name: "Lat Pulldown",
            primary: [.back],
            secondary: [.biceps],
            met: 6.0,
            instructions: "Seated at the cable station, pull the bar to your upper chest while leaning back slightly, then control it back up."
        ),
        ExerciseDefinition(
            id: "deadlift",
            name: "Deadlift",
            primary: [.back],
            secondary: [.glutes, .hamstrings],
            met: 7.5,
            instructions: "Feet under the bar, hinge down with a flat back, grip, then drive through your heels to stand tall. Keep the bar close to your shins."
        ),
        ExerciseDefinition(
            id: "squat",
            name: "Squat",
            primary: [.quads],
            secondary: [.glutes],
            met: 7.0,
            instructions: "Bar on your upper back, feet shoulder-width. Sit back and down until hips are near knee height, then drive up through your whole foot."
        ),
        ExerciseDefinition(
            id: "leg-press",
            name: "Leg Press",
            primary: [.quads],
            secondary: [.glutes],
            met: 6.0,
            instructions: "Seated in the sled, place feet shoulder-width on the platform. Lower until knees reach about 90 degrees, then press without locking out."
        ),
        ExerciseDefinition(
            id: "romanian-deadlift",
            name: "Romanian Deadlift",
            primary: [.hamstrings],
            secondary: [.glutes],
            met: 6.5,
            instructions: "Standing with the bar at hip height, push your hips back with soft knees, sliding the bar down your thighs until you feel a deep hamstring stretch."
        ),
        ExerciseDefinition(
            id: "leg-curl",
            name: "Leg Curl",
            primary: [.hamstrings],
            secondary: [],
            met: 4.5,
            instructions: "Lying or seated in the machine, curl your heels toward your glutes against the pad, then lower slowly without swinging."
        ),
        ExerciseDefinition(
            id: "leg-extension",
            name: "Leg Extension",
            primary: [.quads],
            secondary: [],
            met: 4.5,
            instructions: "Seated in the machine with the pad on your shins, extend your knees to straighten your legs, pause, then lower with control."
        ),
        ExerciseDefinition(
            id: "bulgarian-split-squat",
            name: "Bulgarian Split Squat",
            primary: [.quads],
            secondary: [.glutes],
            met: 6.5,
            instructions: "Rear foot elevated on a bench, front foot planted. Lower straight down until your front thigh is parallel, then drive up."
        ),
        ExerciseDefinition(
            id: "calf-raise",
            name: "Calf Raise",
            primary: [.calves],
            secondary: [],
            met: 4.0,
            instructions: "Standing on a step with heels hanging off, rise onto your toes as high as possible, pause, then lower below step level."
        ),
        ExerciseDefinition(
            id: "hip-thrust",
            name: "Hip Thrust",
            primary: [.glutes],
            secondary: [.hamstrings],
            met: 6.0,
            instructions: "Upper back on a bench, bar across your hips. Drive your hips up until your body forms a straight line from shoulders to knees."
        ),
        ExerciseDefinition(
            id: "plank",
            name: "Plank",
            primary: [.abs],
            secondary: [],
            met: 3.5,
            instructions: "On forearms and toes, keep your body in one straight line. Brace your abs and glutes, and breathe steadily. Log time under 'reps' as seconds."
        ),
        ExerciseDefinition(
            id: "hanging-leg-raise",
            name: "Hanging Leg Raise",
            primary: [.abs],
            secondary: [],
            met: 5.0,
            instructions: "Hang from a bar without swinging. Raise your knees or straight legs until hips flex to 90 degrees, then lower slowly.",
            usesBodyweight: true
        ),
        ExerciseDefinition(
            id: "cable-fly",
            name: "Cable Fly",
            primary: [.chest],
            secondary: [.shoulders],
            met: 5.0,
            instructions: "Standing between cable stacks with a slight forward lean, bring the handles together in a wide arc in front of your chest."
        ),
        ExerciseDefinition(
            id: "face-pull",
            name: "Face Pull",
            primary: [.shoulders],
            secondary: [.back],
            met: 5.0,
            instructions: "At a cable station with a rope at face height, pull toward your forehead while rotating your knuckles back, squeezing your rear delts."
        ),
        ExerciseDefinition(
            id: "farmers-carry",
            name: "Farmer's Carry",
            primary: [.forearms],
            secondary: [.shoulders],
            met: 6.5,
            instructions: "Pick up heavy dumbbells, stand tall with shoulders back, and walk with control. Log distance in steps under 'reps'."
        ),
        ExerciseDefinition(
            id: "push-up",
            name: "Push-Up",
            primary: [.chest],
            secondary: [.triceps, .shoulders],
            met: 6.0,
            instructions: "Hands under shoulders, body in a straight line. Lower your chest to just above the floor, then press up without sagging.",
            usesBodyweight: true
        ),
        ExerciseDefinition(
            id: "goblet-squat",
            name: "Goblet Squat",
            primary: [.quads],
            secondary: [.glutes],
            met: 6.0,
            instructions: "Hold a dumbbell or kettlebell at your chest. Sit down between your heels with elbows inside your knees, then stand tall."
        ),
        ExerciseDefinition(
            id: "jump-squats",
            name: "Jump Squats",
            primary: [.quads, .glutes],
            secondary: [.calves],
            met: 8.0,
            instructions: "Drop into a quarter squat, then explode upward, landing softly back into the squat. Keep reps snappy and land quiet.",
            isCardio: true
        ),
        ExerciseDefinition(
            id: "treadmill-hiit",
            name: "Treadmill HIIT Intervals",
            primary: [.quads, .glutes, .calves],
            secondary: [.hamstrings],
            met: 10.0,
            instructions: "Alternate hard sprints (e.g. 30 seconds) with easy walking recovery (e.g. 45 seconds). Log total interval time in minutes.",
            isCardio: true
        ),
        ExerciseDefinition(
            id: "swimming-freestyle",
            name: "Swimming Freestyle",
            primary: [.back, .shoulders],
            secondary: [.chest, .triceps],
            met: 8.0,
            instructions: "Steady freestyle laps at a challenging pace. Log total swim time in minutes and distance in miles if you track it.",
            isCardio: true
        ),
        ExerciseDefinition(
            id: "steady-run",
            name: "Steady-State Run",
            primary: [.quads, .calves, .glutes],
            secondary: [.hamstrings],
            met: 9.0,
            instructions: "Easy-to-moderate continuous running you could hold a conversation through. Log minutes and miles.",
            isCardio: true
        ),
        ExerciseDefinition(
            id: "box-jumps",
            name: "Box Jumps",
            primary: [.quads, .glutes],
            secondary: [.calves],
            met: 8.0,
            instructions: "From an athletic stance, jump onto a sturdy box or platform, stand tall, then step down. Land soft, reset each rep.",
            isCardio: true
        ),
    ]

    static func definition(for id: String) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }
}
