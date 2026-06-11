# Bike Computer (iOS)

아이폰용 자전거 컴퓨터 앱. **GPS**로 거리·경로를 기록하고, **애플워치**로
속도·케이던스·심박수를 측정한다(워치 미사용 시 폰의 BLE 센서로 폴백). 라이딩은 **Apple 건강(HealthKit)**
앱에 운동으로 기록되며, 누적 거리는 건강 데이터 기준으로 집계한다. Cyclemeter 스타일의 대시보드 UI를 SwiftUI 로 구현했다.

> **최소 OS: iOS 26 / watchOS 26** (워치 HealthKit `cyclingSpeed`·`cyclingCadence` 요구사항).
>
> **대상 기기: iPhone 12 mini + Apple Watch Ultra (1세대)** 에 최적화.
> iPhone 12 mini 는 375pt 폭(가장 좁은 화면)이라 메트릭 라벨이 자동 축소(`minimumScaleFactor`)되도록 했다.

## 화면 구성

**Stopwatch(대시보드) 단일 화면**이며, 나머지는 우하단 **⚙️ 메뉴**로 이동한다(탭바 없음).

| 위치 | 내용 |
|------|------|
| **Stopwatch** (메인) | 시계 / 거리 / 속도·평균 / 라이딩·총 시간 / HR·평균·최대 / 케이던스·평균·최대 / SpO2 / 이번달·올해·누적 + **Start / Done** + ⚙️ |
| ⚙️ → **지도(Map)** | 현재 위치 + 진행 중 경로 + **과거 코스** 오버레이 |
| ⚙️ → **라이딩 기록(Routes)** | 기록 목록(정렬·코스별) · 상세(지도+지표+GPX 공유) |
| ⚙️ → **장치(Devices)** | BLE 센서 스캔·연결, 실시간 rpm·심박 |
| ⚙️ → **더보기(More)** | 데이터 가져오기, 누적 통계, 센서/권한 상태 |
| ⚙️ → **라이딩 설정** | 이름·코스·자전거 종류·휠 둘레 |

## 측정 방식

- **거리·경로**: 항상 **GPS**(CoreLocation) 기준.
- **속도·케이던스·심박수**: **애플워치**가 기본 — 워치에 페어링한 BLE 센서를 워치 워크아웃의
  HealthKit 으로 읽어 폰에 중계. 우선순위는 **워치 > 폰 BLE > GPS**.
- **폴백**: 워치가 없으면 폰이 직접 BLE(CSC 0x1816 속도·케이던스, 0x180D 심박)로 측정.
- **누적 거리**: Apple **건강** 앱의 사이클링 거리(`distanceCycling`) 합 — 이번달/올해/총.
  (앱 설치 전·다른 기기 기록까지 포함, 재설치해도 유지. 권한 미허용 시 로컬 기록으로 폴백.)
- **산소포화도(SpO2)**: 워치 주행화면의 **`SpO2 측정` 버튼**(휴식 중 사용) → 탭 이후 들어오는 새
  `oxygenSaturation` 샘플을 `HKAnchoredObjectQuery` 로 포착해 워치에 표시하고 **WCSession 으로 폰에 즉시 전송**
  → 폰 대시보드 SpO2 셀이 "방금"으로 갱신. 폰은 워치 전송값과 HealthKit 최근값 중 **더 최신**을 표시.
  ⚠️ **앱이 센서를 직접 켤 수는 없다** — `HKLiveWorkoutBuilder` 에 SpO2 라이브 타입이 없고, 측정을 강제할
  공개 API 도 없다. 실제 측정은 사용자가 시스템 **'혈중 산소' 앱**을 열거나 watchOS 자동측정이 수행하며,
  손목이 정지해야 하므로 페달링 중엔 잘 안 잡힌다(휴식·신호대기 시 측정). 일부 지역 모델은 혈중 산소 기능이 비활성일 수 있다.
