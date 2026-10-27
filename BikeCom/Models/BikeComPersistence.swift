import CoreData

/// Core Data + CloudKit 스택 생성. `RideStore`가 유일한 사용처이고, 앱 생애주기 동안
/// 컨테이너는 하나만 있으면 되므로 `RideStore.init()`에서 한 번만 호출한다.
enum BikeComPersistence {
    /// 컨테이너를 만들고 옵션만 구성한다 — 스토어 로드는 비동기라 `loadPersistentStores`의
    /// 완료 핸들러는 호출부(`RideStore.init`)에서 직접 걸어야 한다. 여기서 끝까지 처리해
    /// "로드 완료 전에 fetch가 먼저 실행되는" 레이스를 만들면 안 된다.
    static func makeContainer() -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "BikeCom")
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("BikeCom.xcdatamodeld 에서 퍼시스턴트 스토어 설명을 찾지 못함")
        }
        // 다른 기기의 변경을 NSPersistentStoreRemoteChange 알림으로 받기 위해 필요.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: CloudDocuments.containerID)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }
}
