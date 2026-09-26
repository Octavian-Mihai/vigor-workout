import Foundation

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest = "Chest"
    case anteriorDelts = "Anterior Delts"
    case lateralDelts = "Lateral Delts"
    case triceps = "Triceps"
    case coreAndAbs = "Core & Abs"
    case lats = "Lats"
    case rhomboids = "Rhomboids"
    case traps = "Traps"
    case erectors = "Erectors"
    case posteriorDelts = "Posterior Delts"
    case biceps = "Biceps"
    case forearmsAndGrip = "Forearms & Grip"
    case quadriceps = "Quadriceps"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case tibialis = "Tibialis"
    case adductors = "Adductors"
    case abductors = "Abductors"
    case hipFlexors = "Hip Flexors"

    var id: String { rawValue }

    var compactName: String {
        switch self {
        case .anteriorDelts: return "Ant. Delts"
        case .lateralDelts: return "Lat. Delts"
        case .posteriorDelts: return "Post. Delts"
        case .coreAndAbs: return "Core"
        case .forearmsAndGrip: return "Forearms"
        case .hipFlexors: return "Hip Flex."
        default: return rawValue
        }
    }

    var region: String {
        switch self {
        case .chest, .lats, .rhomboids, .traps, .anteriorDelts, .lateralDelts, .posteriorDelts:
            return "Upper body"
        case .biceps, .triceps, .forearmsAndGrip:
            return "Arms"
        case .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors, .tibialis, .hipFlexors:
            return "Lower body"
        case .coreAndAbs, .erectors:
            return "Trunk"
        }
    }

    /// Maps current catalog names and legacy import strings onto the 20-muscle list.
    static func parse(_ name: String) -> MuscleGroup? {
        if let exact = Self(rawValue: name) { return exact }
        switch name {
        case "Front Delts": return .anteriorDelts
        case "Side Delts": return .lateralDelts
        case "Rear Delts": return .posteriorDelts
        case "Core": return .coreAndAbs
        case "Upper Back": return .rhomboids
        case "Lower Back": return .erectors
        case "Forearms": return .forearmsAndGrip
        case "Quads": return .quadriceps
        default: return nil
        }
    }
}

enum ExerciseCategory: String, CaseIterable, Identifiable {
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case explosive = "Explosive"
    case core = "Core"

    var id: String { rawValue }
}

/// In-category picker/catalog order. `allCases` is the sort key; unused cases in a
/// category are skipped. Hinge covers Legs deadlifts and posterior-chain work.
enum ExerciseMovementPattern: String, CaseIterable, Identifiable {
    case verticalPull = "Vertical Pull"
    case horizontalPull = "Horizontal Pull"
    case squat = "Squat"
    case lunge = "Lunge / Split"
    case hinge = "Hinge"
    case biceps = "Biceps"
    case pullAccessory = "Accessory"
    case horizontalPush = "Horizontal Push"
    case chestIsolation = "Chest Isolation"
    case verticalPush = "Vertical Push"
    case deltIsolation = "Delt Isolation"
    case triceps = "Triceps"
    case kneeFlexion = "Knee Flexion"
    case kneeExtension = "Knee Extension"
    case gluteIsolation = "Glute Isolation"
    case otherIsolation = "Other Isolation"
    case snatch = "Snatch"
    case clean = "Clean"
    case plyometric = "Plyometric"
    case antiExtension = "Anti-Extension"
    case flexion = "Flexion"
    case rotation = "Rotation"
    case carry = "Carry"

    var id: String { rawValue }

    var sortRank: Int {
        Self.allCases.firstIndex(of: self) ?? Int.max
    }

    static func infer(name: String, category: ExerciseCategory) -> ExerciseMovementPattern {
        let n = name.lowercased()
        switch category {
        case .pull: return inferPull(n)
        case .push: return inferPush(n)
        case .legs: return inferLegs(n)
        case .explosive: return inferExplosive(n)
        case .core: return inferCore(n)
        }
    }

    private static func contains(_ n: String, _ needles: String...) -> Bool {
        needles.contains { n.contains($0) }
    }

    /// Vertical before rows; upright row / wrist curl / rear-delt work are accessory.
    private static func inferPull(_ n: String) -> ExerciseMovementPattern {
        if contains(n, "wrist", "shrug", "face pull", "rear delt", "reverse pec", "upright") {
            return .pullAccessory
        }
        if contains(n, "pulldown", "pull-up", "pull up", "chin-up", "chin up") {
            return .verticalPull
        }
        if n.contains("row") {
            return .horizontalPull
        }
        if n.contains("deadlift") {
            return .hinge
        }
        if n.contains("curl") {
            return .biceps
        }
        return .pullAccessory
    }

    /// Close-grip bench is triceps, not a chest press.
    private static func inferPush(_ n: String) -> ExerciseMovementPattern {
        if contains(n, "pushdown", "skull", "triceps") || (n.contains("close-grip") && n.contains("bench")) {
            return .triceps
        }
        if contains(n, "fly", "pec deck") {
            return .chestIsolation
        }
        if contains(n, "lateral raise", "front raise") {
            return .deltIsolation
        }
        if contains(n, "overhead press", "shoulder press", "landmine press") {
            return .verticalPush
        }
        if contains(n, "bench", "dip", "push-up", "chest press") {
            return .horizontalPush
        }
        return .horizontalPush
    }

    /// Split squat / lunge / step-up before generic squat. Jefferson curl is a hinge.
    private static func inferLegs(_ n: String) -> ExerciseMovementPattern {
        if contains(n, "lunge", "split squat", "step-up", "bulgarian") {
            return .lunge
        }
        if contains(
            n,
            "deadlift",
            "romanian",
            "good morning",
            "jefferson",
            "back extension",
            "reverse hyper",
            "hip thrust",
            "glute-ham"
        ) {
            return .hinge
        }
        if contains(n, "nordic", "leg curl") {
            return .kneeFlexion
        }
        if n.contains("leg extension") {
            return .kneeExtension
        }
        if contains(n, "kickback", "abduction") {
            return .gluteIsolation
        }
        if contains(n, "adduction", "calf", "tibialis") {
            return .otherIsolation
        }
        if contains(n, "squat", "leg press") {
            return .squat
        }
        return .otherIsolation
    }

