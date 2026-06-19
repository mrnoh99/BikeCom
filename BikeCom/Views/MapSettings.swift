import SwiftUI
import WebKit
import CoreLocation

/// 지도 제공자 선택(영속: AppStorage "map.provider").
enum MapProvider: String, CaseIterable, Identifiable {
    case apple, google, kakao
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple 지도"
        case .google: return "Google 지도"
        case .kakao: return "카카오 자전거 맵"
        }
    }
}

/// 카카오 지도 JavaScript 키(Info.plist: KakaoJavaScriptAppKey). 없으면 Apple 폴백.
enum KakaoConfig {
    static var jsKey: String? {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "KakaoJavaScriptAppKey") as? String,
              !k.isEmpty else { return nil }
        return k
    }
    static var hasKey: Bool { jsKey != nil }
}

/// 지도 설정 시트 — ① 지도 선택(Apple/Google/카카오 자전거) ② 코스 선택(따라가기).
struct MapSettingsSheet: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("map.provider") private var providerRaw = MapProvider.apple.rawValue

    /// 지도 코스 자료(isCourseOnly) + GPS 있는 코스만, 표시 이름순.
    private var courseRecords: [RideRecord] {
        session.store.records
            .filter { $0.isCourseOnly && $0.trackCount > 1 }
            .sorted { courseName($0) < courseName($1) }
    }
    private func courseName(_ r: RideRecord) -> String {
        (r.mapName?.isEmpty == false ? r.mapName! : r.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("지도", selection: $providerRaw) {
                        ForEach(MapProvider.allCases) { p in
                            Text(p.label).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("지도 선택")
                } footer: {
                    providerFooter
                }

                Section("코스 선택") {
                    Button {
                        session.clearFollowCourse(); dismiss()
                    } label: {
                        HStack {
                            Label("따라가기 해제", systemImage: "xmark.circle")
                            Spacer()
                            if session.followCourseName == nil {
                                Image(systemName: "checkmark").foregroundColor(Theme.gold)
                            }
                        }
                    }
                    if courseRecords.isEmpty {
                        Text("저장된 지도 코스가 없습니다. 라이딩 기록 상세에서 '지도 코스로 복사'로 추가하세요.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(courseRecords) { course in
                        Button {
                            session.setFollowCourse(course); dismiss()
                        } label: {
                            HStack {
                                Text(courseName(course)).foregroundColor(.primary)
                                Spacer()
                                if session.followCourseName == courseName(course) {
                                    Image(systemName: "checkmark").foregroundColor(Theme.gold)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("지도 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
        }
    }

    @ViewBuilder private var providerFooter: some View {
        switch MapProvider(rawValue: providerRaw) ?? .apple {
        case .apple:
            Text("Apple 지도는 추가 설정 없이 사용합니다.")
        case .google:
            Text(googleAvailable
                 ? "Google 지도를 사용합니다."
                 : "Google 지도는 GoogleMaps SDK + API 키(Info.plist: GMSApiKey)가 필요합니다. 없으면 Apple 지도로 표시됩니다.")
        case .kakao:
            Text(KakaoConfig.hasKey
                 ? "카카오 자전거 맵(자전거 도로 오버레이)을 사용합니다."
                 : "카카오 자전거 맵은 Kakao JavaScript 키(Info.plist: KakaoJavaScriptAppKey)가 필요합니다. 없으면 Apple 지도로 표시됩니다.")
        }
    }

    private var googleAvailable: Bool {
        #if canImport(GoogleMaps)
        return GMapsConfig.hasKey
        #else
        return false
        #endif
    }
}

/// 카카오 자전거 맵(WKWebView) — 자전거 도로 오버레이 + 기준 코스·현재 경로 + 사용자 위치.
/// 라이브 추적: 사용자 위치를 계속 따라가고(직접 지도를 움직이면 추적 중단), 재중심 버튼으로
/// 다시 켠다. 내비 모드는 근접 줌(레벨 3)으로 본다. (Kakao JS 지도는 회전·3D 미지원.)
/// Info.plist 에 KakaoJavaScriptAppKey 가 있어야 하며, Kakao 개발자 콘솔에 도메인 등록이 필요하다.
struct KakaoWebMap: UIViewRepresentable {
    let track: [CLLocationCoordinate2D]
    let userLocation: CLLocationCoordinate2D?
    var courseTrack: [CLLocationCoordinate2D] = []
    var navigationMode: Bool = false
    var recenterToken: Int = 0

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.isOpaque = false
        if let key = KakaoConfig.jsKey {
            web.loadHTMLString(Self.html(key: key), baseURL: URL(string: "https://localhost"))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        func arr(_ c: [CLLocationCoordinate2D]) -> String {
            "[" + c.map { "[\($0.latitude),\($0.longitude)]" }.joined(separator: ",") + "]"
        }
        let locArgs = userLocation.map { "\($0.latitude),\($0.longitude)" } ?? "null,null"
        let nav = navigationMode ? "true" : "false"
        web.evaluateJavaScript(
            "if(window.bikeUpdate){window.bikeUpdate(\(arr(track)),\(arr(courseTrack)),\(locArgs),\(nav));}",
            completionHandler: nil)
        // 재중심 버튼: 토큰이 바뀌면 추적을 다시 켜고 사용자 위치로 이동.
        if context.coordinator.recenterToken != recenterToken {
            context.coordinator.recenterToken = recenterToken
            web.evaluateJavaScript("if(window.bikeRecenter){window.bikeRecenter();}", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var recenterToken = 0 }

    private static func html(key: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>html,body,#map{margin:0;width:100%;height:100%;background:#000}</style>
        <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=\(key)&autoload=false"></script>
        </head><body><div id="map"></div>
        <script>
        kakao.maps.load(function(){
          var map=new kakao.maps.Map(document.getElementById('map'),
            {center:new kakao.maps.LatLng(37.5665,126.9780),level:4});
          map.addOverlayMapTypeId(kakao.maps.MapTypeId.BICYCLE);
          var tLine=null,cLine=null,me=null,follow=true,navOn=false;
          function path(a){return a.map(function(p){return new kakao.maps.LatLng(p[0],p[1]);});}
          // 사용자가 직접 지도를 움직이면 자동 추적 중단.
          kakao.maps.event.addListener(map,'dragstart',function(){follow=false;});
          window.bikeRecenter=function(){follow=true; if(me){map.setCenter(me.getPosition());}};
          window.bikeUpdate=function(track,course,lat,lon,nav){
            if(cLine)cLine.setMap(null);
            if(course&&course.length>1){cLine=new kakao.maps.Polyline({path:path(course),strokeWeight:6,strokeColor:'#FF9500',strokeOpacity:0.7});cLine.setMap(map);}
            if(tLine)tLine.setMap(null);
            if(track&&track.length>1){tLine=new kakao.maps.Polyline({path:path(track),strokeWeight:5,strokeColor:'#1E78FF',strokeOpacity:0.95});tLine.setMap(map);}
            if(nav!==navOn){navOn=nav; map.setLevel(nav?3:4);}   // 내비: 근접 줌
            if(lat!=null&&lon!=null){var pos=new kakao.maps.LatLng(lat,lon);
              if(!me){me=new kakao.maps.Marker({position:pos});me.setMap(map);}else{me.setPosition(pos);}
              if(follow){map.setCenter(pos);}}   // 추적 중이면 계속 따라감
          };
        });
        </script></body></html>
        """
    }
}
