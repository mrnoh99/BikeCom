import Foundation
import CoreBluetooth

/// 이 폰이 지금 갖고 있는 심박(워치 WCSession 또는 폰 BLE 스트랩에서 받은 값)을
/// 표준 BLE Heart Rate Service(`0x180D`)로 재광고한다.
///
/// `CBPeripheralManager`(BLE 페리페럴/광고 역할)는 **watchOS 에는 없다** — 센트럴 역할만
/// 지원한다. 그래서 워치가 직접 BLE 로 광고할 수는 없고, 대신 이미 심박을 받은 폰이
/// 일반 BLE 심박 스트랩처럼 재광고한다. 이렇게 하면 이 폰과 페어링되지 않은 다른
/// 아이폰(BikeCom 의 `BLEHeartRateManager`, 또는 표준 HR 서비스를 스캔하는 임의의 앱)도
/// 근처에서 이 폰을 거쳐 심박을 받을 수 있다.
final class HeartRateBroadcaster: NSObject {
    static let shared = HeartRateBroadcaster()

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")

    private var peripheralManager: CBPeripheralManager?
    private var measurementCharacteristic: CBMutableCharacteristic?
    private var serviceAdded = false
    private var advertising = false
    private var latestBPM: Int = 0

    /// 라이딩 시작 시 호출 — 아직 켜져 있지 않으면 `CBPeripheralManager` 를 만든다.
    func start() {
        guard peripheralManager == nil else {
            startAdvertisingIfNeeded()
            return
        }
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    /// 라이딩 종료 시 호출 — 광고·서비스를 모두 내린다.
    func stop() {
        guard let pm = peripheralManager else { return }
        if advertising { pm.stopAdvertising() }
        pm.removeAllServices()
        peripheralManager = nil
        measurementCharacteristic = nil
        serviceAdded = false
        advertising = false
        latestBPM = 0
    }

    /// 최신 심박(bpm)을 구독 중인 모든 센트럴(다른 아이폰)에 notify 한다.
    func update(bpm: Int) {
        guard bpm > 0 else { return }
        latestBPM = bpm
        guard let pm = peripheralManager, pm.state == .poweredOn,
              let characteristic = measurementCharacteristic else { return }
        pm.updateValue(Self.encode(bpm: bpm), for: characteristic, onSubscribedCentrals: nil)
    }

    /// GATT Heart Rate Measurement(`0x2A37`) 포맷: flags(1B, 0=UINT8 심박값) + 심박값(1B).
    private static func encode(bpm: Int) -> Data {
        Data([0x00, UInt8(clamping: bpm)])
    }

    private func setupServiceIfNeeded() {
        guard !serviceAdded, let pm = peripheralManager else { return }
        let characteristic = CBMutableCharacteristic(
            type: Self.heartRateMeasurement,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable])
        measurementCharacteristic = characteristic
        let service = CBMutableService(type: Self.heartRateService, primary: true)
        service.characteristics = [characteristic]
        pm.add(service)
    }

    private func startAdvertisingIfNeeded() {
        guard let pm = peripheralManager, pm.state == .poweredOn, serviceAdded, !advertising else { return }
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.heartRateService],
            CBAdvertisementDataLocalNameKey: "BikeCom HR",
        ])
        advertising = true
    }
}

extension HeartRateBroadcaster: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            setupServiceIfNeeded()
        } else {
            advertising = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        serviceAdded = true
        startAdvertisingIfNeeded()
        if latestBPM > 0 { update(bpm: latestBPM) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard latestBPM > 0, let ch = measurementCharacteristic else { return }
        peripheral.updateValue(Self.encode(bpm: latestBPM), for: ch, onSubscribedCentrals: [central])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == Self.heartRateMeasurement else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        request.value = Self.encode(bpm: latestBPM)
        peripheral.respond(to: request, withResult: .success)
    }
}
