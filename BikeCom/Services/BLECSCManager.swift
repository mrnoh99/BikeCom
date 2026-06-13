import Foundation
import CoreBluetooth
import Combine

/// 폰에 BLE 자전거 속도·케이던스(CSC) 센서를 **직접** 연결한다(워치 중계 없이).
/// 표준 CSC 서비스(0x1816) / CSC Measurement(0x2A5B) 를 구독해
/// 속도(m/s)·케이던스(rpm)를 직접 계산한다.
final class BLECSCManager: NSObject, ObservableObject {
    static let cscService = CBUUID(string: "1816")
    static let cscMeasurement = CBUUID(string: "2A5B")

    @Published private(set) var speedMps: Double = 0
    @Published private(set) var cadenceRPM: Int = 0
    @Published private(set) var speedConnected = false
    @Published private(set) var cadenceConnected = false
    @Published private(set) var poweredOn = false
    @Published private(set) var scanning = false
    @Published private(set) var discovered: [Found] = []
    @Published private(set) var connectedName: String?

    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    /// 휠 둘레(m) — 속도 계산용. RideSession 이 설정과 동기화한다.
    var wheelCircumferenceMeters: Double = 2.105

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let savedKey = "bike.bleCSC.savedID"

    // CSC 누적 상태(직전 알림값)
    private var lastWheelRevs: UInt32?
    private var lastWheelTime: UInt16?
    private var lastCrankRevs: UInt16?
    private var lastCrankTime: UInt16?
    private var lastSpeedSampleAt = Date.distantPast
    private var lastCadenceSampleAt = Date.distantPast
    private var staleTimer: AnyCancellable?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // 무동작(코스팅·정지) 시 속도·케이던스를 0 으로 떨어뜨린다.
        staleTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.decayIfStale() }
    }

    var savedPeripheralID: UUID? {
        UserDefaults.standard.string(forKey: savedKey).flatMap(UUID.init)
    }
    var isLinked: Bool { peripheral != nil }

    // MARK: 스캔 / 연결

    func startScan() {
        guard poweredOn else { return }
        discovered = []
        scanning = true
        central.scanForPeripherals(withServices: [Self.cscService], options: nil)
    }

    func stopScan() {
        scanning = false
        central.stopScan()
    }

    func connect(_ id: UUID) {
        stopScan()
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        UserDefaults.standard.set(id.uuidString, forKey: savedKey)
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    /// 연결 해제 + 저장 해제(자동 재연결 중단).
    func forget() {
        UserDefaults.standard.removeObject(forKey: savedKey)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        connectedName = nil
        resetMetrics()
    }

    private func reconnectSavedIfNeeded() {
        guard peripheral == nil, let id = savedPeripheralID,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func resetMetrics() {
        speedMps = 0; cadenceRPM = 0
        speedConnected = false; cadenceConnected = false
        lastWheelRevs = nil; lastWheelTime = nil
        lastCrankRevs = nil; lastCrankTime = nil
    }

    private func decayIfStale() {
        let now = Date()
        if now.timeIntervalSince(lastSpeedSampleAt) > 3, speedMps != 0 { speedMps = 0 }
        if now.timeIntervalSince(lastCadenceSampleAt) > 3, cadenceRPM != 0 { cadenceRPM = 0 }
    }

    // MARK: CSC Measurement(0x2A5B) 파싱
    // [flags(1)] [wheelRevs(uint32) wheelTime(uint16 @1/1024s)]? [crankRevs(uint16) crankTime(uint16 @1/1024s)]?

    private func parse(_ data: Data) {
        let b = [UInt8](data)
        guard let flags = b.first else { return }
        var i = 1
        let wheelPresent = (flags & 0x01) != 0
        let crankPresent = (flags & 0x02) != 0
        let now = Date()

        if wheelPresent, b.count >= i + 6 {
            let revs = UInt32(b[i]) | (UInt32(b[i+1]) << 8) | (UInt32(b[i+2]) << 16) | (UInt32(b[i+3]) << 24)
            let time = UInt16(b[i+4]) | (UInt16(b[i+5]) << 8)
            i += 6
            if let lr = lastWheelRevs, let lt = lastWheelTime {
                let dRev = revs &- lr            // uint32 롤오버 안전
                let dT = time &- lt              // uint16 롤오버 안전(1/1024 s)
                if dT > 0 {
                    let seconds = Double(dT) / 1024.0
                    let mps = Double(dRev) * wheelCircumferenceMeters / seconds
                    if mps >= 0, mps < 35 {       // 사니티(<126 km/h)
                        speedMps = mps
                        lastSpeedSampleAt = now
                    }
                } else if dRev == 0 {
                    speedMps = 0                 // 같은 이벤트 시각 + 회전 없음 = 정지
                }
            }
            lastWheelRevs = revs; lastWheelTime = time
            if !speedConnected { speedConnected = true }
        }

        if crankPresent, b.count >= i + 4 {
            let revs = UInt16(b[i]) | (UInt16(b[i+1]) << 8)
            let time = UInt16(b[i+2]) | (UInt16(b[i+3]) << 8)
            i += 4
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
            lastCrankRevs = revs; lastCrankTime = time
            if !cadenceConnected { cadenceConnected = true }
        }
    }
}

extension BLECSCManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        poweredOn = c.state == .poweredOn
        if poweredOn {
            reconnectSavedIfNeeded()
        } else {
            speedConnected = false; cadenceConnected = false
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
        connectedName = p.name
        p.discoverServices([Self.cscService])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        speedConnected = false; cadenceConnected = false
        // 저장된 센서면 자동 재연결.
        if savedPeripheralID == p.identifier { central.connect(p, options: nil) }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        speedConnected = false; cadenceConnected = false
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

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.cscMeasurement, let data = ch.value else { return }
        parse(data)
    }
}
