import Foundation
import HealthKit
import Flutter

final class HealthKitHandler: NSObject {
  private let healthStore = HKHealthStore()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(FlutterError(
        code: "health_data_not_available",
        message: "HealthKit is not available on this device.",
        details: nil
      ))
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "querySteps":
      querySteps(args: args, result: result)
    case "queryHeartRate":
      queryHeartRate(args: args, result: result)
    case "querySleep":
      querySleep(args: args, result: result)
    case "queryEnergy":
      queryEnergy(args: args, result: result)
    case "queryBody":
      queryBody(args: args, result: result)
    case "queryNutrition":
      queryNutrition(args: args, result: result)
    case "logSample":
      logSample(args: args, result: result)
    case "getSummary":
      getSummary(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Types List

  private func readTypes() -> Set<HKObjectType> {
    var types: Set<HKObjectType> = []
    if let step = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(step) }
    if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
    if let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { types.insert(rhr) }
    if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
    if let basalEnergy = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) { types.insert(basalEnergy) }
    if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
    if let height = HKQuantityType.quantityType(forIdentifier: .height) { types.insert(height) }
    if let bmi = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) { types.insert(bmi) }
    if let cal = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) { types.insert(cal) }
    if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) { types.insert(water) }
    if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
    return types
  }

  private func writeTypes() -> Set<HKSampleType> {
    var types: Set<HKSampleType> = []
    if let step = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(step) }
    if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
    if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
    if let height = HKQuantityType.quantityType(forIdentifier: .height) { types.insert(height) }
    if let cal = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) { types.insert(cal) }
    if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) { types.insert(water) }
    return types
  }

  // MARK: - Permission

  private func requestPermission(result: @escaping FlutterResult) {
    healthStore.requestAuthorization(toShare: writeTypes(), read: readTypes()) { success, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil))
        } else {
          result(["authorized": success])
        }
      }
    }
  }

  // MARK: - Steps Query

  private func querySteps(args: [String: Any], result: @escaping FlutterResult) {
    let days = (args["days"] as? Int) ?? 7
    guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
      result(FlutterError(code: "type_error", message: "Step count type not available.", details: nil))
      return
    }

    let now = Date()
    let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)

    var interval = DateComponents()
    interval.day = 1

    let query = HKStatisticsCollectionQuery(
      quantityType: stepType,
      quantitySamplePredicate: predicate,
      options: .cumulativeSum,
      anchorDate: Calendar.current.startOfDay(for: now),
      intervalComponents: interval
    )

    query.initialResultsHandler = { _, results, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "query_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      var dailySteps = [[String: Any]]()
      var totalSteps: Double = 0
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"

      results?.enumerateStatistics(from: startDate, to: now) { statistics, _ in
        if let sum = statistics.sumQuantity() {
          let count = sum.doubleValue(for: HKUnit.count())
          totalSteps += count
          dailySteps.append([
            "date": formatter.string(from: statistics.startDate),
            "steps": Int(count)
          ])
        }
      }

      DispatchQueue.main.async {
        result([
          "total_steps": Int(totalSteps),
          "days": dailySteps,
          "period_days": days
        ])
      }
    }
    healthStore.execute(query)
  }

  // MARK: - Heart Rate Query

  private func queryHeartRate(args: [String: Any], result: @escaping FlutterResult) {
    let limit = (args["limit"] as? Int) ?? 20
    guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
      result(FlutterError(code: "type_error", message: "Heart rate type not available.", details: nil))
      return
    }

    let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
    let query = HKSampleQuery(sampleType: hrType, predicate: nil, limit: limit, sortDescriptors: [sortDescriptor]) { _, samples, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "query_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      let hrUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
      let isoFormatter = ISO8601DateFormatter()
      var items = [[String: Any]]()
      var totalBpm: Double = 0

      for sample in (samples as? [HKQuantitySample]) ?? [] {
        let bpm = sample.quantity.doubleValue(for: hrUnit)
        totalBpm += bpm
        items.append([
          "bpm": Int(bpm.rounded()),
          "date": isoFormatter.string(from: sample.startDate)
        ])
      }

      let avgBpm = items.isEmpty ? 0 : Int((totalBpm / Double(items.count)).rounded())

      DispatchQueue.main.async {
        result([
          "average_bpm": avgBpm,
          "latest_bpm": items.first?["bpm"] ?? NSNull(),
          "samples": items
        ])
      }
    }
    healthStore.execute(query)
  }

  // MARK: - Sleep Query

  private func querySleep(args: [String: Any], result: @escaping FlutterResult) {
    let days = (args["days"] as? Int) ?? 7
    guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
      result(FlutterError(code: "type_error", message: "Sleep analysis type not available.", details: nil))
      return
    }

    let now = Date()
    let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
    let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

    let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 100, sortDescriptors: [sortDescriptor]) { _, samples, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "query_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      let isoFormatter = ISO8601DateFormatter()
      var items = [[String: Any]]()
      var totalSleepSeconds: TimeInterval = 0

      for sample in (samples as? [HKCategorySample]) ?? [] {
        let duration = sample.endDate.timeIntervalSince(sample.startDate)
        totalSleepSeconds += duration

        let valueString: String
        if #available(iOS 16.0, *) {
          switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
          case .asleepDeep: valueString = "deep"
          case .asleepREM: valueString = "rem"
          case .asleepCore: valueString = "core"
          case .awake: valueString = "awake"
          case .asleepUnspecified: valueString = "asleep"
          default: valueString = "asleep"
          }
        } else {
          valueString = sample.value == HKCategoryValueSleepAnalysis.awake.rawValue ? "awake" : "asleep"
        }

        items.append([
          "type": valueString,
          "duration_minutes": Int(duration / 60.0),
          "start": isoFormatter.string(from: sample.startDate),
          "end": isoFormatter.string(from: sample.endDate)
        ])
      }

      let totalHours = (totalSleepSeconds / 3600.0 * 10.0).rounded() / 10.0

      DispatchQueue.main.async {
        result([
          "total_sleep_hours": totalHours,
          "segments": items
        ])
      }
    }
    healthStore.execute(query)
  }

  // MARK: - Energy Query

  private func queryEnergy(args: [String: Any], result: @escaping FlutterResult) {
    let now = Date()
    let startOfDay = Calendar.current.startOfDay(for: now)
    let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

    guard let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
          let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else {
      result(FlutterError(code: "type_error", message: "Energy types not available.", details: nil))
      return
    }

    let group = DispatchGroup()
    var activeKcal: Double = 0
    var basalKcal: Double = 0

    group.enter()
    let activeQuery = HKStatisticsQuery(quantityType: activeType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
      if let sum = stats?.sumQuantity() {
        activeKcal = sum.doubleValue(for: HKUnit.kilocalorie())
      }
      group.leave()
    }
    healthStore.execute(activeQuery)

    group.enter()
    let basalQuery = HKStatisticsQuery(quantityType: basalType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
      if let sum = stats?.sumQuantity() {
        basalKcal = sum.doubleValue(for: HKUnit.kilocalorie())
      }
      group.leave()
    }
    healthStore.execute(basalQuery)

    group.notify(queue: .main) {
      result([
        "active_energy_kcal": Int(activeKcal.rounded()),
        "basal_energy_kcal": Int(basalKcal.rounded()),
        "total_energy_kcal": Int((activeKcal + basalKcal).rounded())
      ])
    }
  }

  // MARK: - Body Query

  private func queryBody(args: [String: Any], result: @escaping FlutterResult) {
    guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass),
          let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
      result(FlutterError(code: "type_error", message: "Body types not available.", details: nil))
      return
    }

    let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
    let group = DispatchGroup()

    var weightKg: Double?
    var heightCm: Double?

    group.enter()
    let weightQuery = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
      if let sample = (samples as? [HKQuantitySample])?.first {
        weightKg = (sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)) * 10.0).rounded() / 10.0
      }
      group.leave()
    }
    healthStore.execute(weightQuery)

    group.enter()
    let heightQuery = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
      if let sample = (samples as? [HKQuantitySample])?.first {
        heightCm = (sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi)) * 10.0).rounded() / 10.0
      }
      group.leave()
    }
    healthStore.execute(heightQuery)

    group.notify(queue: .main) {
      var bmi: Double?
      if let w = weightKg, let h = heightCm, h > 0 {
        let hMeter = h / 100.0
        bmi = (w / (hMeter * hMeter) * 10.0).rounded() / 10.0
      }

      result([
        "weight_kg": weightKg.map { $0 as Any } ?? NSNull(),
        "height_cm": heightCm.map { $0 as Any } ?? NSNull(),
        "bmi": bmi.map { $0 as Any } ?? NSNull()
      ])
    }
  }

  // MARK: - Nutrition Query

  private func queryNutrition(args: [String: Any], result: @escaping FlutterResult) {
    let now = Date()
    let startOfDay = Calendar.current.startOfDay(for: now)
    let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

    guard let calType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
          let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
      result(FlutterError(code: "type_error", message: "Nutrition types not available.", details: nil))
      return
    }

    let group = DispatchGroup()
    var calories: Double = 0
    var waterMl: Double = 0

    group.enter()
    let calQuery = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
      if let sum = stats?.sumQuantity() {
        calories = sum.doubleValue(for: HKUnit.kilocalorie())
      }
      group.leave()
    }
    healthStore.execute(calQuery)

    group.enter()
    let waterQuery = HKStatisticsQuery(quantityType: waterType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
      if let sum = stats?.sumQuantity() {
        waterMl = sum.doubleValue(for: HKUnit.literUnit(with: .milli))
      }
      group.leave()
    }
    healthStore.execute(waterQuery)

    group.notify(queue: .main) {
      result([
        "dietary_calories_kcal": Int(calories.rounded()),
        "dietary_water_ml": Int(waterMl.rounded())
      ])
    }
  }

  // MARK: - Log Sample

  private func logSample(args: [String: Any], result: @escaping FlutterResult) {
    guard let typeName = args["type"] as? String,
          let value = (args["value"] as? NSNumber)?.doubleValue else {
      result(FlutterError(code: "invalid_args", message: "Parameters 'type' and 'value' are required.", details: nil))
      return
    }

    let now = Date()
    let sample: HKQuantitySample?

    switch typeName.lowercased() {
    case "steps":
      if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
        let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: value)
        sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
      } else { sample = nil }

    case "weight":
      if let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
        let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: value)
        sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
      } else { sample = nil }

    case "water":
      if let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: value)
        sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
      } else { sample = nil }

    case "heart_rate":
      if let type = HKQuantityType.quantityType(forIdentifier: .heartRate) {
        let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: value)
        sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
      } else { sample = nil }

    case "calories":
      if let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: value)
        sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
      } else { sample = nil }

    default:
      result(FlutterError(code: "unsupported_type", message: "Type '\(typeName)' is not supported. Supported: steps, weight, water, heart_rate, calories.", details: nil))
      return
    }

    guard let sampleToSave = sample else {
      result(FlutterError(code: "sample_creation_failed", message: "Failed to create sample.", details: nil))
      return
    }

    healthStore.save(sampleToSave) { success, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
        } else {
          result([
            "success": true,
            "type": typeName,
            "value": value,
            "message": "Health sample saved to HealthKit."
          ])
        }
      }
    }
  }

  // MARK: - Summary Aggregate

  private func getSummary(args: [String: Any], result: @escaping FlutterResult) {
    let group = DispatchGroup()
    var summaryData = [String: Any]()

    // Steps
    group.enter()
    querySteps(args: ["days": 1]) { res in
      if let dict = res as? [String: Any] {
        summaryData["today_steps"] = dict["total_steps"] ?? 0
      }
      group.leave()
    }

    // Heart rate
    group.enter()
    queryHeartRate(args: ["limit": 5]) { res in
      if let dict = res as? [String: Any] {
        summaryData["latest_heart_rate"] = dict["latest_bpm"] ?? NSNull()
      }
      group.leave()
    }

    // Energy
    group.enter()
    queryEnergy(args: [:]) { res in
      if let dict = res as? [String: Any] {
        summaryData["active_energy_kcal"] = dict["active_energy_kcal"] ?? 0
        summaryData["total_energy_kcal"] = dict["total_energy_kcal"] ?? 0
      }
      group.leave()
    }

    // Body
    group.enter()
    queryBody(args: [:]) { res in
      if let dict = res as? [String: Any] {
        summaryData["weight_kg"] = dict["weight_kg"] ?? NSNull()
        summaryData["bmi"] = dict["bmi"] ?? NSNull()
      }
      group.leave()
    }

    group.notify(queue: .main) {
      result([
        "success": true,
        "summary": summaryData
      ])
    }
  }
}