    private static func inferExplosive(_ n: String) -> ExerciseMovementPattern {
        if n.contains("snatch") { return .snatch }
        if n.contains("clean") { return .clean }
        return .plyometric
    }

    private static func inferCore(_ n: String) -> ExerciseMovementPattern {
        if contains(n, "plank", "ab wheel") { return .antiExtension }
        if contains(n, "woodchop", "rotation") { return .rotation }
        if contains(n, "walk", "carry") { return .carry }
        return .flexion
    }
}

enum ExerciseEquipment: String, CaseIterable, Identifiable, Hashable, Codable {
    case barbell
    case machine
    case functionalTrainer
    case kettlebell
    case dumbbell
    case bodyweight

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .barbell: return "Barbell"
        case .machine: return "Machine"
        case .functionalTrainer: return "Functional Trainer"
        case .kettlebell: return "Kettlebell"
        case .dumbbell: return "Dumbbell"
        case .bodyweight: return "Bodyweight"
        }
    }

    var shortBadge: String {
        switch self {
        case .barbell: return "BB"
        case .machine: return "MC"
        case .functionalTrainer: return "FT"
        case .kettlebell: return "KB"
        case .dumbbell: return "DB"
        case .bodyweight: return "BW"
        }
    }

    var showsPlateCalculator: Bool {
        switch self {
        case .barbell, .machine, .functionalTrainer:
            return true
        default:
            return false
        }
    }

    static func from(raw: String) -> ExerciseEquipment? {
        switch raw {
        case "functionalTrainer": return .machine
        case "other": return nil
        default: return ExerciseEquipment(rawValue: raw)
        }
    }

    static func resolve(raw: String?, name: String) -> ExerciseEquipment {
        if let raw, let resolved = from(raw: raw) {
            return resolved
        }
        return infer(from: name)
    }

    static func infer(from name: String) -> ExerciseEquipment {
        let n = name.lowercased()
        if n.contains("kettlebell") || n.contains("goblet") {
            return .kettlebell
        }
        if n.contains("dumbbell") {
            return .dumbbell
        }
        if n.contains("push-up") || n.contains("push up")
            || n.contains("pull-up") || n.contains("pull up")
            || n.contains("chin-up") || n.contains("chin up")
            || (n.contains("dip") && !n.contains("machine"))
            || n.contains("plank") || n.contains("bodyweight")
            || n.contains("pistol") || n.contains("ab wheel") {
            return .bodyweight
        }
        if n.contains("machine") || n.contains("leg press") || n.contains("leg extension")
            || n.contains("leg curl") || n.contains("calf raise")
            || n.contains("functional trainer") || n.contains("cable")
            || n.contains("lat pulldown") || n.contains("pulldown")
            || n.contains("face pull") || n.contains("pushdown") || n.contains("smith") {
            return .machine
        }
        if n.contains("barbell") || n.contains("deadlift") || n.contains("ohp")
            || n.contains("overhead press") || n.contains("hip thrust") || n.contains("bench")
            || n.contains("skull crusher") {
            return .barbell
        }
        if n.contains("squat"),
           !n.contains("split"),
           !n.contains("hack"),
           !n.contains("goblet"),
           !n.contains("pistol") {
            return .barbell
        }
        if n.contains("lunge") || n.contains("split squat") || n.contains("curl")
            || n.contains("raise") || n.contains("fly") {
            return .dumbbell
        }
        return .bodyweight
    }
}

struct CatalogExercise: Identifiable, Hashable {
    let id: String
    let name: String
    let category: ExerciseCategory
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let cues: String
    let equipment: ExerciseEquipment
    let imageAssetName: String?
    let pattern: ExerciseMovementPattern

    var primaryNames: [String] { primary.map(\.rawValue) }
    var secondaryNames: [String] { secondary.map(\.rawValue) }

    init(
        id: String,
        name: String,
        category: ExerciseCategory,
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        cues: String,
        equipment: ExerciseEquipment? = nil,
        imageAssetName: String? = nil,
        pattern: ExerciseMovementPattern? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primary = primary
        self.secondary = secondary
        self.cues = cues
        self.equipment = equipment ?? ExerciseEquipment.infer(from: name)
        self.imageAssetName = imageAssetName
        self.pattern = pattern ?? ExerciseMovementPattern.infer(name: name, category: category)
    }
}

