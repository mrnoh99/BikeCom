import Foundation
import MediaPlayer

/// Apple Music 앱에서 현재 재생 중인 곡의 제목·아티스트를 가져온다.
///
/// iOS는 다른 음악 앱(Spotify·YouTube Music 등)이 재생 중인 곡 정보를 읽는 공식 API를 제공하지
/// 않는다(샌드박스 제한 — `MPNowPlayingInfoCenter`는 내 앱이 설정한 값만 쓰고 읽을 수 있다).
/// `MPMusicPlayerController.systemMusicPlayer`는 Apple Music 앱의 재생 상태만 반영하므로,
/// 이 기능은 Apple Music으로 들을 때만 동작한다.
final class NowPlayingMusicObserver: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var title: String?
    @Published private(set) var artist: String?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var isGeneratingNotifications = false

    init() {
        // 이미 승인돼 있으면(이전 실행에서 허용) 바로 알림 구독 시작. 아직이면 요청만 하고,
        // 사용자가 허용한 뒤 다음 실행부터 반영된다 — 라이딩 화면을 열 때마다 매번 권한
        // 팝업을 띄우고 싶지 않아서, 거부된 경우 다시 묻지 않는다(MPMediaLibrary 쪽 표준 동작).
        if MPMediaLibrary.authorizationStatus() == .authorized {
            startObserving()
        } else {
            MPMediaLibrary.requestAuthorization { [weak self] status in
                guard status == .authorized else { return }
                DispatchQueue.main.async { self?.startObserving() }
            }
        }
    }

    deinit {
        if isGeneratingNotifications {
            player.endGeneratingPlaybackNotifications()
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func startObserving() {
        guard !isGeneratingNotifications else { return }
        isGeneratingNotifications = true
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(update),
                                               name: .MPMusicPlayerControllerNowPlayingItemDidChange,
                                               object: player)
        NotificationCenter.default.addObserver(self, selector: #selector(update),
                                               name: .MPMusicPlayerControllerPlaybackStateDidChange,
                                               object: player)
        update()
    }

    @objc private func update() {
        isPlaying = player.playbackState == .playing
        title = player.nowPlayingItem?.title
        artist = player.nowPlayingItem?.artist
    }
}