- **Done(종료) 루틴** — 의미 있는 라이딩이면 4가지를 한 번에 수행:
  1. **Apple 건강(HKWorkout)** 저장 — 폰이 거리 + **GPS 경로(`HKWorkoutRoute`)** 까지 첨부(건강 앱 지도 표시).
     워치는 워크아웃 세션만 종료(저장은 폰이 담당 → 중복 방지). 심박은 세션 동안 시스템이 기록.
  2. **iOS 캘린더** 요약 이벤트(`EventKit`, Cyclemeter 형식) — 제목 `"{자전거}, time {시간}, distance {거리} km"`,
     위치=경로명, 메모 `Route / Ride Time / Stopped Time / Distance`.
     **제목이 `Bike` 인 캘린더(iCloud/CalDAV 우선)** 에 기록 — 없으면 **iCloud 에 `Bike` 캘린더 자동 생성**.
     이름으로 캘린더를 찾고 새로 만들므로 **전체 접근**(`requestFullAccessToEvents` / `NSCalendarsFullAccessUsageDescription`) 필요.
  3. **GPX 내보내기** — 경로를 `.gpx` 로 저장. 지점별 **고도(ele)·시각·심박·속도**
     (Garmin `gpxtpx:TrackPointExtension`) 포함. 위치: **iCloud Drive > BikeCom > GPX**
     (iCloud 미사용 시 로컬 Files 앱 > 나의 iPhone > Bike > GPX).
     Routes 상세 화면의 **GPX 공유** 버튼(`ShareLink`)으로도 내보낼 수 있다.
  4. iCloud/로컬 **상세 기록**(`rides.json`) 추가 → Routes 탭.
- **iCloud 동기화**: 앱 iCloud 컨테이너를 iCloud Drive 에 **`BikeCom`** 폴더로 표시
  (`NSUbiquitousContainers` / `NSUbiquitousContainerName`). 그 안에 `rides.json`(상세+경로)과 `GPX/` 저장 →
  기기 간 동기화. iCloud 미사용 시 로컬 Documents 폴백. (Xcode 에서 **iCloud > iCloud Documents** Capability +
  컨테이너 `iCloud.com.jaisungnoh.bikecomputer` 설정 필요)
- 백그라운드에서도 블루투스·위치 계속 기록(`UIBackgroundModes`).

### 애플워치 측정 (watchOS 컴패니언 앱)

라이딩 **Start** → 아이폰이 `HKHealthStore.startWatchApp(toHandle:)` 로 워치 앱을 자동 실행
→ 워치가 `HKWorkoutSession` + `HKLiveWorkoutBuilder` 로 심박·`cyclingSpeed`·`cyclingCadence` 를 수집
→ `WatchConnectivity(WCSession)` 로 폰에 전송 → 대시보드에 표시. **Done** 시 워치 워크아웃을
종료하며 **HKWorkout(심박·거리 포함)을 건강 앱에 저장**한다. 워치 없이 탄 라이딩은 폰이 직접
HKWorkout 을 저장한다(둘 중 하나만 저장해 이중 계산 방지).

> 속도·케이던스 BLE 센서는 **워치 설정 > 블루투스** 에서 OS 에 페어링해야 워치가 읽는다(watchOS 10+).

```
아이폰 RideSession.start()
   └─ WatchSensorManager.startWatchWorkout() ─ startWatchApp(toHandle:) ─▶ 워치 앱 실행
                                                                            └─ WorkoutManager
                                                                                 HKLiveWorkoutBuilder
                                                                                 (심박·속도·케이던스)
아이폰 WatchSensorManager ◀─ WCSession {"hr":142,"speedMps":7.5,"cadence":88} ──────┘
아이폰 HealthStore  ◀─ HKStatisticsQuery(distanceCycling) ─ 누적 거리(이번달/올해/총)
```

### 지원 BLE 프로토콜 (표준 GATT)

| 서비스 | UUID | 특성 |
|--------|------|------|
| Cycling Speed and Cadence | `0x1816` | CSC Measurement `0x2A5B` |
| Heart Rate | `0x180D` | HR Measurement `0x2A37` |
| Battery | `0x180F` | Battery Level `0x2A19` |

스크린샷의 Wahoo / CYCPLUS / Magene 등 대부분의 시판 속도·케이던스 센서가 이 표준을 따른다.
(심박수는 애플워치를 기본으로 사용하며, BLE 심박 스트랩은 선택 보조 수단이다.)

## 빌드

이 저장소는 `.xcodeproj` 대신 **XcodeGen** `project.yml` 로 프로젝트를 정의한다.

```bash
brew install xcodegen      # 최초 1회
./scripts/build.sh         # xcodegen + (필요 시 watchOS 런타임) + 빌드
open BikeComputer.xcodeproj # Xcode 에서 실 기기로 실행
```

> 워치 컴패니언 앱이 포함되어 **watchOS 시뮬레이터 런타임**이 필요하다.
> 없으면 `xcodebuild -downloadPlatform watchOS` 로 설치하거나 `./scripts/build.sh` 가 자동 시도한다.

> 블루투스·GPS 는 **실제 기기**에서만 동작한다(시뮬레이터 불가). 서명 팀(`DEVELOPMENT_TEAM`)을
> Xcode 의 Signing & Capabilities 에서 본인 계정으로 지정한 뒤 실행한다.

