import CoreBluetooth
import FitnessTrackerCore
import Foundation

/// Both delegates run on the explicitly selected main queue. SDK references never cross actors.
@MainActor
final class BluetoothHeartRateService: NSObject, HeartRateBluetooth,
  @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate
{
  var onChange: (@MainActor (HeartRateBluetoothSnapshot) -> Void)?
  private var central: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var peripheral: CBPeripheral?
  private var snapshot = HeartRateBluetoothSnapshot()
  private var scanRequested = false
  private var timeout: Task<Void, Never>?
  private let serviceID = CBUUID(string: "180D")
  private let measurementID = CBUUID(string: "2A37")

  func scan() {
    disconnect()
    peripherals = [:]
    snapshot = HeartRateBluetoothSnapshot()
    scanRequested = true
    // Construct only after an explicit user action, avoiding an unsolicited Bluetooth prompt.
    if central == nil {
      central = CBCentralManager(
        delegate: self, queue: .main,
        options: [CBCentralManagerOptionShowPowerAlertKey: false])
    } else {
      beginScanIfPoweredOn()
    }
  }
  private func beginScanIfPoweredOn() {
    guard let central, central.state == .poweredOn, scanRequested else {
      if let central { updatePowerState(central.state) }
      return
    }
    snapshot.connection = .scanning
    publish()
    central.scanForPeripherals(
      withServices: [serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    armTimeout(seconds: 30) { [weak self] in self?.stopScan() }
  }
  func stopScan() {
    scanRequested = false
    central?.stopScan()
    if snapshot.connection == .scanning {
      timeout?.cancel()
      snapshot.connection = .idle
      publish()
    }
  }
  func connect(_ id: UUID) {
    guard let central, central.state == .poweredOn, let candidate = peripherals[id] else { return }
    disconnect()
    peripheral = candidate
    candidate.delegate = self
    snapshot.connection = .connecting
    snapshot.deviceName = snapshot.devices.first { $0.id == id }?.name ?? candidate.name
    snapshot.reading = nil
    publish()
    central.connect(candidate)
    armTimeout(seconds: 20) { [weak self] in self?.failConnection() }
  }
  func disconnect() {
    stopScan()
    timeout?.cancel()
    let previous = peripheral
    peripheral = nil
    previous?.delegate = nil
    if let previous { central?.cancelPeripheralConnection(previous) }
    snapshot.connection = .idle
    snapshot.reading = nil
    snapshot.deviceName = nil
    publish()
  }
  private func failConnection(_ error: (any Error)? = nil) {
    if let error { AppErrorReporter.record(error, operation: "bluetoothHeartRate") }
    disconnect()
    snapshot.connection = .failed
    publish()
  }
  private func armTimeout(seconds: Int, action: @escaping @MainActor () -> Void) {
    timeout?.cancel()
    timeout = Task {
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard !Task.isCancelled else { return }
      action()
    }
  }
  private func publish() { onChange?(snapshot) }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
      beginScanIfPoweredOn()
    } else {
      timeout?.cancel()
      peripheral = nil
      snapshot.reading = nil
      updatePowerState(central.state)
    }
  }
  private func updatePowerState(_ state: CBManagerState) {
    switch state {
    case .poweredOff: snapshot.connection = .poweredOff
    case .unauthorized: snapshot.connection = .unauthorized
    case .unsupported: snapshot.connection = .unsupported
    default: snapshot.connection = .idle
    }
    publish()
  }
  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi: NSNumber
  ) {
    guard scanRequested, peripherals.count < 50 else { return }
    peripherals[peripheral.identifier] = peripheral
    let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
    snapshot.devices.removeAll { $0.id == peripheral.identifier }
    snapshot.devices.append(
      HeartRateDevice(
        id: peripheral.identifier,
        name: name ?? L10n.text("Пульсометр")))
    publish()
  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard peripheral === self.peripheral else { return }
    peripheral.discoverServices([serviceID])
  }
  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?
  ) {
    guard peripheral === self.peripheral else { return }
    failConnection(error)
  }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
    error: (any Error)?
  ) {
    guard peripheral === self.peripheral else { return }
    if let error { AppErrorReporter.record(error, operation: "bluetoothDisconnect") }
    timeout?.cancel()
    self.peripheral = nil
    snapshot.connection = .disconnected
    snapshot.reading = nil
    publish()
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
    guard peripheral === self.peripheral else { return }
    guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID })
    else {
      failConnection(error)
      return
    }
    peripheral.discoverCharacteristics([measurementID], for: service)
  }
  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
    error: (any Error)?
  ) {
    guard peripheral === self.peripheral else { return }
    guard error == nil,
      let characteristic = service.characteristics?.first(where: { $0.uuid == measurementID }),
      characteristic.properties.contains(.notify)
    else {
      failConnection(error)
      return
    }
    peripheral.setNotifyValue(true, for: characteristic)
  }
  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: (any Error)?
  ) {
    guard peripheral === self.peripheral, characteristic.uuid == measurementID else { return }
    guard error == nil, characteristic.isNotifying else {
      failConnection(error)
      return
    }
    timeout?.cancel()
    snapshot.connection = .connected
    publish()
  }
  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
    error: (any Error)?
  ) {
    guard peripheral === self.peripheral, characteristic.uuid == measurementID else { return }
    guard error == nil, let value = characteristic.value else {
      failConnection(error)
      return
    }
    do {
      let measurement = try BluetoothHeartRateMeasurement.decode(value)
      let reading = HeartRateReading(date: .now, beatsPerMinute: Double(measurement.beatsPerMinute))
      snapshot.reading = measurement.hasSkinContact != false && reading.isValid ? reading : nil
      publish()
    } catch {
      snapshot.reading = nil
      AppErrorReporter.record(error, operation: "decodeHeartRate")
      publish()
    }
  }
}
