import Foundation
import CoreBluetooth
import Combine

/// 폰에 표준 BLE 심박 센서(GATT Heart Rate Service `0x180D`)를 **직접** 연결한다.
///
/// 일반 BLE 심박 스트랩(Polar·Wahoo 등)뿐 아니라, `HeartRateBroadcaster`(BikeComWatch)로
/// 이 서비스를 어드버타이즈하는 Apple Watch도 같은 방식으로 잡힌다 — 즉 **그 워치와
/// OS 페어링되지 않은 다른 아이폰**에서도 여기로 스캔·연결해 심박을 받을 수 있다.
/// Apple Watch(WatchConnectivity, `WatchSensorManager`)가 연결돼 있으면 그쪽이 우선이며,
/// 이 매니저는 워치가 없거나 미페어링일 때의 보조/대체 경로다.
final class BLEHeartRateManager: NSObject, ObservableObject {
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")

    @Published private(set) var bpm: Int = 0
    @Published private(set) var connected = false
    @Published private(set) var poweredOn = false
    @Published private(set) var scanning = false
    @Published private(set) var discovered: [Found] = []
    @Published private(set) var connectedName: String?

    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let savedKey = "bike.bleHR.deviceID"
    private var lastSampleAt = Date.distantPast
    private var staleTimer: AnyCancellable?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        staleTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.decayIfStale() }
    }

    // MARK: 스캔 / 연결

    func startScan() {
        guard poweredOn else { return }
        discovered = []
        scanning = true
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)
    }

    func stopScan() {
        scanning = false
        central.stopScan()
    }

    func connect(_ id: UUID) {
        stopScan()
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        UserDefaults.standard.set(id.uuidString, forKey: savedKey)
        link(p)
        if p.state != .connected {
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        } else {
            ensureNotifications(for: p)
        }
    }

    /// 연결 해제 + 저장 해제(자동 재연결 중단).
    func forget() {
        UserDefaults.standard.removeObject(forKey: savedKey)
        guard let p = peripheral else {
            clearState()
            return
        }
        peripheral = nil
        clearState()
        central.cancelPeripheralConnection(p)
    }

    private func link(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        connectedName = p.name ?? "심박 센서"
    }

    private func reconnectSavedIfNeeded() {
        guard peripheral == nil,
              let str = UserDefaults.standard.string(forKey: savedKey),
              let id = UUID(uuidString: str),
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        link(p)
        if p.state != .connected {
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        } else {
            ensureNotifications(for: p)
        }
    }

    private func ensureNotifications(for p: CBPeripheral) {
        guard p.state == .connected else { return }
        if let s = p.services?.first(where: { $0.uuid == Self.heartRateService }) {
            p.discoverCharacteristics([Self.heartRateMeasurement], for: s)
        } else {
            p.discoverServices([Self.heartRateService])
        }
    }

    private func clearState() {
        connectedName = nil
        bpm = 0
        connected = false
    }

    private func decayIfStale() {
        guard Date().timeIntervalSince(lastSampleAt) > 5, bpm != 0 else { return }
        bpm = 0
        connected = false
    }

    // MARK: Heart Rate Measurement(0x2A37) 파싱

    private func parse(_ data: Data) {
        let b = [UInt8](data)
        guard let flags = b.first, b.count >= 2 else { return }
        let value: Int
        if (flags & 0x01) != 0 {
            guard b.count >= 3 else { return }
            value = Int(b[1]) | (Int(b[2]) << 8)
        } else {
            value = Int(b[1])
        }
        guard value > 0, value < 260 else { return }
        bpm = value
        lastSampleAt = Date()
        if !connected { connected = true }
    }
}

extension BLEHeartRateManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        poweredOn = c.state == .poweredOn
        if poweredOn {
            reconnectSavedIfNeeded()
        } else {
            connected = false
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "심박 센서"
        let f = Found(id: p.identifier, name: name)
        if !discovered.contains(f) { discovered.append(f) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connectedName = p.name ?? connectedName
        p.discoverServices([Self.heartRateService])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        connected = false
        guard let saved = UserDefaults.standard.string(forKey: savedKey),
              saved == p.identifier.uuidString else { return }
        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        connected = false
    }
}

extension BLEHeartRateManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.heartRateService }) else { return }
        p.discoverCharacteristics([Self.heartRateMeasurement], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.heartRateMeasurement }) else { return }
        p.setNotifyValue(true, for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.heartRateMeasurement, ch.isNotifying else { return }
        connected = true
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.heartRateMeasurement, let data = ch.value else { return }
        parse(data)
    }
}
