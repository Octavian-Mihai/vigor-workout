import SwiftUI
import UIKit

// MARK: - Data Models

struct MovementCategory: Identifiable {
    var id: String { GuideVisuals.slug(key) }
    let key: String
    let title: String
    let intent: String
    let coachingNotes: String
    let exampleLifts: String
    let patternNames: [String]
}

struct MovementPattern: Identifiable {
    var id: String { GuideVisuals.slug(name) }
    let name: String
    let category: String
    let primaryMuscles: String
    let secondaryMuscles: String?
    let equipment: String
    let execution: String
    let tips: String
    let whyItMatters: String
    let exampleExercises: String
}

enum GuideTrainingSplit: String, CaseIterable, Identifiable {
    case push
    case pull
    case lowerBody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .lowerBody: return "Lower Body"
        }
    }

    var summary: String {
        switch self {
        case .push:
            return "Pressing and lockout work. Chest, delts, and triceps drive the load away from the torso; the core braces so the spine stays stacked."
        case .pull:
            return "Rows, pulldowns, and the upper-back wall. Lats, scapular retractors, and the arms that finish every pull."
        case .lowerBody:
            return "Squat, hinge, and single-leg tissue. Quads, posterior chain, hips, and the lower-leg muscles that support stance and gait."
        }
    }
}

struct GuideMuscleGroup: Identifiable {
    var id: String { GuideVisuals.slug(name) }
    let name: String
    let region: String
    let trainingSplit: GuideTrainingSplit
    let trainingRole: String
    let function: String
    let exampleExercises: String
    let movementPatterns: [String]
}

struct GuideTopic: Identifiable {
    var id: String { GuideVisuals.slug(name) }
    let name: String
    let summary: String
    let whyItMatters: String
    let examples: String
    let coachingNotes: String
    let relatedPatternNames: [String]
}

struct GuideChecklistSection: Identifiable {
    var id: String { GuideVisuals.slug(title) }
    let title: String
    let summary: String
    let itemNames: [String]
}

// MARK: - Data Store

final class AnatomyStore: ObservableObject {
    static let shared = AnatomyStore()

    @Published var coreCategories: [MovementCategory] = []
    @Published var movementPatterns: [MovementPattern] = []
    @Published var muscleGroups: [GuideMuscleGroup] = []
    @Published var extraTopics: [GuideTopic] = []
    @Published var checklistSections: [GuideChecklistSection] = []

    private init() {
        loadData()
    }

    func patterns(in category: MovementCategory) -> [MovementPattern] {
        category.patternNames.compactMap { name in
            movementPatterns.first { $0.name == name }
        }
    }

    func pattern(named name: String) -> MovementPattern? {
        movementPatterns.first { $0.name == name }
    }

    func topic(named name: String) -> GuideTopic? {
        extraTopics.first { $0.name == name }
    }

    func relatedMuscles(for pattern: MovementPattern) -> [GuideMuscleGroup] {
        muscleGroups.filter { $0.movementPatterns.contains(pattern.name) }
    }

    func muscles(in split: GuideTrainingSplit) -> [GuideMuscleGroup] {
        muscleGroups.filter { $0.trainingSplit == split }
    }

