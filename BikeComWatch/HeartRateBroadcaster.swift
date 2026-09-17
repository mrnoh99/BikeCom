import Foundation
import CoreBluetooth

/// 워치를 표준 BLE 심박 센서(GATT Heart Rate Service `0x180D`)로 광고한다.
///
/// `WCSession`(WatchConnectivity)은 이 워치와 OS 레벨로 **페어링된** 단 하나의 아이폰에만
/// 심박을 전달할 수 있다. 반면 BLE GATT 연결은 페어링과 무관하므로, 여기서 워치를
/// 일반 BLE 심박 스트랩처럼 어드버타이즈하면 페어링되지 않은 다른 아이폰의 BikeCom
/// (또는 표준 HR 서비스를 스캔하는 임의의 앱)도 근처에서 심박을 구독할 수 있다.
final class HeartRateBroadcaster: NSObject {
    static let shared = HeartRateBroadcaster()

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")

    private var peripheralManager: CBPeripheralManager?
    private var measurementCharacteristic: CBMutableCharacteristic?
    private var serviceAdded = false
    private var advertising = false
    private var latestBPM: Int = 0

    /// 워크아웃 시작 시 호출 — 아직 켜져 있지 않으면 `CBPeripheralManager` 를 만든다.
    func start() {
        guard peripheralManager == nil else {
            startAdvertisingIfNeeded()
            return
        }
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    /// 워크아웃 종료 시 호출 — 광고·서비스를 모두 내린다.
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
            CBAdvertisementDataLocalNameKey: "BikeCom Watch HR",
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
