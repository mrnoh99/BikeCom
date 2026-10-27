import CoreData
import Foundation

/// 라이딩 기록 1건의 Core Data 표현. `BikeCom.xcdatamodeld`의 `CDRide` 엔티티에 대응한다.
///
/// 모델의 모든 속성은 Optional이다 — `NSPersistentCloudKitContainer`(CloudKit 동기화)를 쓰려면
/// 모든 속성이 Optional이거나 기본값이 있어야 하고(고유 제약은 아예 지원 안 됨), 가장 단순하고
/// 안전한 선택은 전부 Optional로 두는 것이다. 여기 선언한 Swift 프로퍼티 타입(비Optional
/// `Double`/`Int32`/`Bool` 등)은 Core Data의 표준 스칼라 접근자 관례를 그대로 따른 것뿐이고,
/// 모델 쪽 Optional 여부와는 무관하다 — 코드 생성은 Xcode에 맡기지 않고(모델의
/// `codeGenerationType="None"`) 이 파일에서 직접 선언해 타입을 명확히 고정한다.
@objc(CDRide)
final class CDRide: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var bikeName: String?
    @NSManaged var source: String?            // RideSource.rawValue
    @NSManaged var location: String?
    @NSManaged var startedAt: Date?
    @NSManaged var duration: Double
    @NSManaged var totalElapsed: Double
    @NSManaged var distanceMeters: Double
    @NSManaged var averageSpeedMps: Double
    @NSManaged var maxSpeedMps: Double
    @NSManaged var maxHeartRate: NSNumber?
    @NSManaged var avgHeartRate: NSNumber?
    @NSManaged var maxCadence: NSNumber?
    @NSManaged var avgCadence: NSNumber?
    /// GPS 트랙([RideRecord.Coordinate])을 JSON으로 인코딩해 저장. 모델에서
    /// "Allows External Storage"를 켜서, 큰 트랙도 CloudKit 레코드 용량 제한(1MB)에
    /// 걸리지 않고 별도 에셋으로 동기화된다.
    @NSManaged var trackData: Data?
    @NSManaged var trackCount: Int32
    @NSManaged var startCoordData: Data?      // RideRecord.Coordinate 1건, JSON
    @NSManaged var endCoordData: Data?
    @NSManaged var includeInMap: Bool
    @NSManaged var mapName: String?
    @NSManaged var isCourseOnly: Bool
}

extension CDRide {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDRide> {
        NSFetchRequest<CDRide>(entityName: "CDRide")
    }
}
