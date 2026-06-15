import Foundation
import CoreBluetooth
import Combine

/// 폰에 BLE 자전거 속도·케이던스(CSC) 센서를 **직접** 연결한다(워치 중계 없이).
/// 속도·케이던스 센서를 각각 별도 슬롯에 연결·저장·자동 재연결한다.
final class BLECSCManager: NSObject, ObservableObject {
    enum Slot: String, CaseIterable {
        case speed, cadence
    }

    static let cscService = CBUUID(string: "1816")
    static let cscMeasurement = CBUUID(string: "2A5B")

    @Published private(set) var speedMps: Double = 0
    @Published private(set) var cadenceRPM: Int = 0
    @Published private(set) var speedConnected = false
    @Published private(set) var cadenceConnected = false
    @Published private(set) var poweredOn = false
    @Published private(set) var scanning = false
    @Published private(set) var scanTarget: Slot?
    @Published private(set) var discovered: [Found] = []
    @Published private(set) var connectedSpeedName: String?
    @Published private(set) var connectedCadenceName: String?

    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    /// 휠 둘레(m) — 속도 계산용. RideSession 이 설정과 동기화한다.
    var wheelCircumferenceMeters: Double = 2.105

    private var central: CBCentralManager!
    private var peripherals: [Slot: CBPeripheral] = [:]
    private let savedSpeedKey = "bike.bleCSC.speedID"
    private let savedCadenceKey = "bike.bleCSC.cadenceID"
    private let legacySavedKey = "bike.bleCSC.savedID"

    // CSC 누적 상태(직전 알림값) — 슬롯별
    private var lastWheelRevs: UInt32?
    private var lastWheelTime: UInt16?
    private var lastCrankRevs: UInt16?
    private var lastCrankTime: UInt16?
    private var lastSpeedSampleAt = Date.distantPast
    private var lastCadenceSampleAt = Date.distantPast
    private var staleTimer: AnyCancellable?
    private var reconnectRetry: AnyCancellable?
    /// false 이면 연결 해제·자동 재연결 중단(워치 모드). 저장 UUID 는 유지.
    private(set) var connectionsActive = true