## 구조

```
BikeComputer/                       # 아이폰 앱
  App/        BikeComputerApp.swift · ContentView · Info.plist · *.entitlements
  Design/     Theme.swift                 # 색상·폰트 토큰
  Models/     Units.swift · RideRecord.swift(+RideStore)
  Services/   BluetoothManager.swift      # CoreBluetooth: CSC(속도·케이던스) 파싱 — 폴백
              LocationManager.swift       # CoreLocation: GPS 속도·거리·트랙
              WatchSensorManager.swift    # WCSession: 워치 심박·속도·케이던스·SpO2 수신
              HealthStore.swift           # HealthKit: 누적 거리·SpO2 + 워크아웃(거리+경로) 저장
              CalendarLogger.swift        # EventKit: Done 시 캘린더 요약 이벤트
              GPXExporter.swift           # 경로 GPX 내보내기(Files 앱 GPX 폴더)
              GPXImporter.swift           # Cyclemeter 등 GPX 일괄 가져오기(파일/폴더)
              HealthWorkoutImporter.swift # Apple 건강 사이클링 워크아웃(경로·심박) 가져오기
              RideSession.swift           # 메인 뷰모델(상태머신·소스우선순위·통계·저장)
  Views/      ContentView(단일 화면) · DashboardView(⚙️ 메뉴) · MapTabView(+LiveMap/GoogleLiveMap)
              RoutesView(정렬·코스별·상세) · PastCoursesMapView(과거 코스 오버레이)
              DevicesView · MoreView · Components/MetricCell
  Assets.xcassets

BikeComputerWatch/                  # 애플워치 앱
  BikeComputerWatchApp.swift          # @main + WKApplicationDelegate(handle workout)
  WatchContentView.swift              # 실시간 심박 화면 + 시작/정지
  WorkoutManager.swift                # HKWorkoutSession·HKLiveWorkoutBuilder(심박·속도·케이던스) → WCSession 전송
  Info.plist · *.entitlements · Assets.xcassets
```

> 워치 앱은 아이폰 앱에 **임베드**되어 함께 설치된다(`project.yml` 의 `embed: true`).
> 두 타깃 모두 **HealthKit Capability** 와 서명 팀이 필요하다(Xcode Signing & Capabilities).

## 현재 한계 / 다음 단계

- 라이딩 거리는 GPS 트랙 기준이며, 누적 거리(이번달/올해/총)는 Apple 건강의 사이클링 거리 합으로 집계.
- 워치 속도/케이던스는 워치 설정에서 BLE 센서를 OS 에 페어링해야 동작(watchOS 10+).
- **지도는 Google 지도(표준 타입)** 사용 — 라이브 Map 탭(`GoogleLiveMap`), 라이딩 상세(`StaticRouteMap`),
  과거 코스 오버레이(`GoogleRouteMap`) 모두. `#if canImport(GoogleMaps)` 로 감싸 SDK·키가 있으면 Google,
  없으면 **Apple 지도(MapKit)로 폴백**(앱은 항상 빌드됨). 활성화하려면:
  ① `project.yml` 의 GoogleMaps SPM 의존성 유지(`xcodegen generate`) ② Google Cloud 에서 **Maps SDK for iOS**
  키 발급 ③ `Info.plist` 의 `GMSApiKey` 에 키 입력. 키가 비어 있으면 자동으로 Apple 지도로 표시.
- **과거 코스 오버레이**(Map 탭 → "과거 코스"): 코스별 대표 경로를 한 지도에 색별로 겹쳐 표시.
- 랩(구간) 기록 · 사용자 자전거 다중 프로필 미구현. (GPX 내보내기/가져오기·HealthKit 경로·iCloud 동기화는 구현됨)
- **데이터 가져오기**(More 탭): ① **Apple 건강에서 가져오기** — 건강의 사이클링 워크아웃(거리·시간·평균/최대
  심박·최대 케이던스 + 경로)을 Routes 로 채움(이미 건강에 있을 때 최선). ② **Cyclemeter GPX 가져오기** —
  여러 `.gpx` 파일/폴더 선택(건강에 없거나 경로 없는 기록용). 둘 다 **시작시각 중복 제외**.
  누적 거리는 건강 기준이라 ①은 이미 반영되어 있고 가져오기는 Routes 표시용이다.
- 앱 아이콘 이미지 미포함(placeholder, 폰·워치 공통).
- `startWatchApp(toHandle:)` 는 워치 앱이 설치되어 있어야 동작. 워치에서 직접 **시작** 버튼으로도 측정 가능.
