import Foundation
import UIKit
import Flutter

final class DeviceInfoHandler: NSObject {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getInfo":
      getInfo(result: result)
    case "getBattery":
      getBattery(result: result)
    case "getStorage":
      getStorage(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Battery Data

  private func getBatteryData() -> [String: Any] {
    let dev = UIDevice.current
    let wasEnabled = dev.isBatteryMonitoringEnabled
    dev.isBatteryMonitoringEnabled = true

    let level = dev.batteryLevel
    let state = dev.batteryState

    if !wasEnabled {
      dev.isBatteryMonitoringEnabled = false
    }

    let stateString: String
    switch state {
    case .unplugged: stateString = "unplugged"
    case .charging: stateString = "charging"
    case .full: stateString = "full"
    case .unknown: stateString = "unknown"
    @unknown default: stateString = "unknown"
    }

    let levelPercent: Int? = level >= 0 ? Int(round(level * 100)) : nil

    return [
      "level": level >= 0 ? level : NSNull(),
      "level_percent": levelPercent ?? NSNull(),
      "state": stateString,
      "monitoring_enabled": true
    ]
  }

  private func getBattery(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      result(self.getBatteryData())
    }
  }

  // MARK: - Storage Data

  private func getStorageData() -> [String: Any] {
    let homeDir = NSHomeDirectory()
    do {
      let attrs = try NSFileManager.default.attributesOfFileSystem(forPath: homeDir)
      let totalBytes = (attrs[.systemSize] as? NSNumber)?.uint64Value ?? 0
      let freeBytes = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
      let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0

      let totalGb = (Double(totalBytes) / (1024.0 * 1024.0 * 1024.0) * 10.0).rounded() / 10.0
      let freeGb = (Double(freeBytes) / (1024.0 * 1024.0 * 1024.0) * 10.0).rounded() / 10.0
      let usedGb = (Double(usedBytes) / (1024.0 * 1024.0 * 1024.0) * 10.0).rounded() / 10.0
      let usagePercent = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes) * 100.0 * 10.0).rounded() / 10.0 : 0.0

      return [
        "total_bytes": totalBytes,
        "free_bytes": freeBytes,
        "used_bytes": usedBytes,
        "total_gb": totalGb,
        "free_gb": freeGb,
        "used_gb": usedGb,
        "usage_percent": usagePercent
      ]
    } catch {
      return ["error": error.localizedDescription]
    }
  }

  private func getStorage(result: @escaping FlutterResult) {
    result(getStorageData())
  }

  // MARK: - Full Device Info

  private func getInfo(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let dev = UIDevice.current

      let machine = self.sysctlMachine()
      let pi = ProcessInfo.processInfo

      let thermalStateStr: String
      switch pi.thermalState {
      case .nominal: thermalStateStr = "nominal"
      case .fair: thermalStateStr = "fair"
      case .serious: thermalStateStr = "serious"
      case .critical: thermalStateStr = "critical"
      @unknown default: thermalStateStr = "unknown"
      }

      let physMem = pi.physicalMemory
      let physMemGb = (Double(physMem) / (1024.0 * 1024.0 * 1024.0) * 10.0).rounded() / 10.0

      let data: [String: Any] = [
        "name": dev.name,
        "system_name": dev.systemName,
        "system_version": dev.systemVersion,
        "model": dev.model,
        "localized_model": dev.localizedModel,
        "machine": machine,
        "user_interface_idiom": dev.userInterfaceIdiom == .pad ? "pad" : "phone",
        "processor_count": pi.processorCount,
        "active_processor_count": pi.activeProcessorCount,
        "physical_memory_gb": physMemGb,
        "thermal_state": thermalStateStr,
        "is_low_power_mode": pi.isLowPowerModeEnabled,
        "uptime_seconds": Int(pi.systemUptime),
        "battery": self.getBatteryData(),
        "storage": self.getStorageData()
      ]

      result(data)
    }
  }

  // MARK: - Machine Identifier (sysctl)

  private func sysctlMachine() -> String {
    var size: Int = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
  }
}
