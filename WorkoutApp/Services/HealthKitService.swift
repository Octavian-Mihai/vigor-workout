import Foundation
import HealthKit
import CoreLocation

struct CardioWorkout: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let averageHeartRate: Double?
    let activityType: HKWorkoutActivityType
    let elevationGainMeters: Double?
    let isIndoor: Bool
    let workout: HKWorkout

    var distanceKilometers: Double { distanceMeters / 1000.0 }

    var sportLabel: String {
        switch activityType {
        case .running: return isIndoor ? "Indoor Run" : "Outdoor Run"
        case .cycling: return isIndoor ? "Indoor Cycling" : "Outdoor Cycling"
        case .walking: return isIndoor ? "Indoor Walk" : "Outdoor Walk"
        case .hiking: return "Hike"
        default: return "Workout"
        }
    }

    var paceMinPerKm: Double? {
        guard distanceKilometers > 0, duration > 0 else { return nil }
        return (duration / 60.0) / distanceKilometers
    }

    func stress(restingHeartRate: Double?, maxHeartRate: Double? = nil) -> Double {
        StressCalculator.runStress(
            duration: duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            elevationGainMeters: elevationGainMeters,
            activityType: activityType
        )
    }
}

struct HeartRateSample: Identifiable {
    let date: Date
    let bpm: Double
    var id: Date { date }
}

struct PaceSample: Identifiable {
    let date: Date
    let minutesPerKm: Double
    var id: Date { date }
}

struct RunDetailData {
    var heartRate: [HeartRateSample]
    var pace: [PaceSample]
    var route: [CLLocation]
}

struct DailySteps: Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

@MainActor
final class HealthKitService: ObservableObject {
    /// Opt-in: when true, finishing a strength session writes an `HKWorkout` to Health.
    static let writeStrengthToHealthKitKey = "writeStrengthToHealthKit"

    static let recentCardioInterval: TimeInterval = 14 * 86_400

    @Published var isAuthorized = false
    @Published var cardioWorkouts: [CardioWorkout] = []
    @Published var olderCardioWorkouts: [CardioWorkout] = []
    @Published var olderCardioSessionCount = 0
    @Published var runDays: Set<Date> = []
    @Published var lastError: String?
    @Published var isLoading = false
    @Published var isLoadingOlder = false
    @Published var restingHeartRate: Double?
    @Published var hrvSDNN: Double?
    @Published var lastNightSleepHours: Double?
    /// Per-day history used by the daily check-in insights (keyed by start of day).
    @Published var dailyHRV: [Date: Double] = [:]
    @Published var dailyRestingHR: [Date: Double] = [:]
    @Published var dailySleepHours: [Date: Double] = [:]
    @Published var dailySteps: [DailySteps] = []
    @Published var isLoadingSteps = false
    @Published var stepsError: String?
    @Published var dateOfBirth: Date?

    private let store = HKHealthStore()
    private var hasLoadedOlder = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static var recentCardioCutoff: Date {
        Date().addingTimeInterval(-recentCardioInterval)
    }

    static var currentYearStart: Date {
        let cal = Calendar.current
        let now = Date()
        return cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
    }

    /// Recent running and cycling (indoor and outdoor) plus older sessions once that folder has been loaded.
    var cardioSessions: [CardioWorkout] {
        var seen = Set<UUID>()
        var result: [CardioWorkout] = []
        for workout in cardioWorkouts + olderCardioWorkouts {
            guard workout.activityType == .running || workout.activityType == .cycling,
                  seen.insert(workout.id).inserted else { continue }
            result.append(workout)
        }
        return result.sorted { $0.start > $1.start }
    }

    var maxHeartRate: Double {
        StressCalculator.estimatedMaxHeartRate(dateOfBirth: dateOfBirth)
    }

    var activityRunDays: Set<Date> {
        var days = runDays
        let cal = Calendar.current
        for workout in cardioWorkouts where workout.activityType != .walking {
            days.insert(cal.startOfDay(for: workout.start))
        }
        return days
    }

    func requestAndLoad() async {
        guard isAvailable else {
            lastError = "Health data is not available on this device."
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await requestAuthorization()
            isAuthorized = true
            loadDateOfBirth()
            try await loadCardioWorkouts()
            try await loadRunDays()
            try await loadOlderCardioSessionCount()
            try await loadRestingHeartRate()
            try await loadHRV()
            try? await loadSleep()
            await loadRecoveryHistory()
            await loadDailyStepsIfPossible()
        } catch {
            lastError = error.localizedDescription
            await loadDailyStepsIfPossible()
        }
    }