    func loadData() {
        coreCategories = [
            MovementCategory(
                key: "PUSHES",
                title: "Pushes",
                intent: "Move a load away from the torso. Vertical presses train overhead lockout and scapular upward rotation. Horizontal presses train the chest-dominant pattern of driving away from the sternum.",
                coachingNotes: "Brace the trunk so the lumbar spine does not take the load. On overhead work, keep ribs down. On benching, retract the scapulae and keep a stable upper back. Lock out with the triceps instead of shrugging the finish.",
                exampleLifts: "Overhead press, push press, bench press, incline press, dip, push-up",
                patternNames: ["Vertical Push", "Horizontal Push"]
            ),
            MovementCategory(
                key: "PULLS",
                title: "Pulls",
                intent: "Move a load toward the torso. Vertical pulls develop the lats through shoulder adduction and extension from overhead. Horizontal pulls train scapular retraction and the upper-back wall behind every press.",
                coachingNotes: "Start the rep by setting the shoulders down and back, then drive the elbows. Avoid yanking with the wrists. Hold a brief squeeze at the peak, then lower under control so the scapulae work through a full range.",
                exampleLifts: "Pull-up, chin-up, lat pulldown, barbell row, chest-supported row, Meadows row, face pull",
                patternNames: ["Vertical Pull", "Horizontal Pull"]
            ),
            MovementCategory(
                key: "SQUAT",
                title: "Squat",
                intent: "A knee-dominant sit-to-stand. Hips and knees flex together so the quads, glutes, and adductors share the work. This is how you stand up from a chair, a hole, or a heavy bar on the back.",
                coachingNotes: "Keep the trunk braced and the chest from collapsing. Depth to parallel or below if the hips and ankles allow it. Drive through midfoot, not the toes. Knees track over the feet instead of caving in.",
                exampleLifts: "Back squat, front squat, safety-bar squat, goblet squat, leg press",
                patternNames: ["Squat Pattern"]
            ),
            MovementCategory(
                key: "HINGE",
                title: "Hinge",
                intent: "A hip-dominant pattern with a relatively quiet knee. You push the hips back, load the hamstrings and glutes, then snap the hips through. Deadlifts, RDLs, and swings all live here.",
                coachingNotes: "Maintain a neutral spine from head to tail. Push the hips back until you feel a hamstring stretch, then stand by squeezing the glutes rather than yanking the bar with the back. The bar stays close to the legs.",
                exampleLifts: "Conventional deadlift, Romanian deadlift, good morning, kettlebell swing, hip thrust",
                patternNames: ["Hinge Pattern"]
            ),
            MovementCategory(
                key: "SINGLE-LEG",
                title: "Single-leg",
                intent: "Unilateral stance work. Split squats, lunges, step-ups, and single-leg hinges train each side on its own, plus the hip muscles that keep the pelvis level when you walk, run, or change direction.",
                coachingNotes: "Keep the pelvis level and the knee tracking over the toes. Use a stride long enough that the back hip can extend. Slow the eccentric if balance is the limiter. Treat these as strength, not cardio, unless that is the point.",
                exampleLifts: "Bulgarian split squat, reverse lunge, walking lunge, step-up, single-leg RDL",
                patternNames: ["Single-Leg Pattern"]
            ),
            MovementCategory(
                key: "CARRIES",
                title: "Loaded carries",
                intent: "Walk under load. Carries train gait, grip, packed shoulders, and anti-lateral flexion — the trunk resisting side-bend while the legs move. This is the sixth fundamental pattern alongside squat, hinge, push, pull, and lunge.",
                coachingNotes: "Stand tall, lock the ribcage over the pelvis, and keep the shoulders packed without shrugging. Breathe continuously. If the load pulls you sideways, that is the training effect — do not lean into it.",
                exampleLifts: "Farmer carry, suitcase carry, front-rack carry, waiter carry, yoke walk",
                patternNames: ["Loaded Carries"]
            )
        ]

        movementPatterns = [
            MovementPattern(
                name: "Vertical Push",
                category: "PUSHES",
                primaryMuscles: "Deltoids (anterior & lateral), Triceps, Upper Pectoralis",
                secondaryMuscles: "Trapezius, Serratus Anterior",
                equipment: "Dumbbells, Barbell, Kettlebell",
                execution: "Press weight overhead from shoulders to full lockout. Control descent.",
                tips: "Keep core braced, avoid lumbar hyperextension.",
                whyItMatters: "Overhead pressing is how you put load above your head with a stable shoulder. It trains upward rotation of the scapula, lockout strength through the triceps, and a trunk that can stay stacked instead of dumping into the low back.",
                exampleExercises: "Barbell overhead press, dumbbell shoulder press, push press, landmine press, pike push-up"
            ),
            MovementPattern(
                name: "Horizontal Push",
                category: "PUSHES",
                primaryMuscles: "Pectoralis Major, Triceps, Anterior Deltoid",
                secondaryMuscles: "Serratus Anterior, Coracobrachialis",
                equipment: "Barbell, Dumbbells, Push-up bars",
                execution: "Press weight away from chest. Lower to sternum or mid-chest.",
                tips: "Retract scapulae, maintain neutral spine.",
                whyItMatters: "The most common gym press. Horizontal pushing builds the pecs and triceps and teaches a stiff upper back so the shoulder can move on a stable base. Pair it with horizontal pulling so the scapulae are not stuck in a rounded position.",
                exampleExercises: "Barbell bench press, incline press, dumbbell press, dip, push-up"
            ),
            MovementPattern(
                name: "Vertical Pull",
                category: "PULLS",
                primaryMuscles: "Latissimus Dorsi, Teres Major, Biceps",
                secondaryMuscles: "Posterior Deltoids, Rhomboids",
                equipment: "Pull-up bar, Lat pulldown, Rings",
                execution: "Pull weight down from overhead to chest or chin level.",
                tips: "Depress scapulae, drive elbows down.",
                whyItMatters: "Vertical pulling develops lat width and hanging strength. Depressing the scapulae before the elbows bend keeps the shoulders from shrugging into the ears and lets the lats do the work they are built for.",
                exampleExercises: "Pull-up, chin-up, lat pulldown, kneeling straight-arm pulldown"
            ),
            MovementPattern(
                name: "Horizontal Pull",
                category: "PULLS",
                primaryMuscles: "Rhomboids, Middle Trapezius, Posterior Deltoids, Biceps",
                secondaryMuscles: "Latissimus Dorsi, Teres Major",
                equipment: "Barbell, Dumbbells, Cable row, Meadows row",
                execution: "Pull weight toward torso while retracting scapulae.",
                tips: "Hold contraction at peak, avoid rounding lower back.",
                whyItMatters: "Rows build the upper-back wall that every press needs. Scapular retraction and posterior-delt work keep the shoulder girdle balanced when pressing volume is high.",
                exampleExercises: "Barbell row, chest-supported row, Meadows row, cable row, face pull, seal row"
            ),
            MovementPattern(
                name: "Squat Pattern",
                category: "SQUAT",
                primaryMuscles: "Quadriceps, Gluteus Maximus, Adductors",
                secondaryMuscles: "Erectors, Core, Calves",
                equipment: "Barbell, Safety Squat Bar, Goblet Dumbbell",
                execution: "Descend by pushing hips back and knees forward. Keep chest up.",
                tips: "Depth to parallel or below, drive through midfoot.",
                whyItMatters: "Squatting is the loaded sit-to-stand. It is the main knee-dominant strength pattern: quads, glutes, and adductors sharing a deep knee bend under a braced trunk.",
                exampleExercises: "Back squat, front squat, safety-bar squat, goblet squat, Bulgarian split squat (knee-dominant)"
            ),
            MovementPattern(
                name: "Hinge Pattern",
                category: "HINGE",
                primaryMuscles: "Hamstrings, Gluteus Maximus, Erectors",
                secondaryMuscles: "Adductors, Core",
                equipment: "Barbell, Dumbbells, Kettlebell",
                execution: "Hinge at hips with minimal knee bend, back straight.",
                tips: "Push hips back, maintain neutral spine, feel hamstring stretch.",
                whyItMatters: "The hinge is how you pick things up without turning it into a squat. Hip extension through the hamstrings and glutes is the posterior-chain counterpart to knee-dominant squatting.",
                exampleExercises: "Romanian deadlift, conventional deadlift, good morning, kettlebell swing, hip thrust"
            ),
            MovementPattern(
                name: "Single-Leg Pattern",
                category: "SINGLE-LEG",
                primaryMuscles: "Gluteus Medius, Quadriceps, Hamstrings, Calves",
                secondaryMuscles: "Core, Adductors",
                equipment: "Dumbbells, Kettlebell, TRX",
                execution: "Lunge, step-up, or single-leg deadlift. Maintain stability.",
                tips: "Knee tracking over toes, pelvis level.",
                whyItMatters: "Life and sport happen one leg at a time. Unilateral work exposes left-right gaps, trains pelvic control, and loads the lateral hip that bilateral squats can hide.",
                exampleExercises: "Walking lunge, reverse lunge, Bulgarian split squat, step-up, single-leg RDL"
            ),
            MovementPattern(
                name: "Anti-Rotation & Anti-Lateral",
                category: "ROTATIONAL CORE",
                primaryMuscles: "Obliques, Transverse Abdominis, Erector Spinae",
                secondaryMuscles: "Glutes, Lats",
                equipment: "Cable, Landmine, Kettlebell",
                execution: "Resist rotation or side-bending while moving load.",
                tips: "Brace core, keep ribs down, slow controlled reps.",
                whyItMatters: "Most hard lifting asks the trunk to be a cylinder, not a cruncher. Anti-rotation and anti-lateral work teach the obliques to brake unwanted twist and side-bend so the hips and shoulders can produce force.",
                exampleExercises: "Pallof press, landmine anti-rotation, suitcase hold, Copenhagen plank, side plank"
            ),
            MovementPattern(
                name: "Rotational Acceleration",
                category: "ROTATIONAL CORE",
                primaryMuscles: "Obliques, Rectus Abdominis, Erector Spinae",
                secondaryMuscles: "Hip flexors, Lats",
                equipment: "Cable, Landmine, Med Ball",
                execution: "Explosively rotate torso from a stable stance.",
                tips: "Generate power from hips, rotate as a unit.",
                whyItMatters: "Sport often needs rotation on purpose — throws, swings, cuts. Train it as power from the hips through a stiff trunk, not as a twist isolated to the lumbar spine.",
                exampleExercises: "Landmine rotation, cable woodchop, med-ball rotational throw, rotational slam"
            ),
            MovementPattern(
                name: "Loaded Carries",
                category: "CARRIES",
                primaryMuscles: "Core, Trapezius, Forearms, Glutes",
                secondaryMuscles: "Erectors, Quadratus Lumborum",
                equipment: "Kettlebells, Dumbbells, Suitcase handles",
                execution: "Walk with load in one or both hands, maintain upright posture.",
                tips: "Keep shoulders back, engage lats, breathe continuously.",
                whyItMatters: "Carries are strength that has to travel. Grip, packed shoulders, and a trunk that resists side-bend while the legs walk — useful on its own and as a transfer to deadlifts, rows, and sport.",
                exampleExercises: "Farmer carry, suitcase carry, front-rack carry, waiter carry"
            ),
            MovementPattern(
                name: "Power / Triple Extension",
                category: "ATHLETIC TRANSFERS",
                primaryMuscles: "Glutes, Quadriceps, Calves, Erector Spinae",
                secondaryMuscles: "Deltoids, Trapezius",
                equipment: "Barbell, Kettlebell, Med Ball",
                execution: "Explosive extension of hips, knees, and ankles against load.",
                tips: "Start with hips high, accelerate through mid-thigh.",
                whyItMatters: "Strength that cannot be expressed quickly is only half the quality. Triple extension trains rate of force: hips, knees, and ankles opening together, the same pattern as a jump, a sprint first step, or a clean.",
                exampleExercises: "Jump shrug, kettlebell swing, push press, broad jump, med-ball slam"
            ),
            MovementPattern(
                name: "Deceleration / Catching",
                category: "ATHLETIC TRANSFERS",
                primaryMuscles: "Anterior Deltoids, Pectorals, Core, Quads",
                secondaryMuscles: "Biceps, Forearms",
                equipment: "Med Ball, Dumbbells (eccentric)",
                execution: "Absorb impact by yielding through hips and chest.",
                tips: "Stay braced, cushion force with soft elbows and knees.",
                whyItMatters: "Producing force is only half of athleticism. Catching and deceleration train the other half: yielding under control so landings, changes of direction, and eccentric presses do not dump into the joints.",
                exampleExercises: "Med-ball catch, snap-down, tempo eccentric press, drop-catch landing"
            )
        ]

        muscleGroups = [
            GuideMuscleGroup(
                name: "Chest (Pectorals)",
                region: "Upper body",
                trainingSplit: .push,
                trainingRole: "Prime mover on horizontal push; upper fibers assist incline and some overhead work.",
                function: "Shoulder horizontal adduction, flexion, internal rotation.",
                exampleExercises: "Bench Press, Incline Press, DB Fly, Decline Fly",
                movementPatterns: ["Horizontal Push", "Deceleration / Catching"]
            ),
            GuideMuscleGroup(
                name: "Anterior Delts",
                region: "Upper body",
                trainingSplit: .push,
                trainingRole: "Prime mover on overhead pressing and the front-of-shoulder contribution to incline and bench work.",
                function: "Shoulder flexion. Front head of the deltoid on vertical and horizontal pushes.",
                exampleExercises: "OHP, Incline Press",
                movementPatterns: ["Vertical Push", "Horizontal Push"]
            ),
            GuideMuscleGroup(
                name: "Lateral Delts",
                region: "Upper body",
                trainingSplit: .push,
                trainingRole: "Shoulder abduction and the cap of the deltoid on overhead presses and raises.",
                function: "Shoulder abduction. Lateral head that sets the arm path on vertical push.",
                exampleExercises: "Lateral Raise, DB Shoulder Press",
                movementPatterns: ["Vertical Push"]
            ),
            GuideMuscleGroup(
                name: "Triceps",
                region: "Arms",
                trainingSplit: .push,
                trainingRole: "Elbow extensor and press lockout. Shows up on every vertical and horizontal push, then again on isolation extensions.",
                function: "Elbow extension. Long head extends shoulder, lateral head stabilizes.",
                exampleExercises: "Pushdown, Skullcrusher, Diamond Push-up, Overhead Extension",
                movementPatterns: ["Vertical Push", "Horizontal Push"]
            ),
            GuideMuscleGroup(
                name: "Core & Abs",
                region: "Trunk",
                trainingSplit: .push,
                trainingRole: "Brace, anti-motion, and some flexion/rotation. Treat it as a cylinder on compounds, then add anti-series and flexion work as needed.",
                function: "Spinal flexion, rotation, anti-extension, anti-rotation.",
                exampleExercises: "Cable Crunch, Dragon Fly, Russian Twist, Plank",
                movementPatterns: ["Anti-Rotation & Anti-Lateral", "Rotational Acceleration", "Loaded Carries"]
            ),
            GuideMuscleGroup(
                name: "Lats",
                region: "Upper body",
                trainingSplit: .pull,
                trainingRole: "Prime mover on vertical and horizontal pulls. Width and shoulder extension from overhead and from a row.",
                function: "Shoulder extension and adduction. Depresses the scapula on vertical pulls.",
                exampleExercises: "Pull-up, Lat Pulldown, Meadows Row",
                movementPatterns: ["Vertical Pull", "Horizontal Pull"]
            ),
            GuideMuscleGroup(
                name: "Rhomboids",
                region: "Upper body",
                trainingSplit: .pull,
                trainingRole: "Scapular retractors that build the upper-back wall behind every press.",
                function: "Scapular retraction. Pull the shoulder blades toward the spine.",
                exampleExercises: "Barbell Row, Seal Row, Face Pull",
                movementPatterns: ["Horizontal Pull"]
            ),
            GuideMuscleGroup(
                name: "Traps",
                region: "Upper body",
                trainingSplit: .pull,
                trainingRole: "Postural wall on rows and the packed-shoulder work of carries.",
                function: "Scapular retraction, elevation, and upward rotation. Middle fibers retract; upper fibers support loaded carries.",
                exampleExercises: "Face Pull, Loaded Carry, Shrug-style work from pulls",
                movementPatterns: ["Horizontal Pull", "Loaded Carries"]
            ),
            GuideMuscleGroup(
                name: "Erectors",
                region: "Trunk",
                trainingSplit: .pull,
                trainingRole: "Spinal extensors that keep the trunk rigid on hinges and squats.",
                function: "Spinal extension and isometric bracing under axial load.",
                exampleExercises: "Deadlift, RDL, Back Squat",
                movementPatterns: ["Hinge Pattern", "Squat Pattern"]
            ),
            GuideMuscleGroup(
                name: "Posterior Delts",
                region: "Upper body",
                trainingSplit: .pull,
                trainingRole: "The rear head that balances pressing volume with horizontal pulling.",
                function: "Shoulder extension and external rotation. Posterior head of the deltoid.",
                exampleExercises: "Rear Delt Fly, Face Pull",
                movementPatterns: ["Horizontal Pull"]
            ),
            GuideMuscleGroup(
                name: "Biceps",
                region: "Arms",
                trainingSplit: .pull,
                trainingRole: "Elbow flexor and pull accessory. Direct curls plus indirect work on every vertical and horizontal pull.",
                function: "Elbow flexion, supination. Long head contributes to shoulder flexion.",
                exampleExercises: "BB Curl, Hammer Curl, Preacher Curl, Reverse Curl",
                movementPatterns: ["Horizontal Pull", "Vertical Pull"]
            ),
            GuideMuscleGroup(
                name: "Forearms & Grip",
                region: "Arms",
                trainingSplit: .pull,
                trainingRole: "Limiters on pulls, hinges, and carries. Train grip so the hands are not the first thing to quit.",
                function: "Wrist flexion, extension, pronation, supination.",
                exampleExercises: "Wrist Curl, Reverse Curl, Pronation/Supination Twists",
                movementPatterns: ["Loaded Carries", "Vertical Pull", "Horizontal Pull"]
            ),
            GuideMuscleGroup(
                name: "Quadriceps",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Knee extension on squats, lunges, and jumps. The main knee-dominant engine.",
                function: "Knee extension, hip flexion.",
                exampleExercises: "Squat, Leg Extension, Bulgarian Split Squat, Goblet Squat",
                movementPatterns: ["Squat Pattern", "Power / Triple Extension"]
            ),
            GuideMuscleGroup(
                name: "Hamstrings",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Hip extension on hinges plus knee flexion on curls. Pair with quads so the posterior chain is not an afterthought.",
                function: "Knee flexion, hip extension.",
                exampleExercises: "Nordic Curl, RDL, Glute Ham Raise, Leg Curl",
                movementPatterns: ["Hinge Pattern", "Single-Leg Pattern"]
            ),
            GuideMuscleGroup(
                name: "Glutes",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Hip extension, abduction, and the finish of squats, hinges, and jumps.",
                function: "Hip extension, abduction, external rotation.",
                exampleExercises: "Step-ups, Lunges, Hip Thrust, RDL",
                movementPatterns: ["Squat Pattern", "Hinge Pattern", "Power / Triple Extension"]
            ),
            GuideMuscleGroup(
                name: "Calves",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Ankle plantarflexion and elastic stiffness for gait, jumps, and single-leg work.",
                function: "Plantarflexion (gastrocnemius and soleus).",
                exampleExercises: "Standing / Seated Calf Raise",
                movementPatterns: ["Single-Leg Pattern", "Power / Triple Extension"]
            ),
            GuideMuscleGroup(
                name: "Tibialis",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Ankle dorsiflexion. The front-of-shin counterpart to the calves.",
                function: "Dorsiflexion (tibialis anterior).",
                exampleExercises: "Tibialis Raise",
                movementPatterns: ["Single-Leg Pattern"]
            ),
            GuideMuscleGroup(
                name: "Adductors",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Share squat depth and stance control. Pelvic stability on squats and lunges.",
                function: "Adduction (pull the leg in) and pelvic stability.",
                exampleExercises: "Copenhagen Adductor, Lateral Lunge",
                movementPatterns: ["Squat Pattern", "Single-Leg Pattern"]
            ),
            GuideMuscleGroup(
                name: "Abductors",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Keep the pelvis level on lunges and single-leg work.",
                function: "Abduction (push the leg out) and pelvic stability.",
                exampleExercises: "Cable Side Extension, side-lying abduction",
                movementPatterns: ["Single-Leg Pattern", "Anti-Rotation & Anti-Lateral"]
            ),
            GuideMuscleGroup(
                name: "Hip Flexors",
                region: "Lower body",
                trainingSplit: .lowerBody,
                trainingRole: "Swing-leg and knee-drive muscles. They stabilize the pelvis and show up in sprinting, hanging leg raises, and split-stance work.",
                function: "Hip flexion, stabilizes pelvis.",
                exampleExercises: "Reverse Squat, Hanging Leg Raise, Reverse Lunge",
                movementPatterns: ["Single-Leg Pattern", "Power / Triple Extension"]
            )
        ]

        extraTopics = [
            GuideTopic(
                name: "Anti-Extension",
                summary: "Resist lumbar extension while the arms or legs move.",
                whyItMatters: "Squats, deadlifts, and overhead presses all ask the trunk not to dump into a backbend. Anti-extension trains that brace so the hips and shoulders can load instead of the lumbar spine taking the motion.",
                examples: "Dead bug, ab wheel / rollout, hollow hold, plank with reach, stability-ball roll-out",
                coachingNotes: "Ribs down, pelvis tucked just enough to keep a long low back. If the lumbar folds into extension, shorten the lever or slow the rep.",
                relatedPatternNames: ["Anti-Rotation & Anti-Lateral", "Loaded Carries", "Vertical Push"]
            ),
            GuideTopic(
                name: "Anti-Rotation",
                summary: "Resist twist through the trunk while a load tries to turn you.",
                whyItMatters: "Rows, carries, and single-arm presses create rotational torque. The obliques’ job on those lifts is to brake that twist so force stays in the intended plane.",
                examples: "Pallof press, landmine anti-rotation, single-arm farmer hold, cable press-out",
                coachingNotes: "Lock the ribcage to the pelvis and move the arms, not the waist. Slow the eccentric. Pair with rotational acceleration if the sport actually needs to create twist.",
                relatedPatternNames: ["Anti-Rotation & Anti-Lateral", "Loaded Carries"]
            ),
            GuideTopic(
                name: "Anti-Lateral Flexion",
                summary: "Resist side-bend while standing, walking, or holding offset load.",
                whyItMatters: "A suitcase carry or offset farmer walk is a moving side plank. The quadratus lumborum and obliques keep the ribcage stacked so the spine does not collapse toward the load.",
                examples: "Suitcase carry, side plank, offset farmer walk, single-arm overhead waiter's walk",
                coachingNotes: "Stand tall. Do not lean into the weight or away from it. Breathe without letting the ribs flare on the loaded side.",
                relatedPatternNames: ["Anti-Rotation & Anti-Lateral", "Loaded Carries"]
            ),
            GuideTopic(
                name: "Rotation (Acceleration)",
                summary: "Create rotation on purpose from the hips through a stiff trunk.",
                whyItMatters: "Throws, swings, and cuts need rotational power. Train it as a unit — feet, hips, then torso — rather than grinding the lumbar spine in isolation.",
                examples: "Med-ball rotational throw, landmine rotation, cable woodchop, rotational slam",
                coachingNotes: "Load the back hip, then unwind. Keep the chest and pelvis turning together. Use anti-rotation work as the brake that makes this acceleration useful.",
                relatedPatternNames: ["Rotational Acceleration"]
            ),
            GuideTopic(
                name: "Sprinting",
                summary: "Max-velocity locomotion: stiffness, hip extension, and front-side mechanics.",
                whyItMatters: "Sprinting is the high-speed expression of hinge, single-leg, and triple-extension qualities. Short accelerations also train intent that heavy barbell work does not.",
                examples: "Hill sprints, 10–30 m accelerations, wickets, sled marches into a sprint",
                coachingNotes: "Treat these as quality, not volume. Full recoveries. Build the hinge, single-leg, and calf stiffness in the weight room, then express it on the run.",
                relatedPatternNames: ["Power / Triple Extension", "Single-Leg Pattern", "Hinge Pattern"]
            ),
            GuideTopic(
                name: "Rotational Throwing",
                summary: "Hip-to-shoulder power into a throw or toss.",
                whyItMatters: "A rotational throw is rotational acceleration with an implement leaving the hands. It is a clean way to train power without loading the spine axially.",
                examples: "Med-ball rotational scoop toss, shot-put style throw, rotational slam, landmine punch",
                coachingNotes: "Push the ground away, then let the arms follow. Catch or reset with a brace so the deceleration half of the throw is trained too.",
                relatedPatternNames: ["Rotational Acceleration", "Deceleration / Catching", "Power / Triple Extension"]
            ),
            GuideTopic(
                name: "Shoulder",
                summary: "Joint-prep for a shoulder that presses, pulls, and hangs.",
                whyItMatters: "The glenohumeral joint lives on the scapula. Healthy pressing usually means the upper back can retract and the scapula can upwardly rotate, not just that the delts are strong.",
                examples: "Face pull, Y/T/W raise, Cuban rotation, controlled hang, landmine press",
                coachingNotes: "Use light, crisp work around the heavier press and pull days. Train rear delts and upward rotation as seriously as the bench.",
                relatedPatternNames: ["Vertical Push", "Horizontal Pull", "Vertical Pull"]
            ),
            GuideTopic(
                name: "Hip",
                summary: "Joint-prep for a hip that squats, hinges, and lunges.",
                whyItMatters: "Squat depth, hinge range, and split-stance stability all start at the hip. Capsule mobility plus glute and adductor strength keep the knee from doing the hip’s job.",
                examples: "90/90 sit, hip airplane, Copenhagen adductor, side-lying abduction, deep goblet squat hold",
                coachingNotes: "Own the positions you load. If a squat or hinge feels stuck, check hip rotation and adductor length before adding more bar weight.",
                relatedPatternNames: ["Squat Pattern", "Hinge Pattern", "Single-Leg Pattern"]
            ),
            GuideTopic(
                name: "Knee",
                summary: "Joint-prep for a knee that tracks well under load.",
                whyItMatters: "The knee is a hinge that wants the hip and ankle to share the motion. Quad and hamstring strength plus tracking over the midfoot keep split squats and jumps from becoming a grind.",
                examples: "Terminal knee extension, Spanish squat, reverse Nordic, split-squat isometric, step-down",
                coachingNotes: "Train the ranges you use. Slow eccentrics on split squats and controlled step-downs do more for knee-friendly strength than random foam rolling.",
                relatedPatternNames: ["Squat Pattern", "Single-Leg Pattern"]
            ),
            GuideTopic(
                name: "Elbow/Wrist",
                summary: "Joint-prep for the arms that grip, curl, and lock out.",
                whyItMatters: "Elbows and wrists take the last bit of every press, pull, and carry. Grip variety and controlled wrist work keep the small links from limiting the big patterns.",
                examples: "Wrist curl, reverse curl, hammer curl, pronation/supination, loaded hang",
                coachingNotes: "Change grip (pronated, supinated, neutral) across the week. If pressing bothers the elbow, check lockout control and triceps capacity, not just the joint.",
                relatedPatternNames: ["Vertical Push", "Horizontal Pull", "Loaded Carries"]
            ),
            GuideTopic(
                name: "Spine",
                summary: "Joint-prep for a trunk that braces, then moves on purpose.",
                whyItMatters: "Axial loading (squat, hinge, carry, overhead) asks the spine to be stiff. Rotation and locomotion ask it to move. Training both — brace and controlled motion — is the complete-human approach, not one or the other.",
                examples: "Bird dog, dead bug, McGill curl-up, suitcase carry, controlled cat-camel as a reset — not as the workout",
                coachingNotes: "Brace on the heavy compounds. Use anti-series and a little flexion/rotation away from max loading. Do not chase end-range spinal motion under fatigue.",
                relatedPatternNames: ["Hinge Pattern", "Squat Pattern", "Anti-Rotation & Anti-Lateral", "Loaded Carries"]
            )
        ]

        checklistSections = [
            GuideChecklistSection(
                title: "The Big 7 primary strength patterns",
                summary: "If a week of training covers these seven, the main strength patterns are accounted for. Pushes and pulls are split by plane; legs are split into squat, hinge, and single-leg.",
                itemNames: [
                    "Vertical Push",
                    "Horizontal Push",
                    "Vertical Pull",
                    "Horizontal Pull",
                    "Squat Pattern",
                    "Hinge Pattern",
                    "Single-Leg Pattern"
                ]
            ),
            GuideChecklistSection(
                title: "Core stability (anti-series)",
                summary: "The trunk as a brake. Anti-extension, anti-rotation, and anti-lateral flexion keep compounds honest. Add rotational acceleration when you need to create twist, not just resist it.",
                itemNames: [
                    "Anti-Extension",
                    "Anti-Rotation",
                    "Anti-Lateral Flexion",
                    "Rotation (Acceleration)"
                ]
            ),
            GuideChecklistSection(
                title: "Athletic & neuromuscular",
                summary: "Qualities that barbell strength does not automatically give you: rate of force, catching, locomotion, and throwing.",
                itemNames: [
                    "Power / Triple Extension",
                    "Loaded Carries",
                    "Deceleration / Catching",
                    "Sprinting",
                    "Rotational Throwing"
                ]
            ),
            GuideChecklistSection(
                title: "Prehab 360: Joint health",
                summary: "Light, regular work around the joints that take the brunt of hard training. This is preparation and capacity, not a diagnosis or rehab plan.",
                itemNames: ["Shoulder", "Hip", "Knee", "Elbow/Wrist", "Spine"]
            )
        ]
    }
}

