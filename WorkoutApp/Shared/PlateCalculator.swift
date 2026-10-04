import Foundation

struct PlateCount: Equatable {
    var weight: Double
    var count: Int
}

struct PlateBreakdown: Equatable {
    var equipment: ExerciseEquipment
    var unit: WeightUnit
    var total: Double
    var base: Double
    var perSide: Double
    var plates: [PlateCount]
    var remainder: Double

    var isBelowBase: Bool { total + 0.001 < base }

    var compactPlates: String {
        if plates.isEmpty {
            return remainder > 0.001 ? "" : "—"
        }
        return plates.map { plate in
            let label = Formatters.trimmedNumber(plate.weight)
            return plate.count > 1 ? "\(plate.count)×\(label)" : label
        }.joined(separator: " + ")
    }
}

enum PlateCalculator {
    static let kgPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let lbPlates: [Double] = [45, 35, 25, 10, 5, 2.5]

    static func plates(for unit: WeightUnit) -> [Double] {
        unit == .kg ? kgPlates : lbPlates
    }

    static func calculate(
        total: Double,
        unit: WeightUnit,
        equipment: ExerciseEquipment,
        barKg: Double,
        barLb: Double
    ) -> PlateBreakdown {
        let base = EquipmentSettings.plateBaseWeight(
            for: equipment,
            unit: unit,
            barKg: barKg,
            barLb: barLb
        )
        return calculate(
            total: total,
            base: base,
            unit: unit,
            equipment: equipment
        )
    }

    static func calculate(
        total: Double,
        base: Double,
        unit: WeightUnit,
        equipment: ExerciseEquipment
    ) -> PlateBreakdown {
        let load = max(total - base, 0)
        let perSide = load / 2
        var remaining = perSide
        var result: [PlateCount] = []
        for plate in plates(for: unit) {
            let count = Int(remaining / plate + 1e-9)
            if count > 0 {
                result.append(PlateCount(weight: plate, count: count))
                remaining -= Double(count) * plate
            }
        }
        if remaining < 0.05 {
            remaining = 0
        }
        return PlateBreakdown(
            equipment: equipment,
            unit: unit,
            total: total,
            base: base,
            perSide: perSide,
            plates: result,
            remainder: remaining
        )
    }
}

enum EquipmentSettings {
    static let barbellBarKgKey = "barbellBarKg"
    static let barbellBarLbKey = "barbellBarLb"

    static let defaultBarKg: Double = 20
    static let defaultBarLb: Double = 45

    static func barStep(for unit: WeightUnit) -> Double {
        unit == .kg ? 2.5 : 5
    }

    static func plateBaseWeight(
        for equipment: ExerciseEquipment,
        unit: WeightUnit,
        barKg: Double,
        barLb: Double
    ) -> Double {
        switch equipment {
        case .barbell:
            if unit == .kg {
                return barKg > 0 ? barKg : defaultBarKg
            }
            return barLb > 0 ? barLb : defaultBarLb
        case .machine, .functionalTrainer:
            return 0
        default:
            return 0
        }
    }
}