enum ExerciseCatalog {
    static let all: [CatalogExercise] = [
        CatalogExercise(
            id: "back-squat",
            name: "Back Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.adductors, .coreAndAbs, .erectors],
            cues: "Brace before you descend. Sit between the hips, keep mid-foot pressure, and stand without collapsing the chest.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "front-squat",
            name: "Front Squat",
            category: .legs,
            primary: [.quadriceps, .coreAndAbs],
            secondary: [.glutes, .rhomboids],
            cues: "Elbows high, torso tall. The bar stays over mid-foot as you sit down and drive up.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "zercher-squat",
            name: "Zercher Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.coreAndAbs, .erectors, .adductors],
            cues: "Hold the bar in the elbow crook and keep a tall torso. Brace, sit between the hips, and stand without folding forward.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "hack-squat",
            name: "Hack Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [],
            cues: "Back against the pad, feet planted. Descend with control and stand without locking out aggressively.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "smith-machine-squat",
            name: "Smith Machine Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [],
            cues: "Brace and sit between the hips. Keep mid-foot pressure; don’t collapse the chest or ride the bar forward.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "belt-squat",
            name: "Belt Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [],
            cues: "Load the hips, not the spine. Sit down and stand tall; don’t let the torso fold.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "sissy-squat",
            name: "Sissy Squat",
            category: .legs,
            primary: [.quadriceps],
            secondary: [],
            cues: "Knees travel forward as the hips stay relatively high. Control the descent; don’t dump into the low back.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "reverse-squat",
            name: "Reverse Squat",
            category: .legs,
            primary: [.hipFlexors],
            secondary: [.coreAndAbs, .quadriceps],
            cues: "Drive the knees up against the load without dumping the pelvis. Control the return; don’t swing.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "landmine-squat",
            name: "Landmine Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.coreAndAbs, .adductors],
            cues: "Hold the bar at chest height and sit between the hips. Brace, stay tall, and stand without folding forward.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "box-squat",
            name: "Box Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.adductors, .coreAndAbs, .erectors],
            cues: "Sit back to the box under control, pause briefly, then drive up without rocking forward.",
            equipment: .barbell,
            pattern: .squat
        ),
        CatalogExercise(
            id: "goblet-squat",
            name: "Goblet Squat",
            category: .legs,
            primary: [.quadriceps],
            secondary: [.coreAndAbs, .glutes, .adductors],
            cues: "Hold the weight at chest height. Sit between the hips and keep the elbows inside the knees.",
            equipment: .dumbbell,
            pattern: .squat
        ),
        CatalogExercise(
            id: "safety-bar-squat",
            name: "Safety Bar Squat",
            category: .legs,
            primary: [.quadriceps],
            secondary: [.coreAndAbs, .adductors, .erectors, .glutes],
            cues: "Set the yoke on your back and brace. Sit between the hips and drive up without folding forward.",
            equipment: .barbell,
            pattern: .squat
        ),
        CatalogExercise(
            id: "leg-press",
            name: "Leg Press",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.hamstrings, .adductors],
            cues: "Full foot on the platform. Lower with control and stop before the low back rounds.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "bulgarian-split-squat",
            name: "Bulgarian Split Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.hamstrings, .adductors, .coreAndAbs],
            cues: "Most of the load on the front leg. Slight forward lean is fine; keep the front knee tracking over the toes.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "zercher-split-squat",
            name: "Zercher Split Squat",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.hamstrings, .adductors, .coreAndAbs],
            cues: "Bar in the elbow crook, most of the load on the front leg. Stay tall; keep the front knee tracking over the toes.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "step-up",
            name: "Step-Up",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.quadriceps, .coreAndAbs],
            cues: "Drive through the whole foot on the box. Stand tall; don’t push off the trailing leg. Use a big box.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "zercher-step-up",
            name: "Zercher Step-Up",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.quadriceps, .coreAndAbs],
            cues: "Bar in the elbow crook, drive through the whole foot on the box. Stand tall; don’t push off the trailing leg.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "walking-lunge",
            name: "Walking Lunge",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.quadriceps, .coreAndAbs],
            cues: "Long enough stride to load the glute. Front knee tracks the toes; trail knee drops under the hip.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "zercher-lunge",
            name: "Zercher Lunge",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.quadriceps, .coreAndAbs],
            cues: "Hold the bar in the elbow crook and stay tall. Long enough stride to load the glute; front knee tracks the toes.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "reverse-lunge",
            name: "Reverse Lunge",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.quadriceps, .coreAndAbs],
            cues: "Step back far enough to load the front glute. Front knee tracks the toes; don’t crash the trail knee.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "zercher-reverse-lunge",
            name: "Zercher Reverse Lunge",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.quadriceps, .coreAndAbs],
            cues: "Hold the bar in the elbow crook. Step back far enough to load the front glute; stay tall through the torso.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "forward-lunge",
            name: "Forward Lunge",
            category: .legs,
            primary: [.quadriceps, .glutes],
            secondary: [.hamstrings, .coreAndAbs],
            cues: "Step forward and drop the trail knee under the hip. Front knee tracks; don’t slam into the bottom.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "cossack-squat",
            name: "Cossack Squat",
            category: .legs,
            primary: [.quadriceps, .adductors, .glutes],
            secondary: [.hamstrings, .coreAndAbs],
            cues: "Shift side to side with one leg extended. Keep the working heel down and chest as tall as you can.",
            equipment: .dumbbell,
            pattern: .squat
        ),
        CatalogExercise(
            id: "pistol-squat",
            name: "Pistol Squat",
            category: .legs,
            primary: [.quadriceps],
            secondary: [.coreAndAbs, .hipFlexors, .glutes],
            cues: "Balance on one leg, extend the other forward. Sit as deep as you can control and stand without collapsing.",
            equipment: .bodyweight,
            pattern: .lunge
        ),
        CatalogExercise(
            id: "box-jump",
            name: "Box Jump",
            category: .explosive,
            primary: [.quadriceps, .glutes],
            secondary: [.hamstrings, .calves, .coreAndAbs],
            cues: "Load the hips, then jump onto the box and land softly with the whole foot. Stand tall to finish; don’t rebound off a bouncing landing.",
            equipment: .bodyweight
        ),
        CatalogExercise(
            id: "leg-extension",
            name: "Leg Extension",
            category: .legs,
            primary: [.quadriceps],
            secondary: [],
            cues: "Control the top squeeze. Avoid slamming the stack; pause briefly at lockout.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "seated-leg-curl",
            name: "Seated Leg Curl",
            category: .legs,
            primary: [.hamstrings],
            secondary: [],
            cues: "Hips stay pinned to the pad. Curl through a full range and lower slowly.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "lying-leg-curl",
            name: "Lying Leg Curl",
            category: .legs,
            primary: [.hamstrings],
            secondary: [.erectors],
            cues: "Hips stay glued to the pad. Curl fully and lower without lifting the pelvis.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "nordic-curl",
            name: "Nordic Curl",
            category: .legs,
            primary: [.hamstrings],
            secondary: [],
            cues: "Brace and lower as far as you can control. Catch with the hamstrings; don’t fold at the hips.",
            equipment: .bodyweight
        ),
        CatalogExercise(
            id: "glute-ham-raise",
            name: "Glute-Ham Raise",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.erectors],
            cues: "Hips stay extended as you lower. Pull back with the hamstrings; don’t pike or fold at the waist.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "romanian-deadlift",
            name: "Romanian Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.erectors],
            cues: "Soft knees, push the hips back, bar close to the legs. Stop when the hamstrings run out of range.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "single-leg-romanian-deadlift",
            name: "Single Leg Romanian Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes],
            secondary: [.erectors, .coreAndAbs],
            cues: "Hinge at the hip over one leg, trailing leg reaching back for balance. Keep the hips square and the weight close.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "deadlift",
            name: "Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes, .erectors],
            secondary: [.quadriceps, .traps, .coreAndAbs],
            cues: "Wedge in, brace, and push the floor away. The bar stays over mid-foot from floor to lockout.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "zercher-deadlift",
            name: "Zercher Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes, .erectors],
            secondary: [.quadriceps, .coreAndAbs, .traps],
            cues: "Bar in the elbow crook from the floor. Brace, then stand tall without losing the torso.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "sumo-deadlift",
            name: "Sumo Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes, .erectors],
            secondary: [.quadriceps, .traps, .adductors, .coreAndAbs],
            cues: "Wide stance, toes turned out. Push the knees out, wedge in, and keep the bar over mid-foot.",
            equipment: .barbell,
            pattern: .hinge
        ),
        CatalogExercise(
            id: "trap-bar-deadlift",
            name: "Trap Bar Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes, .quadriceps],
            secondary: [.erectors, .traps, .coreAndAbs],
            cues: "Stand inside the handles, hinge and grip. Push the floor away and stand tall without rounding the back.",
            equipment: .barbell,
            pattern: .hinge
        ),
        CatalogExercise(
            id: "rack-pull",
            name: "Rack Pull",
            category: .legs,
            primary: [.erectors, .glutes, .traps],
            secondary: [.hamstrings, .coreAndAbs],
            cues: "Set the bar at knee height or above. Brace, then drive the hips forward to lockout without hyperextending.",
            equipment: .barbell,
            pattern: .hinge
        ),
        CatalogExercise(
            id: "deficit-deadlift",
            name: "Deficit Deadlift",
            category: .legs,
            primary: [.hamstrings, .glutes, .erectors],
            secondary: [.quadriceps, .traps, .coreAndAbs],
            cues: "Stand on a plate or platform. Wedge in from the deeper start, brace, and pull with the bar over mid-foot.",
            equipment: .barbell,
            pattern: .hinge
        ),
        CatalogExercise(
            id: "good-morning",
            name: "Good Morning",
            category: .legs,
            primary: [.hamstrings, .erectors],
            secondary: [.glutes],
            cues: "Brace, then hinge until the hamstrings stop you. Bar stays over mid-foot; don’t round the back.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "seated-good-morning",
            name: "Seated Good Morning",
            category: .legs,
            primary: [.adductors, .erectors],
            secondary: [.coreAndAbs, .hamstrings],
            cues: "Sit tall, then hinge and pull with the posterior chain. Brace; don’t round through the low back to finish.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "jefferson-curl",
            name: "Jefferson Curl",
            category: .legs,
            primary: [.hamstrings, .erectors],
            secondary: [.glutes, .coreAndAbs],
            cues: "Hold the bar in the hands and round the spine slowly from the neck down. Reverse with control; don’t bounce out of the bottom.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "zercher-jefferson-curl",
            name: "Zercher Jefferson Curl",
            category: .legs,
            primary: [.hamstrings, .erectors],
            secondary: [.glutes, .coreAndAbs],
            cues: "Bar in the elbow crook. Round the spine slowly vertebra by vertebra, then reverse with control; don’t rush the flexion.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "back-extension",
            name: "Back Extension",
            category: .legs,
            primary: [.erectors, .glutes],
            secondary: [.hamstrings],
            cues: "Hinge at the hips, not the spine. Rise until the body is in line; don’t hyperextend the low back.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "reverse-hyper",
            name: "Reverse Hyper",
            category: .legs,
            primary: [.glutes, .hamstrings],
            secondary: [.erectors],
            cues: "Hips on the pad, swing the legs with the glutes. Stop in line with the torso; don’t hyperextend the low back.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "snatch",
            name: "Snatch",
            category: .explosive,
            primary: [.hamstrings, .glutes, .traps],
            secondary: [.quadriceps, .coreAndAbs, .anteriorDelts, .lats],
            cues: "Keep the bar close, then explode and punch under to lockout. Catch in a full squat with arms locked; don’t press it out.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "power-snatch",
            name: "Power Snatch",
            category: .explosive,
            primary: [.hamstrings, .glutes, .traps],
            secondary: [.quadriceps, .coreAndAbs, .anteriorDelts],
            cues: "Same pull as the snatch, catch higher. Bar close, explode, and punch under without riding into a deep squat.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "snatch-pull",
            name: "Snatch Pull",
            category: .explosive,
            primary: [.hamstrings, .glutes, .traps],
            secondary: [.quadriceps, .lats],
            cues: "Pull like a snatch without going overhead. Bar close, explode through the hips, and finish tall; don’t lean back and yank.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "clean",
            name: "Clean",
            category: .explosive,
            primary: [.hamstrings, .glutes, .traps],
            secondary: [.quadriceps, .coreAndAbs, .biceps],
            cues: "Bar close off the floor, then explode and pull under to the front rack. Catch with elbows high; don’t crash the bar onto the shoulders.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "clean-and-jerk",
            name: "Clean and Jerk",
            category: .explosive,
            primary: [.hamstrings, .glutes, .traps],
            secondary: [.quadriceps, .coreAndAbs, .anteriorDelts, .triceps],
            cues: "Clean to a solid front rack, then dip and drive the bar overhead. Punch under the jerk and lock out; don’t press it out from the shoulders.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "kettlebell-swing",
            name: "Kettlebell Swing",
            category: .explosive,
            primary: [.hamstrings],
            secondary: [.glutes, .erectors, .coreAndAbs, .adductors, .forearmsAndGrip],
            cues: "Hinge hard, then snap the hips to float the bell to chest height. Keep the arms loose; don’t squat the swing or lift with the shoulders.",
            equipment: .kettlebell,
            pattern: .hinge
        ),
        CatalogExercise(
            id: "kettlebell-snatch",
            name: "Kettlebell Snatch",
            category: .explosive,
            primary: [.glutes, .hamstrings, .anteriorDelts],
            secondary: [.biceps, .coreAndAbs, .erectors, .forearmsAndGrip],
            cues: "Hike the bell, explode the hips, and punch through to lockout overhead. The bell should roll around the wrist, not slam onto it.",
            equipment: .kettlebell
        ),
        CatalogExercise(
            id: "kettlebell-clean",
            name: "Kettlebell Clean",
            category: .explosive,
            primary: [.glutes, .hamstrings, .biceps],
            secondary: [.anteriorDelts, .coreAndAbs, .erectors, .forearmsAndGrip],
            cues: "Hinge and snap the hips, then guide the bell into a tight rack. Elbow close, wrist stacked; don’t let the bell crash onto the forearm.",
            equipment: .kettlebell
        ),
        CatalogExercise(
            id: "kettlebell-clean-and-jerk",
            name: "Kettlebell Clean and Jerk",
            category: .explosive,
            primary: [.glutes, .hamstrings, .anteriorDelts],
            secondary: [.triceps, .coreAndAbs, .biceps, .quadriceps, .erectors],
            cues: "Clean to a solid rack, then dip and drive the bell overhead. Punch under to lockout; don’t press it out from a stalled rack.",
            equipment: .kettlebell
        ),
        CatalogExercise(
            id: "kettlebell-high-pull",
            name: "Kettlebell High Pull",
            category: .explosive,
            primary: [.traps, .lateralDelts],
            secondary: [.glutes, .hamstrings, .biceps, .forearmsAndGrip],
            cues: "Hinge and explode the hips, then pull the bell to the chest with high elbows. Keep it close; don’t shrug it out in front of you.",
            equipment: .kettlebell
        ),
        CatalogExercise(
            id: "kettlebell-push-press",
            name: "Kettlebell Push Press",
            category: .explosive,
            primary: [.anteriorDelts, .triceps],
            secondary: [.quadriceps, .glutes, .coreAndAbs, .lateralDelts],
            cues: "Dip the knees slightly, then drive the bell overhead and finish with the arm. Use the legs to start the press; don’t turn it into a strict press.",
            equipment: .kettlebell
        ),
        CatalogExercise(
            id: "hip-thrust",
            name: "Hip Thrust",
            category: .legs,
            primary: [.glutes],
            secondary: [.hamstrings],
            cues: "Chin tucked, ribs down. Finish with a hard glute squeeze and a flat torso at the top.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "barbell-hip-thrust",
            name: "Barbell Hip Thrust",
            category: .legs,
            primary: [.glutes],
            secondary: [.hamstrings, .coreAndAbs],
            cues: "Upper back on the bench, chin tucked, ribs down. Drive the bar up with the glutes and finish with a flat torso at the top.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "glute-kickback",
            name: "Glute Kickback",
            category: .legs,
            primary: [.glutes],
            secondary: [.hamstrings],
            cues: "Square the hips and kick without arching the low back. Squeeze at the top; don’t swing.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "machine-hip-abduction",
            name: "Machine Hip Abduction",
            category: .legs,
            primary: [.abductors],
            secondary: [],
            cues: "Sit tall, then drive the knees out. Pause at the end range; don’t lean to cheat.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "machine-hip-adduction",
            name: "Machine Hip Adduction",
            category: .legs,
            primary: [.adductors],
            secondary: [],
            cues: "Sit tall and squeeze the thighs together. Control the return; don’t slam the stack.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "calf-raise",
            name: "Calf Raise",
            category: .legs,
            primary: [.calves],
            secondary: [],
            cues: "Full stretch at the bottom, pause at the top. Knee position stays consistent.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "tibialis-raise",
            name: "Tibialis Raise",
            category: .legs,
            primary: [.tibialis],
            secondary: [],
            cues: "Heels planted, lift the toes as high as you can. Pause at the top; don’t rock the torso.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "barbell-bench-press",
            name: "Barbell Bench Press",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts],
            cues: "Plant the feet, set the scaps, and lower to the chest with wrists stacked. Press back toward the rack.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "decline-bench-press",
            name: "Decline Bench Press",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts],
            cues: "Lock the legs under the pads and lower to the lower chest. Press up and slightly back toward the rack.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "smith-machine-bench-press",
            name: "Smith Machine Bench Press",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts],
            cues: "Set the bar path over the nipple line. Lower under control and press without bouncing off the safety catches.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "incline-barbell-bench-press",
            name: "Incline Barbell Bench Press",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts],
            cues: "Set the scaps and keep a slight arch. Lower to the upper chest with control; don’t bounce or flare the elbows out wide.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "close-grip-bench-press",
            name: "Close-Grip Bench Press",
            category: .push,
            primary: [.triceps],
            secondary: [.chest, .anteriorDelts],
            cues: "Grip just inside shoulder width. Elbows stay tucked; lower to the chest and press without bouncing.",
            equipment: .barbell,
            pattern: .triceps
        ),
        CatalogExercise(
            id: "jm-press",
            name: "JM Press",
            category: .push,
            primary: [.triceps],
            secondary: [.chest, .anteriorDelts],
            cues: "Elbows forward, bar travels down toward the upper chest. Press back without flaring the elbows wide.",
            equipment: .barbell,
            pattern: .triceps
        ),
        CatalogExercise(
            id: "incline-dumbbell-press",
            name: "Incline Dumbbell Press",
            category: .push,
            primary: [.chest, .anteriorDelts],
            secondary: [.triceps],
            cues: "30–45° bench. Lower until the elbows are in line with the torso, then press without flaring wildly.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "dumbbell-bench-press",
            name: "Dumbbell Bench Press",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts],
            cues: "Slight arch, dumbbells travel in a gentle arc. Control the bottom stretch.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "machine-chest-press",
            name: "Machine Chest Press",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts],
            cues: "Brace and keep the shoulders packed. Press through a full range and stop short of locking out aggressively.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "dips",
            name: "Dips",
            category: .push,
            primary: [.chest, .triceps],
            secondary: [.anteriorDelts],
            cues: "Shoulders down. Lean forward for more chest; stay more upright for triceps. Don’t dump into the joints.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "dip-machine",
            name: "Dip Machine",
            category: .push,
            primary: [.chest, .triceps],
            secondary: [.anteriorDelts],
            cues: "Set the seat so the handles line up under the shoulders. Lean forward for more chest; stay upright for triceps.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "push-up",
            name: "Push-Up",
            category: .push,
            primary: [.chest],
            secondary: [.triceps, .anteriorDelts, .coreAndAbs],
            cues: "Body in one line. Elbows ~45° from the torso. Chest to near the floor, then press the floor away.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "overhead-press",
            name: "Overhead Press",
            category: .push,
            primary: [.anteriorDelts],
            secondary: [.triceps, .traps, .coreAndAbs],
            cues: "Glutes tight, ribs stacked. Bar path close to the face; head through at the top.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "landmine-press",
            name: "Landmine Press",
            category: .push,
            primary: [.chest, .anteriorDelts],
            secondary: [.triceps, .coreAndAbs],
            cues: "Brace and press the bar up and slightly forward on an arc. Don’t over-arch the low back or let the shoulder dump forward.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "dumbbell-shoulder-press",
            name: "Dumbbell Shoulder Press",
            category: .push,
            primary: [.anteriorDelts, .lateralDelts],
            secondary: [.triceps],
            cues: "Press slightly in front of the head. Don’t over-arch the low back.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "machine-shoulder-press",
            name: "Machine Shoulder Press",
            category: .push,
            primary: [.anteriorDelts, .lateralDelts],
            secondary: [.triceps],
            cues: "Ribs down, glutes on. Press overhead without over-arching the low back.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "lateral-raise",
            name: "Lateral Raise",
            category: .push,
            primary: [.lateralDelts],
            secondary: [.traps],
            cues: "Lead with the elbows, slight lean, and stop around shoulder height. Control the lower.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "cable-lateral-raise",
            name: "Cable Lateral Raise",
            category: .push,
            primary: [.lateralDelts],
            secondary: [.traps],
            cues: "Lead with the elbows and keep tension through the whole arc. Stop around shoulder height; don’t swing.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "front-raise",
            name: "Front Raise",
            category: .push,
            primary: [.anteriorDelts],
            secondary: [],
            cues: "Raise to eye height with a slight elbow bend. Don’t use the low back to heave the weight up.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "cable-fly",
            name: "Cable Fly",
            category: .push,
            primary: [.chest],
            secondary: [.anteriorDelts],
            cues: "Soft elbows, sweep in an arc, and squeeze without shrugging.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "dumbbell-fly",
            name: "Dumbbell Fly",
            category: .push,
            primary: [.chest],
            secondary: [.anteriorDelts],
            cues: "Slight bend in the elbows and a wide arc. Stop when the chest is stretched; don’t turn it into a press.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "pec-deck",
            name: "Pec Deck",
            category: .push,
            primary: [.chest],
            secondary: [.anteriorDelts],
            cues: "Soft elbows, chest proud. Sweep until you feel a stretch, then squeeze without shrugging the shoulders.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "tricep-pushdown",
            name: "Tricep Pushdown",
            category: .push,
            primary: [.triceps],
            secondary: [],
            cues: "Elbows pinned by the sides. Full extension, then a controlled return.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "overhead-cable-triceps-extension",
            name: "Overhead Cable Triceps Extension",
            category: .push,
            primary: [.triceps],
            secondary: [],
            cues: "Elbows stay high and close. Extend fully, then control the stretch; don’t flare.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "skull-crusher",
            name: "Skull Crusher",
            category: .push,
            primary: [.triceps],
            secondary: [],
            cues: "Only the elbows move. Lower toward the forehead or hairline, then extend without flaring.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "barbell-row",
            name: "Barbell Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts, .erectors],
            cues: "Hinge, brace, and row to the lower ribs. Don’t turn it into a shrug or a deadlift.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "landmine-row",
            name: "Landmine Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts, .coreAndAbs],
            cues: "Hinge, brace, and row the bar to the hip. Don’t yank with the torso or turn it into a shrug.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "chest-supported-dumbbell-row",
            name: "Chest-Supported Dumbbell Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts],
            cues: "Chest stays on the pad. Row the elbows back and squeeze; don’t yank from the neck.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "chest-supported-t-bar-row",
            name: "Chest-Supported T-Bar Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts],
            cues: "Drive the chest into the pad. Pull toward the lower ribs and lower under control; don’t bounce.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "one-arm-dumbbell-row",
            name: "One-Arm Dumbbell Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts],
            cues: "Hinge, brace, and row the elbow to the hip. Don’t rotate the torso to cheat the last inches.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "one-arm-cable-row",
            name: "One-Arm Cable Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts],
            cues: "Start from a long arm. Pull the elbow back, pause, then reach without rounding hard.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "seated-cable-row",
            name: "Seated Cable Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts],
            cues: "Start from a long arm. Pull elbows back, pause, then reach forward without rounding hard.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "inverted-row",
            name: "Inverted Row",
            category: .pull,
            primary: [.lats, .rhomboids],
            secondary: [.biceps, .posteriorDelts],
            cues: "Body straight from a bar or rings, chest to the bar. Keep the hips up; don’t let them sag.",
            equipment: .bodyweight
        ),
        CatalogExercise(
            id: "lat-pulldown",
            name: "Lat Pulldown",
            category: .pull,
            primary: [.lats],
            secondary: [.biceps, .rhomboids],
            cues: "Set the scaps first. Pull the bar to the upper chest, elbows down, not behind the body.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "close-grip-lat-pulldown",
            name: "Close-Grip Lat Pulldown",
            category: .pull,
            primary: [.lats, .biceps],
            secondary: [.rhomboids],
            cues: "Set the scaps, then pull the handle to the upper chest. Elbows stay in; don’t lean way back.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "wide-grip-lat-pulldown",
            name: "Wide-Grip Lat Pulldown",
            category: .pull,
            primary: [.lats],
            secondary: [.biceps, .rhomboids],
            cues: "Wide grip, scaps set. Pull to the upper chest with elbows down, not behind the body.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "pull-up",
            name: "Pull-Up",
            category: .pull,
            primary: [.lats],
            secondary: [.biceps, .rhomboids],
            cues: "Dead hang to chin over the bar. Drive elbows down; avoid kipping unless that’s the point.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "assisted-pull-up",
            name: "Assisted Pull-Up",
            category: .pull,
            primary: [.lats],
            secondary: [.biceps, .rhomboids],
            cues: "Set the counterweight so the last rep or two is hard, not free. Dead hang to chin over the bar.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "chin-up",
            name: "Chin-Up",
            category: .pull,
            primary: [.lats, .biceps],
            secondary: [.rhomboids],
            cues: "Supinated grip. Same full range as a pull-up, with a little more biceps.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "cable-pullover",
            name: "Cable Pullover",
            category: .pull,
            primary: [.lats],
            secondary: [.triceps, .coreAndAbs],
            cues: "Arms stay slightly bent. Sweep the handle down and in an arc over the hips; don’t turn it into a triceps pushdown.",
            equipment: .functionalTrainer,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "dumbbell-pullover",
            name: "Dumbbell Pullover",
            category: .pull,
            primary: [.lats],
            secondary: [.triceps, .coreAndAbs],
            cues: "Upper back supported, weight held with soft elbows. Lower behind the head for a stretch, then pull back over the chest.",
            equipment: .dumbbell,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "face-pull",
            name: "Face Pull",
            category: .pull,
            primary: [.posteriorDelts, .traps],
            secondary: [.rhomboids],
            cues: "Pull toward the face, externally rotate at the end, and keep the ribs down.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "rear-delt-fly",
            name: "Rear Delt Fly",
            category: .pull,
            primary: [.posteriorDelts],
            secondary: [.rhomboids],
            cues: "Hinge, soft elbows, and sweep the arms out. Stop at torso height; don’t yank with the traps.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "cable-rear-delt-fly",
            name: "Cable Rear Delt Fly",
            category: .pull,
            primary: [.posteriorDelts],
            secondary: [.rhomboids, .traps],
            cues: "Hinge or stand tall with soft elbows. Sweep the handles out to the sides and squeeze the rear delts.",
            equipment: .functionalTrainer,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "reverse-pec-deck",
            name: "Reverse Pec Deck",
            category: .pull,
            primary: [.posteriorDelts],
            secondary: [.rhomboids],
            cues: "Chest on the pad, soft elbows. Sweep out and squeeze the rear delts without shrugging.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "upright-row",
            name: "Upright Row",
            category: .pull,
            primary: [.traps, .lateralDelts],
            secondary: [.biceps],
            cues: "Lead with the elbows, bar close to the body. Stop around chest height; don’t yank the bar into the neck.",
            equipment: .barbell,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "dumbbell-shrug",
            name: "Dumbbell Shrug",
            category: .pull,
            primary: [.traps],
            secondary: [],
            cues: "Stand tall and shrug straight up. Pause at the top; don’t roll the shoulders.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "barbell-shrug",
            name: "Barbell Shrug",
            category: .pull,
            primary: [.traps],
            secondary: [],
            cues: "Brace, then shrug the bar straight up. Pause and lower; don’t roll or heave.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "barbell-curl",
            name: "Barbell Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [.forearmsAndGrip],
            cues: "Elbows close. No swing. Squeeze at the top and lower for 2–3 seconds.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "dumbbell-curl",
            name: "Dumbbell Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [.forearmsAndGrip],
            cues: "Supinate through the lift. Keep the upper arm still.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "hammer-curl",
            name: "Hammer Curl",
            category: .pull,
            primary: [.biceps, .forearmsAndGrip],
            secondary: [],
            cues: "Neutral grip. Control both directions; this is also a forearm builder.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "preacher-curl",
            name: "Preacher Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [],
            cues: "Upper arms pinned to the pad. Curl through a full range and lower slowly; don’t hyperextend the elbows.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "preacher-curl-machine",
            name: "Preacher Curl Machine",
            category: .pull,
            primary: [.biceps],
            secondary: [],
            cues: "Upper arms pinned to the pad. Curl through a full range and lower slowly; don’t hyperextend the elbows.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "incline-dumbbell-curl",
            name: "Incline Dumbbell Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [],
            cues: "Let the arms hang. Curl without swinging, and keep the shoulders from rolling forward.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "cable-curl",
            name: "Cable Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [],
            cues: "Elbows close, constant tension. Squeeze at the top and don’t lean back to finish.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "concentration-curl",
            name: "Concentration Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [],
            cues: "Elbow braced. Curl to the shoulder and lower fully; no body English.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "spider-curl",
            name: "Spider Curl",
            category: .pull,
            primary: [.biceps],
            secondary: [],
            cues: "Chest on the bench, arms hanging. Curl without swinging; control the stretch at the bottom.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "reverse-curl",
            name: "Reverse Curl",
            category: .pull,
            primary: [.biceps, .forearmsAndGrip],
            secondary: [],
            cues: "Pronated grip, elbows close. Curl without swinging; this loads the forearms too.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "wrist-curl",
            name: "Wrist Curl",
            category: .pull,
            primary: [.forearmsAndGrip],
            secondary: [],
            cues: "Forearms supported, wrists hanging. Curl through a full range and don’t let the elbows take over.",
            equipment: .functionalTrainer,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "reverse-wrist-curl",
            name: "Reverse Wrist Curl",
            category: .pull,
            primary: [.forearmsAndGrip],
            secondary: [],
            cues: "Forearms supported, palms down. Extend the wrists through a full range; keep it slow.",
            equipment: .functionalTrainer,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "hand-gripper",
            name: "Hand Gripper",
            category: .pull,
            primary: [.forearmsAndGrip],
            secondary: [],
            cues: "Squeeze until the handles touch, then release under control. Keep the wrist neutral and elbow still.",
            equipment: .machine,
            pattern: .pullAccessory
        ),
        CatalogExercise(
            id: "plank",
            name: "Plank",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [.anteriorDelts, .glutes],
            cues: "Ribs down, glutes on, neck long. Don’t sag or pike.",
            equipment: .bodyweight
        ),
        CatalogExercise(
            id: "zercher-carry",
            name: "Zercher Carry",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [.quadriceps, .glutes, .rhomboids],
            cues: "Hold the bar in the elbow crook and brace hard. Walk tall without leaning or letting the torso fold.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "farmers-walk",
            name: "Farmer's Walk",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [.traps, .forearmsAndGrip, .quadriceps],
            cues: "Brace hard and walk tall with the weights close to your sides. Don’t shrug or let the torso lean; short, quick steps.",
            equipment: .dumbbell
        ),
        CatalogExercise(
            id: "turkish-get-up",
            name: "Turkish Get-Up",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [.anteriorDelts, .glutes, .quadriceps],
            cues: "Press the bell up and keep your eyes on it through every step from floor to standing. Move slow and deliberate, not rushed.",
            equipment: .kettlebell,
            pattern: .carry
        ),
        CatalogExercise(
            id: "hanging-leg-raise",
            name: "Hanging Leg Raise",
            category: .core,
            primary: [.hipFlexors],
            secondary: [.coreAndAbs, .forearmsAndGrip],
            cues: "Posteriorly tilt the pelvis and lift with the abs, not momentum.",
            equipment: .bodyweight
        ),
        CatalogExercise(
            id: "sit-up",
            name: "Sit-Up",
            category: .core,
            primary: [.hipFlexors],
            secondary: [.coreAndAbs],
            cues: "Ribs toward the hips. Sit up without yanking on the neck or using momentum.",
            equipment: .bodyweight
        ),
        CatalogExercise(
            id: "cable-crunch",
            name: "Cable Crunch",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [],
            cues: "Round the spine to shorten the abs. Hips stay relatively still.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "ab-crunch-machine",
            name: "Ab Crunch Machine",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [],
            cues: "Round the spine to shorten the abs rather than just pulling the handles down. Control the return.",
            equipment: .machine
        ),
        CatalogExercise(
            id: "cable-woodchop",
            name: "Cable Woodchop",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [],
            cues: "Brace and rotate through the torso, not the arms. Control both directions; don’t twist from the knees.",
            equipment: .functionalTrainer
        ),
        CatalogExercise(
            id: "landmine-rotation",
            name: "Landmine Rotation",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [],
            cues: "Brace and rotate the bar through the torso, not the arms. Control both directions; don’t twist from the knees.",
            equipment: .barbell
        ),
        CatalogExercise(
            id: "russian-twist",
            name: "Russian Twist",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [],
            cues: "Lean back with feet up or grounded, rotate the torso side to side. Move slow; don’t just swing the arms.",
            equipment: .bodyweight,
            pattern: .rotation
        ),
        CatalogExercise(
            id: "ab-wheel",
            name: "Ab Wheel",
            category: .core,
            primary: [.coreAndAbs],
            secondary: [.lats, .anteriorDelts],
            cues: "Roll out only as far as you can keep a braced, slightly rounded torso."
        )
    ]

    /// Catalog list order: movement pattern (`ExerciseMovementPattern.allCases`), then name.
    static func displaySorted(_ items: [CatalogExercise]) -> [CatalogExercise] {
        items.sorted { lhs, rhs in
            if lhs.pattern.sortRank != rhs.pattern.sortRank {
                return lhs.pattern.sortRank < rhs.pattern.sortRank
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    static func grouped() -> [(ExerciseCategory, [CatalogExercise])] {
        ExerciseCategory.allCases.compactMap { category in
            let items = displaySorted(all.filter { $0.category == category })
            return items.isEmpty ? nil : (category, items)
        }
    }

    static func match(name: String) -> CatalogExercise? {
        let key = name.lowercased()
        return all.first { $0.name.lowercased() == key }
    }

    static func equipment(forName name: String) -> ExerciseEquipment {
        match(name: name)?.equipment ?? ExerciseEquipment.infer(from: name)
    }

    static func imageAssetName(for exercise: CatalogExercise) -> String {
        exercise.imageAssetName ?? "exercise-\(exercise.id)"
    }
}
