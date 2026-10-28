import UIKit

/// CloudKit이 다른 기기의 변경을 silent push로 알려줄 때 받기 위한 최소한의 델리게이트.
/// Core Data(`NSPersistentCloudKitContainer`) 쪽 실제 가져오기 처리는 시스템이 알아서
/// 하므로, 여기선 원격 알림 등록과 수신 확인만 담당한다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    /// 시뮬레이터·푸시 미설정 등으로 등록이 실패해도 앱 동작엔 지장 없다(포그라운드 동기화는
    /// 그대로 작동) — 로그만 남긴다.
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("원격 알림 등록 실패(백그라운드 즉시 동기화만 영향, 포그라운드 동기화는 정상): \(error)")
    }

    /// CloudKit의 silent push가 도착하면 호출된다. 페이로드를 직접 파싱할 필요는 없다 —
    /// NSPersistentCloudKitContainer가 이 깨어남을 이용해 알아서 가져오기를 진행한다.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }
}