    override init() {
        super.init()
        migrateLegacySavedID()
        central = CBCentralManager(delegate: self, queue: .main)
        staleTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.decayIfStale() }
    }

    var hasAnyConnection: Bool {
        connectedSpeedName != nil || connectedCadenceName != nil
    }

    // MARK: 스캔 / 연결

    func startScan(for slot: Slot) {
        guard poweredOn, connectionsActive else { return }
        discovered = []
        scanTarget = slot
        scanning = true
        central.scanForPeripherals(withServices: [Self.cscService], options: nil)
    }

    func stopScan() {
        scanning = false
        scanTarget = nil
        central.stopScan()
    }

    /// 폰 BLE 연결 활성/중단. 중단 시 저장된 센서 UUID 는 유지하고 물리 연결만 끊는다.
    func setConnectionsActive(_ active: Bool) {
        guard connectionsActive != active else { return }
        connectionsActive = active
        if active {
            reconnectSavedIfNeeded()
            startReconnectRetryIfNeeded()
        } else {
            stopReconnectRetry()
            suspendAllConnections()
        }
    }

    private func startReconnectRetryIfNeeded() {
        stopReconnectRetry()
        guard connectionsActive, hasSavedPeripheral else { return }
        reconnectRetry = Timer.publish(every: 2.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.connectionsActive, self.poweredOn else { return }
                let pending = (self.savedID(for: .speed) != nil && !self.speedConnected)
                    || (self.savedID(for: .cadence) != nil && !self.cadenceConnected)
                guard pending else {
                    self.stopReconnectRetry()
                    return
                }
                self.reconnectSavedIfNeeded()
            }
    }

    private func stopReconnectRetry() {
        reconnectRetry?.cancel()
        reconnectRetry = nil
    }

    private var hasSavedPeripheral: Bool {
        savedID(for: .speed) != nil || savedID(for: .cadence) != nil
    }

    func connect(_ id: UUID, slot: Slot) {
        guard connectionsActive else { return }
        stopScan()
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        saveID(id, slot: slot)
        link(peripheral: p, slot: slot)
        if p.state != .connected {
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        } else {
            ensureNotifications(for: p)
        }
    }

    /// 연결 해제 + 저장 해제(자동 재연결 중단).
    func forget(_ slot: Slot) {
        UserDefaults.standard.removeObject(forKey: savedKey(for: slot))
        guard let p = peripherals[slot] else {
            clearSlot(slot)
            return
        }
        peripherals[slot] = nil
        clearSlot(slot)
        if !isPeripheralLinked(p) {
            central.cancelPeripheralConnection(p)
        } else {
            ensureNotifications(for: p)
        }
    }

    private func migrateLegacySavedID() {
        guard let old = UserDefaults.standard.string(forKey: legacySavedKey),
              UserDefaults.standard.string(forKey: savedSpeedKey) == nil else { return }
        UserDefaults.standard.set(old, forKey: savedSpeedKey)
        UserDefaults.standard.removeObject(forKey: legacySavedKey)
    }

    private func savedKey(for slot: Slot) -> String {
        switch slot {
        case .speed: savedSpeedKey
        case .cadence: savedCadenceKey
        }
    }

    private func savedID(for slot: Slot) -> UUID? {
        UserDefaults.standard.string(forKey: savedKey(for: slot)).flatMap(UUID.init)
    }

    private func saveID(_ id: UUID, slot: Slot) {
        UserDefaults.standard.set(id.uuidString, forKey: savedKey(for: slot))
    }

    private func link(peripheral p: CBPeripheral, slot: Slot) {
        peripherals[slot] = p
        p.delegate = self
        updateConnectedName(for: p)
    }

    private func reconnectSavedIfNeeded() {
        guard connectionsActive else { return }
        for slot in Slot.allCases {
            guard peripherals[slot] == nil, let id = savedID(for: slot),
                  let p = central.retrievePeripherals(withIdentifiers: [id]).first else { continue }
            link(peripheral: p, slot: slot)
            if p.state != .connected {
                central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            } else {
                ensureNotifications(for: p)
            }
        }
    }

    private func isPeripheralLinked(_ p: CBPeripheral) -> Bool {
        peripherals.values.contains { $0.identifier == p.identifier }
    }

    private func slots(for p: CBPeripheral) -> [Slot] {
        Slot.allCases.filter { peripherals[$0]?.identifier == p.identifier }
    }

    private func ensureNotifications(for p: CBPeripheral) {
        guard p.state == .connected else { return }
        if p.services?.contains(where: { $0.uuid == Self.cscService }) == true {
            for s in p.services ?? [] where s.uuid == Self.cscService {
                p.discoverCharacteristics([Self.cscMeasurement], for: s)
            }
        } else {
            p.discoverServices([Self.cscService])
        }
    }

    private func updateConnectedName(for p: CBPeripheral) {
        let name = p.name ?? "센서"
        for slot in slots(for: p) {
            switch slot {
            case .speed: connectedSpeedName = name
            case .cadence: connectedCadenceName = name
            }
        }
    }

    private func suspendAllConnections() {
        stopScan()
        var ids = Set<UUID>()
        for slot in Slot.allCases {
            if let p = peripherals[slot] { ids.insert(p.identifier) }
            peripherals[slot] = nil
            clearSlot(slot)
        }
        for id in ids {
            guard let p = central.retrievePeripherals(withIdentifiers: [id]).first,
                  p.state == .connected || p.state == .connecting else { continue }
            central.cancelPeripheralConnection(p)
        }
    }

    private func clearSlot(_ slot: Slot) {
        switch slot {
        case .speed:
            connectedSpeedName = nil
            speedMps = 0
            speedConnected = false
            lastWheelRevs = nil
            lastWheelTime = nil
        case .cadence:
            connectedCadenceName = nil
            cadenceRPM = 0
            cadenceConnected = false
            lastCrankRevs = nil
            lastCrankTime = nil
        }
    }

    private func decayIfStale() {
        let now = Date()
        if now.timeIntervalSince(lastSpeedSampleAt) > 3, speedMps != 0 { speedMps = 0 }
        if now.timeIntervalSince(lastCadenceSampleAt) > 3, cadenceRPM != 0 { cadenceRPM = 0 }
    }

    // MARK: CSC Measurement(0x2A5B) 파싱

    private func parse(_ data: Data, from peripheral: CBPeripheral) {
        let roles = slots(for: peripheral)
        guard !roles.isEmpty else { return }

        let b = [UInt8](data)
        guard let flags = b.first else { return }
        var i = 1
        let wheelPresent = (flags & 0x01) != 0
        let crankPresent = (flags & 0x02) != 0
        let now = Date()
        let acceptsSpeed = roles.contains(.speed)
        let acceptsCadence = roles.contains(.cadence)

        if wheelPresent, acceptsSpeed, b.count >= i + 6 {
            let revs = UInt32(b[i]) | (UInt32(b[i+1]) << 8) | (UInt32(b[i+2]) << 16) | (UInt32(b[i+3]) << 24)
            let time = UInt16(b[i+4]) | (UInt16(b[i+5]) << 8)
            i += 6
            if let lr = lastWheelRevs, let lt = lastWheelTime {
                let dRev = revs &- lr
                let dT = time &- lt
                if dT > 0 {
                    let seconds = Double(dT) / 1024.0
                    let mps = Double(dRev) * wheelCircumferenceMeters / seconds
                    if mps >= 0, mps < 35 {
                        speedMps = mps
                        lastSpeedSampleAt = now
                    }
                } else if dRev == 0 {
                    speedMps = 0
                }
            }
            lastWheelRevs = revs
            lastWheelTime = time
            if !speedConnected { speedConnected = true }
        }

        if crankPresent, acceptsCadence, b.count >= i + 4 {
            let revs = UInt16(b[i]) | (UInt16(b[i+1]) << 8)
            let time = UInt16(b[i+2]) | (UInt16(b[i+3]) << 8)
            if let lr = lastCrankRevs, let lt = lastCrankTime {
                let dRev = revs &- lr
                let dT = time &- lt
                if dT > 0 {
                    let minutes = Double(dT) / 1024.0 / 60.0
                    let rpm = Double(dRev) / minutes
                    if rpm >= 0, rpm < 250 {
                        cadenceRPM = Int(rpm.rounded())
                        lastCadenceSampleAt = now
                    }
                } else if dRev == 0 {
                    cadenceRPM = 0
                }
            }
            lastCrankRevs = revs
            lastCrankTime = time
            if !cadenceConnected { cadenceConnected = true }
        }
    }

    private func markSubscribed(for p: CBPeripheral) {
        for slot in slots(for: p) {
            switch slot {
            case .speed where !speedConnected: speedConnected = true
            case .cadence where !cadenceConnected: cadenceConnected = true
            default: break
            }
        }
    }

    private func markDisconnected(_ p: CBPeripheral) {
        for slot in slots(for: p) {
            switch slot {
            case .speed: speedConnected = false
            case .cadence: cadenceConnected = false
            }
        }
    }
}

extension BLECSCManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        poweredOn = c.state == .poweredOn
        if poweredOn {
            if connectionsActive { reconnectSavedIfNeeded() }
            else {
                speedConnected = false
                cadenceConnected = false
            }
        } else {
            speedConnected = false
            cadenceConnected = false
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "센서"
        let f = Found(id: p.identifier, name: name)
        if !discovered.contains(f) { discovered.append(f) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        updateConnectedName(for: p)
        p.discoverServices([Self.cscService])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        markDisconnected(p)
        guard connectionsActive else { return }
        for slot in slots(for: p) where savedID(for: slot) == p.identifier {
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        markDisconnected(p)
    }
}

extension BLECSCManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == Self.cscService {
            p.discoverCharacteristics([Self.cscMeasurement], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where ch.uuid == Self.cscMeasurement {
            p.setNotifyValue(true, for: ch)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.cscMeasurement, ch.isNotifying else { return }
        markSubscribed(for: p)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.cscMeasurement, let data = ch.value else { return }
        parse(data, from: p)
    }
}