    func loadDailyStepsIfPossible() async {
        do {
            try await loadDailySteps()
        } catch {
            stepsError = error.localizedDescription
        }
    }

    func requestAuthorization() async throws {
        guard let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
              let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let stepCount = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitServiceError.missingTypes
        }

        let workoutType = HKObjectType.workoutType()
        let read: Set<HKObjectType> = [
            workoutType,
            distance,
            heartRate,
            restingHR,
            hrv,
            stepCount,
            sleep,
            HKSeriesType.workoutRoute(),
            bodyMass
        ]
        try await store.requestAuthorization(toShare: [bodyMass, workoutType], read: read)
    }

    /// Saves a finished in-app strength session as Traditional Strength Training.
    /// Failures are recorded on `lastError` and do not throw.
    func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) async {
        guard isAvailable else { return }
        let safeEnd = end > start ? end : start.addingTimeInterval(1)
        if await strengthWorkoutExists(sessionUUID: sessionUUID) {
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Workout"
        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: appName,
            HKMetadataKeyExternalUUID: sessionUUID.uuidString
        ]

        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: safeEnd)
            guard try await builder.finishWorkout() != nil else {
                lastError = "Could not save the strength workout to Apple Health."
                return
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func strengthWorkoutExists(sessionUUID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                allowedValues: [sessionUUID.uuidString]
            )
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(query)
        }
    }

    private func loadDateOfBirth() {
        if let components = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: components) {
            dateOfBirth = date
        }
    }

    func loadRunDays() async throws {
        let cal = Calendar.current
        let dates = HKQuery.predicateForSamples(
            withStart: Self.currentYearStart,
            end: Date(),
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [activityDayPredicate, dates])
        let workouts = try await fetchWorkouts(predicate: predicate)
        runDays = Set(workouts.map { cal.startOfDay(for: $0.startDate) })
    }

    func fetchBodyMass(limit: Int = 100) async throws -> [(date: Date, kilograms: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitServiceError.missingTypes
        }
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = HKUnit.gramUnit(with: .kilo)
                let result = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, kilograms: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    func saveBodyMass(kilograms: Double, date: Date) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        do {
            try await store.save(sample)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadCardioWorkouts(limit: Int = HKObjectQueryNoLimit) async throws {
        let dates = HKQuery.predicateForSamples(
            withStart: Self.recentCardioCutoff,
            end: Date(),
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [cardioActivityPredicate, dates])
        let workouts = try await fetchWorkouts(predicate: predicate, limit: limit)
        cardioWorkouts = await mapCardioWorkouts(workouts)
    }

    /// Cheap count of older running/cycling workouts (no route walk) so the folder can show N before expand.
    func loadOlderCardioSessionCount() async throws {
        let running = HKQuery.predicateForWorkouts(with: .running)
        let cycling = HKQuery.predicateForWorkouts(with: .cycling)
        let sport = NSCompoundPredicate(orPredicateWithSubpredicates: [running, cycling])
        let dates = HKQuery.predicateForSamples(
            withStart: nil,
            end: Self.recentCardioCutoff,
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [sport, dates])
        let workouts = try await fetchWorkouts(predicate: predicate)
        olderCardioSessionCount = workouts.count
    }

    /// Full older cardio (same activity types, start before the 14-day cutoff), including elevation.
    func loadOlderCardioWorkouts() async {
        guard isAvailable, !hasLoadedOlder, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let dates = HKQuery.predicateForSamples(
                withStart: nil,
                end: Self.recentCardioCutoff,
                options: .strictStartDate
            )
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [cardioActivityPredicate, dates])
            let workouts = try await fetchWorkouts(predicate: predicate)
            olderCardioWorkouts = await mapCardioWorkouts(workouts)
            olderCardioSessionCount = olderCardioWorkouts.filter {
                $0.activityType == .running || $0.activityType == .cycling
            }.count
            hasLoadedOlder = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadRestingHeartRate() async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 7,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else {
            restingHeartRate = nil
            return
        }
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        restingHeartRate = values.reduce(0, +) / Double(values.count)
    }

    func loadHRV() async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let unit = HKUnit.secondUnit(with: .milli)
        let cutoff = Date().addingTimeInterval(-3 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date(), options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else {
            hrvSDNN = nil
            return
        }

        let cal = Calendar.current
        var daily: [Date: [Double]] = [:]
        for sample in samples {
            let day = cal.startOfDay(for: sample.startDate)
            daily[day, default: []].append(sample.quantity.doubleValue(for: unit))
        }
        let sortedDays = daily.keys.sorted(by: >)
        if let latestDay = sortedDays.first, let values = daily[latestDay], !values.isEmpty {
            hrvSDNN = values.reduce(0, +) / Double(values.count)
        } else {
            hrvSDNN = nil
        }
    }

    func loadDailySteps(days: Int = 7) async throws {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            dailySteps = []
            stepsError = "Step count is not available on this device."
            return
        }

        isLoadingSteps = true
        stepsError = nil
        defer { isLoadingSteps = false }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart),
              let endDate = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            dailySteps = []
            return
        }

        dailySteps = try await fetchDailyStepCounts(
            type: stepType,
            from: startDate,
            to: endDate,
            anchorDate: startDate
        )
    }

    private func fetchDailyStepCounts(
        type: HKQuantityType,
        from startDate: Date,
        to endDate: Date,
        anchorDate: Date
    ) async throws -> [DailySteps] {
        try await withCheckedThrowingContinuation { continuation in
            var interval = DateComponents()
            interval.day = 1

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var results: [DailySteps] = []
                collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    results.append(DailySteps(date: statistics.startDate, count: Int(steps.rounded())))
                }
                continuation.resume(returning: results)
            }

            store.execute(query)
        }
    }

    /// Daily HRV, resting heart rate and hours asleep for roughly the last `days` days.
    func loadRecoveryHistory(days: Int = 90) async {
        async let hrv = try? dailyAverages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: days)
        async let resting = try? dailyAverages(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: days)
        async let sleep = try? dailyAsleepHours(days: days)
        dailyHRV = await hrv ?? [:]
        dailyRestingHR = await resting ?? [:]
        dailySleepHours = await sleep ?? [:]
    }

    private func dailyAverages(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: todayStart),
              let end = cal.date(byAdding: .day, value: 1, to: todayStart) else { return [:] }

        return try await withCheckedThrowingContinuation { continuation in
            var interval = DateComponents()
            interval.day = 1
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let value = statistics.averageQuantity()?.doubleValue(for: unit) {
                        result[cal.startOfDay(for: statistics.startDate)] = value
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// Hours asleep per night, credited to the day the person woke up. Days with under two hours
    /// (a nap) are left out.
    private func dailyAsleepHours(days: Int) async throws -> [Date: Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        var seconds: [Date: Double] = [:]
        for sample in samples where asleep.contains(sample.value) {
            seconds[cal.startOfDay(for: sample.endDate), default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }
        return seconds.compactMapValues { $0 >= 2 * 3600 ? $0 / 3600 : nil }
    }

    func loadSleep() async throws {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart),
              let searchStart = cal.date(bySettingHour: 18, minute: 0, second: 0, of: yesterdayStart) else {
            lastNightSleepHours = nil
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: Date(), options: .strictStartDate)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        var totalSeconds = 0.0
        for sample in samples where asleepValues.contains(sample.value) {
            totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
        }
        lastNightSleepHours = totalSeconds > 0 ? totalSeconds / 3600.0 : nil
    }

    func loadDetails(for run: CardioWorkout) async -> RunDetailData {
        async let heart = heartRateSeries(for: run.workout)
        async let distance = distanceSeries(for: run.workout)
        async let route = routeLocations(for: run.workout)
        let (hr, dist, locations) = await (heart, distance, route)
        return RunDetailData(
            heartRate: hr,
            pace: paceSeries(from: dist),
            route: locations
        )
    }

    /// Every kind of cardio that should light up a day on the activity grid and widgets.
    private var activityDayPredicate: NSPredicate {
        let activityTypes: [HKWorkoutActivityType] = [
            .running, .cycling, .hiking, .swimming, .rowing, .elliptical,
            .stairClimbing, .highIntensityIntervalTraining, .mixedCardio, .jumpRope,
            .cardioDance, .handCycling, .crossCountrySkiing, .paddleSports, .stepTraining
        ]
        let typePredicates = activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        return NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
    }

    private var cardioActivityPredicate: NSPredicate {
        let activityTypes: [HKWorkoutActivityType] = [.running, .walking, .hiking, .cycling]
        let typePredicates = activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        return NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
    }

    private func fetchWorkouts(predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private func mapCardioWorkouts(_ workouts: [HKWorkout]) async -> [CardioWorkout] {
        var results: [CardioWorkout] = []
        for workout in workouts {
            var elevation = elevationFromMetadata(workout)
            if elevation == nil {
                elevation = await elevationFromRoute(workout)
            }
            let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
            results.append(CardioWorkout(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                duration: workout.duration,
                distanceMeters: distance,
                averageHeartRate: averageHeartRate(from: workout),
                activityType: dominantActivityType(for: workout),
                elevationGainMeters: elevation,
                isIndoor: (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false,
                workout: workout
            ))
        }
        return results
    }

    /// Some sessions (auto-detected run/walk intervals, warm-up segments, etc.) are recorded as a
    /// multi-segment `HKWorkout`. The legacy `workoutActivityType` only reflects the first segment,
    /// which can disagree with what Health displays as the workout's overall type. Prefer the segment
    /// that covers the most time when segment data is available.
    private func dominantActivityType(for workout: HKWorkout) -> HKWorkoutActivityType {
        let activities = workout.workoutActivities
        guard !activities.isEmpty else { return workout.workoutActivityType }
        let dominant = activities.max { $0.duration < $1.duration }
        return dominant?.workoutConfiguration.activityType ?? workout.workoutActivityType
    }

    private func elevationFromMetadata(_ workout: HKWorkout) -> Double? {
        guard let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity else { return nil }
        let meters = quantity.doubleValue(for: .meter())
        return meters > 0 ? meters : nil
    }

    private func elevationFromRoute(_ workout: HKWorkout) async -> Double? {
        let locations = await routeLocations(for: workout)
        return Self.elevationGain(from: locations)
    }

    static func elevationGain(from locations: [CLLocation]) -> Double? {
        guard locations.count >= 2 else { return nil }
        var gain = 0.0
        for index in 1..<locations.count {
            let delta = locations[index].altitude - locations[index - 1].altitude
            if delta > 0 { gain += delta }
        }
        return gain > 0 ? gain : nil
    }

    private func averageHeartRate(from workout: HKWorkout) -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let stats = workout.statistics(for: hrType)
        return stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    private func heartRateSeries(for workout: HKWorkout) async -> [HeartRateSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = await quantitySamples(type: type, workout: workout)
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return HeartRateSample(date: quantity.startDate, bpm: quantity.quantity.doubleValue(for: unit))
        }
    }

    private func distanceSeries(for workout: HKWorkout) async -> [(Date, Double)] {
        let type: HKQuantityType?
        switch workout.workoutActivityType {
        case .cycling:
            type = HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        default:
            type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        }
        guard let type else { return [] }
        let samples = await quantitySamples(type: type, workout: workout)
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return (quantity.endDate, quantity.quantity.doubleValue(for: .meter()))
        }
    }

    private func paceSeries(from distanceSamples: [(Date, Double)]) -> [PaceSample] {
        guard distanceSamples.count >= 2 else { return [] }
        var points: [PaceSample] = []
        var cumulative = 0.0
        var previousDate: Date?
        var previousCumulative = 0.0
        let looksIncremental = distanceSamples.allSatisfy { $0.1 < 2000 } && (distanceSamples.last?.1 ?? 0) < 50_000

        for (date, meters) in distanceSamples {
            if looksIncremental {
                cumulative += meters
            } else {
                cumulative = meters
            }
            if let previousDate {
                let dt = date.timeIntervalSince(previousDate)
                let dd = cumulative - previousCumulative
                if dt > 0, dd > 0 {
                    let minPerKm = (dt / 60.0) / (dd / 1000.0)
                    if minPerKm.isFinite, minPerKm > 2, minPerKm < 20 {
                        points.append(PaceSample(date: date, minutesPerKm: minPerKm))
                    }
                }
            }
            previousDate = date
            previousCumulative = cumulative
        }
        return points
    }

    private func quantitySamples(type: HKQuantityType, workout: HKWorkout) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private func routeLocations(for workout: HKWorkout) async -> [CLLocation] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        guard let route = routes.first else { return [] }

        return await withCheckedContinuation { continuation in
            var all: [CLLocation] = []
            var finished = false
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if error != nil {
                    if !finished {
                        finished = true
                        continuation.resume(returning: all)
                    }
                    return
                }
                if let locations {
                    all.append(contentsOf: locations)
                }
                if done, !finished {
                    finished = true
                    continuation.resume(returning: all)
                }
            }
            store.execute(query)
        }
    }
}

enum HealthKitServiceError: LocalizedError {
    case missingTypes

    var errorDescription: String? {
        "Could not read Health types for cardio workouts or body weight."
    }
}