// MARK: - Learn destinations

struct KeyMuscleGroupsView: View {
    @ObservedObject private var store = AnatomyStore.shared

    var body: some View {
        ArticleScreen(title: "Key muscle groups") {
            ArticleCard(
                title: "Train the tissue, not just the lift",
                bodyText: "These are the muscle groups the guide tracks — function, training role, example lifts, and the movement patterns they belong to. Grouped by a push / pull / lower-body split. Tap a muscle for the full note."
            )

            ForEach(GuideTrainingSplit.allCases) { split in
                let muscles = store.muscles(in: split)
                VStack(alignment: .leading, spacing: 12) {
                    Text(split.title)
                        .font(.headline)
                    Text(split.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(muscles) { muscle in
                        Divider()
                        GuideRowLink {
                            MuscleDetailView(muscle: muscle, store: store)
                        } label: {
                            GuideNavRow(
                                title: muscle.name,
                                subtitle: "\(muscle.region) · \(muscle.exampleExercises)"
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .opaqueCard()
            }
        }
    }
}

struct MoreStrengthPatternsView: View {
    @ObservedObject private var store = AnatomyStore.shared
    @Environment(AppTheme.self) private var theme

    var body: some View {
        ArticleScreen(title: "Strength patterns") {
            ForEach(store.checklistSections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.headline)
                    Text(section.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(section.itemNames.enumerated()), id: \.offset) { _, name in
                        Divider()
                        checklistRow(name)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .opaqueCard()
            }
        }
    }

    @ViewBuilder
    private func checklistRow(_ name: String) -> some View {
        let symbol = GuideVisuals.symbol(forChecklistItem: name)
        if let pattern = store.pattern(named: name) {
            GuideRowLink {
                MovementDetailView(pattern: pattern, store: store)
            } label: {
                GuideNavRow(
                    title: pattern.name,
                    subtitle: pattern.whyItMatters,
                    symbolName: symbol
                )
            }
        } else if let topic = store.topic(named: name) {
            GuideRowLink {
                TopicDetailView(topic: topic, store: store)
            } label: {
                GuideNavRow(
                    title: topic.name,
                    subtitle: topic.summary,
                    symbolName: symbol
                )
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Detail Views

struct MovementDetailView: View {
    let pattern: MovementPattern
    @ObservedObject var store: AnatomyStore
    @Environment(AppTheme.self) private var theme

    private var relatedMuscles: [GuideMuscleGroup] {
        store.relatedMuscles(for: pattern)
    }

    var body: some View {
        ArticleScreen(title: pattern.name) {
            GuideArticleCard {
                GuideEyebrow(
                    symbolName: GuideVisuals.symbol(for: pattern.category),
                    text: GuideVisuals.title(for: pattern.category),
                    accent: theme.accent
                )

                GuideArticleSection(title: "What it is", bodyText: pattern.execution)
                GuideArticleSection(title: "Why it matters", bodyText: pattern.whyItMatters)
                GuideArticleSection(title: "Example exercises", bodyText: pattern.exampleExercises)
                GuideArticleSection(title: "Primary muscles", bodyText: pattern.primaryMuscles)

                if let secondary = pattern.secondaryMuscles {
                    GuideArticleSection(title: "Secondary muscles", bodyText: secondary)
                }

                GuideArticleSection(title: "Equipment", bodyText: pattern.equipment)
                GuideArticleSection(title: "Coaching notes", bodyText: pattern.tips)
            }

            GuideRelatedLinksCard(muscles: relatedMuscles, store: store)
        }
    }
}

struct MuscleDetailView: View {
    let muscle: GuideMuscleGroup
    @ObservedObject var store: AnatomyStore
    @Environment(AppTheme.self) private var theme

    private var relatedPatterns: [MovementPattern] {
        store.movementPatterns.filter { muscle.movementPatterns.contains($0.name) }
    }

    var body: some View {
        ArticleScreen(title: muscle.name) {
            GuideArticleCard {
                ExercisePhotoView(
                    assetName: "guide-\(muscle.id)",
                    caption: muscle.name,
                    symbolName: "figure.strengthtraining.traditional"
                )

                GuideEyebrow(text: muscle.region, accent: theme.accent)

                GuideArticleSection(title: "Training role", bodyText: muscle.trainingRole)
                GuideArticleSection(title: "Function", bodyText: muscle.function)
                GuideArticleSection(title: "Example exercises", bodyText: muscle.exampleExercises)
            }

            GuideRelatedLinksCard(patterns: relatedPatterns, store: store)
        }
    }
}

struct TopicDetailView: View {
    let topic: GuideTopic
    @ObservedObject var store: AnatomyStore

    private var relatedPatterns: [MovementPattern] {
        topic.relatedPatternNames.compactMap { store.pattern(named: $0) }
    }

    var body: some View {
        ArticleScreen(title: topic.name) {
            GuideArticleCard {
                GuideArticleSection(title: "What it is", bodyText: topic.summary)
                GuideArticleSection(title: "Why it matters", bodyText: topic.whyItMatters)
                GuideArticleSection(title: "Example exercises", bodyText: topic.examples)
                GuideArticleSection(title: "Coaching notes", bodyText: topic.coachingNotes)
            }

            GuideRelatedLinksCard(patterns: relatedPatterns, store: store)
        }
    }
}

// MARK: - Shared chrome

private struct GuideRowLink<Destination: View, Label: View>: View {
    private let destination: Destination
    private let label: Label

    init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.destination = destination()
        self.label = label()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GuideRelatedLinksCard: View {
    var muscles: [GuideMuscleGroup] = []
    var patterns: [MovementPattern] = []
    var muscleSectionTitle = "Related muscle groups"
    var patternSectionTitle = "Related movement patterns"
    var muscleSubtitle: (GuideMuscleGroup) -> String = { $0.function }
    var patternSubtitle: (MovementPattern) -> String = { GuideVisuals.title(for: $0.category) }
    let store: AnatomyStore

    private var showsMuscles: Bool { !muscles.isEmpty }
    private var showsPatterns: Bool { !patterns.isEmpty }

    var body: some View {
        if showsMuscles || showsPatterns {
            VStack(alignment: .leading, spacing: 16) {
                if showsMuscles && showsPatterns {
                    Text("Related")
                        .font(.headline)
                }

                if showsMuscles {
                    GuideRelatedSection(
                        title: showsMuscles && showsPatterns ? "Muscle groups" : muscleSectionTitle
                    ) {
                        ForEach(Array(muscles.enumerated()), id: \.element.id) { index, muscle in
                            if index > 0 { Divider() }
                            GuideRowLink {
                                MuscleDetailView(muscle: muscle, store: store)
                            } label: {
                                GuideNavRow(title: muscle.name, subtitle: muscleSubtitle(muscle))
                            }
                        }
                    }
                }

                if showsPatterns {
                    GuideRelatedSection(
                        title: showsMuscles && showsPatterns ? "Movement patterns" : patternSectionTitle
                    ) {
                        ForEach(Array(patterns.enumerated()), id: \.element.id) { index, pattern in
                            if index > 0 { Divider() }
                            GuideRowLink {
                                MovementDetailView(pattern: pattern, store: store)
                            } label: {
                                GuideNavRow(title: pattern.name, subtitle: patternSubtitle(pattern))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .opaqueCard()
        }
    }
}

private struct GuideArticleCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opaqueCard()
    }
}

private struct GuideArticleSection: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GuideEyebrow: View {
    var symbolName: String? = nil
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.semibold))
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(accent)
    }
}

private struct GuideRelatedSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GuideNavRow: View {
    let title: String
    var subtitle: String? = nil
    var symbolName: String? = nil
    @Environment(AppTheme.self) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private enum GuideVisuals {
    static func slug(_ raw: String) -> String {
        let mapped = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    static func title(for category: String) -> String {
        switch category {
        case "PUSHES": return "Pushes"
        case "PULLS": return "Pulls"
        case "SQUAT": return "Squat"
        case "HINGE": return "Hinge"
        case "SINGLE-LEG": return "Single-leg"
        case "CARRIES": return "Loaded carries"
        case "ROTATIONAL CORE": return "Rotational core"
        case "ATHLETIC TRANSFERS": return "Athletic transfers"
        case "LEGS": return "Legs"
        default: return category.localizedCapitalized
        }
    }

    static func symbol(for category: String) -> String {
        switch category {
        case "PUSHES": return "arrow.up.circle.fill"
        case "PULLS": return "arrow.down.circle.fill"
        case "SQUAT", "LEGS": return "figure.strengthtraining.traditional"
        case "HINGE": return "arrow.down.right.circle.fill"
        case "SINGLE-LEG": return "figure.walk"
        case "CARRIES": return "bag.fill"
        case "ROTATIONAL CORE": return "arrow.triangle.2.circlepath"
        case "ATHLETIC TRANSFERS": return "bolt.fill"
        default: return "circle.fill"
        }
    }

    static func symbol(forChecklistItem name: String) -> String {
        switch name {
        case "Vertical Push": return "arrow.up.circle.fill"
        case "Horizontal Push": return "arrow.right.circle.fill"
        case "Vertical Pull": return "arrow.down.circle.fill"
        case "Horizontal Pull": return "arrow.left.circle.fill"
        case "Squat Pattern": return "figure.strengthtraining.traditional"
        case "Hinge Pattern": return "arrow.down.right.circle.fill"
        case "Single-Leg Pattern": return "figure.walk"
        case "Anti-Extension": return "arrow.up.and.down.circle.fill"
        case "Anti-Rotation": return "arrow.triangle.2.circlepath"
        case "Anti-Lateral Flexion": return "arrow.left.and.right.circle.fill"
        case "Rotation (Acceleration)": return "rotate.3d.fill"
        case "Power / Triple Extension": return "bolt.fill"
        case "Loaded Carries": return "bag.fill"
        case "Deceleration / Catching": return "hand.raised.fill"
        case "Sprinting": return "figure.run"
        case "Rotational Throwing": return "baseball.fill"
        case "Shoulder": return "figure.arms.open"
        case "Hip": return "figure.stand"
        case "Knee": return "figure.walk.motion"
        case "Elbow/Wrist": return "hand.raised.fill"
        case "Spine": return "line.3.horizontal"
        default: return "circle.fill"
        }
    }
}
