import Foundation
import CoreBluetooth
import Flutter

final class BleBridgeHandler: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private var _centralManager: CBCentralManager?

  private var centralManager: CBCentralManager {
    if let manager = _centralManager {
      return manager
    }
    let manager = CBCentralManager(delegate: self, queue: nil, options: [
      CBCentralManagerOptionShowPowerAlertKey: false
    ])
    _centralManager = manager
    return manager
  }

  private var discoveredPeripherals = [String: CBPeripheral]()
  private var connectedPeripherals = [String: CBPeripheral]()
  private var scanResults = [[String: Any]]()

  // Semaphores / callbacks for sync/async operations
  private var pendingResult: FlutterResult?
  private var pendingOperation: String?

  // Current active read/write/discover targets
  private var targetPeripheralUuid: String?
  private var targetServiceUuid: String?
  private var targetCharacteristicUuid: String?
  private var writeValueHex: String?
  private var writeValueData: Data?

  // Read response
  private var lastReadData: Data?

  override init() {
    super.init()
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getStatus":
      getStatus(result: result)
    case "scan":
      scan(args: args, result: result)
    case "connect":
      connect(args: args, result: result)
    case "disconnect":
      disconnect(args: args, result: result)
    case "discoverServices":
      discoverServices(args: args, result: result)
    case "read":
      readCharacteristic(args: args, result: result)
    case "write":
      writeCharacteristic(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    // Bluetooth state updated
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let uuid = peripheral.identifier.uuidString
    discoveredPeripherals[uuid] = peripheral

    let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
    var serviceUuids = [String]()
    if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
      serviceUuids = uuids.map { $0.uuidString }
    }

    let isConnectable = advertisementData["kCBAdvDataIsConnectable"] as? Bool ?? true

    // Check if already in scanResults
    if let index = scanResults.firstIndex(where: { ($0["uuid"] as? String) == uuid }) {
      scanResults[index] = [
        "name": name,
        "uuid": uuid,
        "rssi": RSSI.intValue,
        "connectable": isConnectable,
        "service_uuids": serviceUuids
      ]
    } else {
      scanResults.append([
        "name": name,
        "uuid": uuid,
        "rssi": RSSI.intValue,
        "connectable": isConnectable,
        "service_uuids": serviceUuids
      ])
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    let uuid = peripheral.identifier.uuidString
    connectedPeripherals[uuid] = peripheral
    peripheral.delegate = self

    if pendingOperation == "connect" && targetPeripheralUuid == uuid {
      pendingResult?(["success": true, "uuid": uuid, "name": peripheral.name ?? "Unknown"])
      clearPending()
    }
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    if pendingOperation == "connect" && targetPeripheralUuid == peripheral.identifier.uuidString {
      pendingResult?(FlutterError(
        code: "connection_failed",
        message: error?.localizedDescription ?? "Failed to connect to peripheral.",
        details: nil
      ))
      clearPending()
    }
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    let uuid = peripheral.identifier.uuidString
    connectedPeripherals.removeValue(forKey: uuid)

    if pendingOperation == "disconnect" && targetPeripheralUuid == uuid {
      pendingResult?(["success": true, "uuid": uuid])
      clearPending()
    }
  }

  // MARK: - CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil else {
      if pendingOperation == "discoverServices" {
        pendingResult?(FlutterError(code: "discover_failed", message: error!.localizedDescription, details: nil))
        clearPending()
      }
      return
    }

    guard let services = peripheral.services, !services.isEmpty else {
      if pendingOperation == "discoverServices" {
        pendingResult?(["services": []])
        clearPending()
      }
      return
    }

    // Discover characteristics for all services
    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard pendingOperation == "discoverServices" else { return }

    // Check if all services have had characteristics discovered
    let services = peripheral.services ?? []
    let allDiscovered = services.allSatisfy { $0.characteristics != nil }

    if allDiscovered {
      var resultServices = [[String: Any]]()
      for s in services {
        var chars = [[String: Any]]()
        for c in s.characteristics ?? [] {
          var props = [String]()
          if c.properties.contains(.read) { props.append("read") }
          if c.properties.contains(.write) { props.append("write") }
          if c.properties.contains(.writeWithoutResponse) { props.append("writeWithoutResponse") }
          if c.properties.contains(.notify) { props.append("notify") }
          if c.properties.contains(.indicate) { props.append("indicate") }

          chars.append([
            "uuid": c.uuid.uuidString,
            "properties": props
          ])
        }
        resultServices.append([
          "uuid": s.uuid.uuidString,
          "is_primary": s.isPrimary,
          "characteristics": chars
        ])
      }
      pendingResult?(["services": resultServices])
      clearPending()
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error = error {
      if pendingOperation == "read" {
        pendingResult?(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
        clearPending()
      }
      return
    }

    if pendingOperation == "read" {
      let data = characteristic.value ?? Data()
      let hex = data.map { String(format: "%02hhx", $0) }.joined()
      lastReadData = data
      pendingResult?([
        "success": true,
        "uuid": characteristic.uuid.uuidString,
        "hex": hex,
        "utf8": String(data: data, encoding: .utf8) ?? ""
      ])
      clearPending()
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if pendingOperation == "write" {
      if let error = error {
        pendingResult?(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
      } else {
        pendingResult?([
          "success": true,
          "uuid": characteristic.uuid.uuidString,
          "message": "Write operation completed successfully."
        ])
      }
      clearPending()
    }
  }

  // MARK: - Method Implementations

  private func getStatus(result: @escaping FlutterResult) {
    let stateString: String
    switch centralManager.state {
    case .poweredOn: stateString = "poweredOn"
    case .poweredOff: stateString = "poweredOff"
    case .resetting: stateString = "resetting"
    case .unauthorized: stateString = "unauthorized"
    case .unsupported: stateString = "unsupported"
    case .unknown: stateString = "unknown"
    @unknown default: stateString = "unknown"
    }

    result([
      "state": stateString,
      "is_powered_on": centralManager.state == .poweredOn
    ])
  }

  private func scan(args: [String: Any], result: @escaping FlutterResult) {
    guard centralManager.state == .poweredOn else {
      result(FlutterError(code: "bluetooth_off", message: "Bluetooth is not powered on (state: \(centralManager.state.rawValue)).", details: nil))
      return
    }

    let duration = (args["duration_seconds"] as? Double) ?? 5.0
    scanResults.removeAll()

    centralManager.scanForPeripherals(withServices: nil, options: [
      CBCentralManagerScanOptionAllowDuplicatesKey: false
    ])

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
      guard let self = self else { return }
      self.centralManager.stopScan()
      result([
        "devices": self.scanResults,
        "count": self.scanResults.count,
        "duration_seconds": duration
      ])
    }
  }

  private func connect(args: [String: Any], result: @escaping FlutterResult) {
    guard let uuid = args["uuid"] as? String, !uuid.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'uuid' is required.", details: nil))
      return
    }

    guard let peripheral = discoveredPeripherals[uuid] ?? connectedPeripherals[uuid] else {
      result(FlutterError(code: "device_not_found", message: "Peripheral with UUID '\(uuid)' not found. Run 'scan' first.", details: nil))
      return
    }

    if peripheral.state == .connected {
      result(["success": true, "uuid": uuid, "name": peripheral.name ?? "Unknown", "message": "Already connected."])
      return
    }

    pendingResult = result
    pendingOperation = "connect"
    targetPeripheralUuid = uuid

    centralManager.connect(peripheral, options: nil)

    // Timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
      guard let self = self else { return }
      if self.pendingOperation == "connect" && self.targetPeripheralUuid == uuid {
        self.pendingResult?(FlutterError(code: "timeout", message: "Connection to peripheral timed out.", details: nil))
        self.clearPending()
      }
    }
  }

  private func disconnect(args: [String: Any], result: @escaping FlutterResult) {
    guard let uuid = args["uuid"] as? String, !uuid.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'uuid' is required.", details: nil))
      return
    }

    guard let peripheral = connectedPeripherals[uuid] else {
      result(FlutterError(code: "device_not_connected", message: "Peripheral with UUID '\(uuid)' is not connected.", details: nil))
      return
    }

    pendingResult = result
    pendingOperation = "disconnect"
    targetPeripheralUuid = uuid

    centralManager.cancelPeripheralConnection(peripheral)
  }

  private func discoverServices(args: [String: Any], result: @escaping FlutterResult) {
    guard let uuid = args["uuid"] as? String, !uuid.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'uuid' is required.", details: nil))
      return
    }

    guard let peripheral = connectedPeripherals[uuid] else {
      result(FlutterError(code: "device_not_connected", message: "Peripheral with UUID '\(uuid)' is not connected.", details: nil))
      return
    }

    pendingResult = result
    pendingOperation = "discoverServices"
    targetPeripheralUuid = uuid

    peripheral.discoverServices(nil)
  }

  private func readCharacteristic(args: [String: Any], result: @escaping FlutterResult) {
    guard let peripheralUuid = args["uuid"] as? String, !peripheralUuid.isEmpty,
          let serviceUuid = args["service_uuid"] as? String, !serviceUuid.isEmpty,
          let charUuid = args["characteristic_uuid"] as? String, !charUuid.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameters 'uuid', 'service_uuid', and 'characteristic_uuid' are required.", details: nil))
      return
    }

    guard let peripheral = connectedPeripherals[peripheralUuid] else {
      result(FlutterError(code: "device_not_connected", message: "Peripheral with UUID '\(peripheralUuid)' is not connected.", details: nil))
      return
    }

    guard let service = peripheral.services?.first(where: { $0.uuid.uuidString.lowercased() == serviceUuid.lowercased() }),
          let characteristic = service.characteristics?.first(where: { $0.uuid.uuidString.lowercased() == charUuid.lowercased() }) else {
      result(FlutterError(code: "characteristic_not_found", message: "Service or Characteristic not found on peripheral.", details: nil))
      return
    }

    pendingResult = result
    pendingOperation = "read"
    targetPeripheralUuid = peripheralUuid
    targetServiceUuid = serviceUuid
    targetCharacteristicUuid = charUuid

    peripheral.readValue(for: characteristic)
  }

  private func writeCharacteristic(args: [String: Any], result: @escaping FlutterResult) {
    guard let peripheralUuid = args["uuid"] as? String, !peripheralUuid.isEmpty,
          let serviceUuid = args["service_uuid"] as? String, !serviceUuid.isEmpty,
          let charUuid = args["characteristic_uuid"] as? String, !charUuid.isEmpty,
          let valueHex = args["value_hex"] as? String else {
      result(FlutterError(code: "invalid_args", message: "Parameters 'uuid', 'service_uuid', 'characteristic_uuid', and 'value_hex' are required.", details: nil))
      return
    }

    guard let peripheral = connectedPeripherals[peripheralUuid] else {
      result(FlutterError(code: "device_not_connected", message: "Peripheral with UUID '\(peripheralUuid)' is not connected.", details: nil))
      return
    }

    guard let service = peripheral.services?.first(where: { $0.uuid.uuidString.lowercased() == serviceUuid.lowercased() }),
          let characteristic = service.characteristics?.first(where: { $0.uuid.uuidString.lowercased() == charUuid.lowercased() }) else {
      result(FlutterError(code: "characteristic_not_found", message: "Service or Characteristic not found on peripheral.", details: nil))
      return
    }

    guard let data = hexStringToData(valueHex) else {
      result(FlutterError(code: "invalid_hex", message: "Failed to parse 'value_hex' into binary data.", details: nil))
      return
    }

    pendingResult = result
    pendingOperation = "write"
    targetPeripheralUuid = peripheralUuid
    targetServiceUuid = serviceUuid
    targetCharacteristicUuid = charUuid

    let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    peripheral.writeValue(data, for: characteristic, type: writeType)

    if writeType == .withoutResponse {
      result(["success": true, "uuid": charUuid, "message": "Write without response sent."])
      clearPending()
    }
  }

  // MARK: - Helpers

  private func clearPending() {
    pendingResult = nil
    pendingOperation = nil
    targetPeripheralUuid = nil
    targetServiceUuid = nil
    targetCharacteristicUuid = nil
    writeValueHex = nil
    writeValueData = nil
  }

  private func hexStringToData(_ hex: String) -> Data? {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "0x", with: "")
    guard hexSanitized.count % 2 == 0 else { return nil }

    var data = Data()
    var index = hexSanitized.startIndex
    while index < hexSanitized.endIndex {
      let nextIndex = hexSanitized.index(index, offsetBy: 2)
      let byteString = String(hexSanitized[index..<nextIndex])
      if let byte = UInt8(byteString, radix: 16) {
        data.append(byte)
      } else {
        return nil
      }
    }
    return data
  }
}
