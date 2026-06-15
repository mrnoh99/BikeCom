#!/usr/bin/env bash
# BikeCom — 서명 포함 iPhone + Watch companion 설치
#
# devicectl UUID(B79C5D47-…) 와 xcodebuild UUID(00008101-…) 가 다릅니다.
# 이 스크립트는 기기 이름/어느 쪽 UUID 로도 빌드·설치를 맞춥니다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen 필요: brew install xcodegen"
  exit 1
fi

echo "==> 1. 프로젝트 생성"
xcodegen generate

# xcodebuild 가 인식하는 실기기 iOS id (00008101-… 형식)
xcode_ios_id_for_name() {
  local name="$1"
  "$XCODEBUILD" -project BikeCom.xcodeproj -scheme BikeCom -showdestinations 2>/dev/null \
    | grep -E 'platform:iOS, arch:arm64, id:[0-9A-Fa-f-]+, name:' \
    | grep -v Simulator \
    | while IFS= read -r line; do
        if echo "$line" | grep -Fq "name:${name} }"; then
          echo "$line" | sed -E 's/.*id:([0-9A-Fa-f-]+),.*/\1/'
          break
        fi
      done
}

# devicectl JSON → iPhone(설치용 id) / Watch(설치용 id) / 이름
pick_devices() {
  local hint="${1:-}"
  local json
  json="$(mktemp)"
  trap 'rm -f "$json"' RETURN
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true

  python3 - "$hint" "$json" <<'PY'
import json, sys
hint = sys.argv[1].strip().lower()
path = sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
devices = data.get("result", {}).get("devices", [])
phones, watches = [], []
for d in devices:
    props = d.get("deviceProperties") or {}
    hw = d.get("hardwareProperties") or {}
    conn = d.get("connectionProperties") or {}
    name = props.get("name") or ""
    ident = d.get("identifier") or ""
    platform = (hw.get("platform") or "").lower()
    device_type = (hw.get("deviceType") or "").lower()
    transport = (conn.get("transportType") or "").lower()
    pairing = (conn.get("pairingState") or "").lower()
    if device_type == "iphone" or (platform == "ios" and "iphone" in name.lower()):
        if pairing == "unpaired" or transport == "unavailable":
            continue
        phones.append({
            "name": name, "id": ident,
            "connected": transport in ("wired", "localnetwork") or "connected" in transport,
        })
    elif device_type == "applewatch" or "watch" in platform or "watch" in name.lower():
        if pairing == "unpaired":
            continue
        watches.append({"name": name, "id": ident, "paired": pairing == "paired"})

def match(dev, hint):
    if not hint:
        return True
    h = hint.replace(" ", "")
    return hint in dev["name"].lower() or h in dev["id"].lower().replace("-", "")

phone = None
if hint:
    for p in phones:
        if match(p, hint):
            phone = p
            break
else:
    phone = next((p for p in phones if p["connected"]), None)
    if not phone and phones:
        phone = phones[0]

watch = next((w for w in watches if w.get("paired")), None)
if phone:
    print(f"PHONE_NAME={phone['name']}")
    print(f"PHONE_INSTALL_ID={phone['id']}")
if watch:
    print(f"WATCH_NAME={watch['name']}")
    print(f"WATCH_INSTALL_ID={watch['id']}")
PY
}

DEVICE_HINT="${1:-}"
while IFS= read -r line; do
  case "$line" in
    PHONE_NAME=*) PHONE_NAME="${line#PHONE_NAME=}" ;;
    PHONE_INSTALL_ID=*) PHONE_INSTALL_ID="${line#PHONE_INSTALL_ID=}" ;;
    WATCH_NAME=*) WATCH_NAME="${line#WATCH_NAME=}" ;;
    WATCH_INSTALL_ID=*) WATCH_INSTALL_ID="${line#WATCH_INSTALL_ID=}" ;;
  esac
done < <(pick_devices "$DEVICE_HINT")

if [[ -z "${PHONE_INSTALL_ID:-}" ]]; then
  echo ""
  echo "연결된 iPhone 을 찾지 못했습니다."
  echo ""
  echo "devicectl (설치용 UUID):"
  xcrun devicectl list devices 2>/dev/null | grep -i iphone || true
  echo ""
  echo "xcodebuild (빌드용 UUID):"
  "$XCODEBUILD" -project BikeCom.xcodeproj -scheme BikeCom -showdestinations 2>/dev/null \
    | grep -E 'platform:iOS, arch:arm64' | grep -v Simulator || true
  echo ""
  echo "사용법:"
  echo "  ./scripts/install_device.sh                 # 연결된 iPhone 자동 선택"
  echo "  ./scripts/install_device.sh iPhone12mini    # 이름 일부"
  echo "  ./scripts/install_device.sh 00008101-...    # xcodebuild UUID"
  echo "  ./scripts/install_device.sh B79C5D47-...    # devicectl UUID"
  exit 1
fi

BUILD_ID="$(xcode_ios_id_for_name "$PHONE_NAME")"
if [[ -z "$BUILD_ID" ]]; then
  echo "❌ xcodebuild 가 iPhone 을 인식하지 못합니다: $PHONE_NAME"
  echo "   Xcode → Window → Devices and Simulators 에서 기기 신뢰(Trust) 확인"
  exit 1
fi

echo "==> 2. iPhone 빌드 (Watch 포함)"
echo "   iPhone: $PHONE_NAME"
echo "   build id: $BUILD_ID"
echo "   install id: $PHONE_INSTALL_ID"
"$XCODEBUILD" \
  -project BikeCom.xcodeproj \
  -scheme BikeCom \
  -destination "id=${BUILD_ID}" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build

APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeCom.app' -not -path '*Index*' -newer BikeCom.xcodeproj 2>/dev/null | head -1)
if [[ -z "$APP" || ! -d "$APP/Watch/BikeComWatch.app" ]]; then
  echo "❌ BikeCom.app 또는 Watch/BikeComWatch.app 없음"
  exit 1
fi
echo "   ✓ $APP"
echo "   ✓ Watch: Watch/BikeComWatch.app ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$APP/Watch/BikeComWatch.app/Info.plist" 2>/dev/null || echo 'icon?'))"

uninstall_bundle() {
  local device_id="$1"
  local bundle_id="$2"
  xcrun devicectl device uninstall app --device "$device_id" "$bundle_id" >/dev/null 2>&1 || true
}

echo "==> 3. 기존 앱 제거 (설치 실패·동기화 꼬임 방지)"
if [[ -n "${WATCH_INSTALL_ID:-}" ]]; then
  echo "   Watch: com.jaisungnoh.bikecom.watchkitapp (+ widget)"
  uninstall_bundle "$WATCH_INSTALL_ID" com.jaisungnoh.bikecom.watchkitapp.widget
  uninstall_bundle "$WATCH_INSTALL_ID" com.jaisungnoh.bikecom.watchkitapp
fi
echo "   iPhone: com.jaisungnoh.bikecom"
uninstall_bundle "$PHONE_INSTALL_ID" com.jaisungnoh.bikecom

echo "==> 4. iPhone에 설치"
if xcrun devicectl device install app --device "$PHONE_INSTALL_ID" "$APP"; then
  echo "   ✓ iPhone 설치 완료"
else
  echo "   ❌ iPhone 설치 실패 — Xcode에서 BikeCom 스킴 + iPhone 선택 → ⌘R"
  exit 1
fi

WATCH_APP="$APP/Watch/BikeComWatch.app"
echo ""
echo "==> 5. Watch에 직접 설치"
if [[ -z "${WATCH_INSTALL_ID:-}" ]]; then
  echo "   ⚠️ 페어링된 Watch 없음 (devicectl)"
  echo "   → iPhone Watch 앱 → 일반 → BikeCom → Apple Watch에 설치 ON"
else
  echo "   Watch: $WATCH_NAME ($WATCH_INSTALL_ID)"
  if xcrun devicectl device install app --device "$WATCH_INSTALL_ID" "$WATCH_APP"; then
    echo "   ✓ Watch 설치 완료"
  else
    echo "   ❌ Watch 직접 설치 실패"
    echo "   → Watch 설정 → 개인정보 보호 및 보안 → 개발자 모드 ON → 재부팅"
    echo "   → iPhone·Watch 재부팅 후 ./scripts/install_device.sh 재실행"
    echo "   → Xcode ⌘R 대신 이 스크립트 사용 (Watch 동기화 설치는 실패할 수 있음)"
  fi
fi

cat <<'EOF'

참고:
  • ./scripts/build.sh 는 컴파일만 합니다 (CODE_SIGNING_ALLOWED=NO → 기기 설치 없음).
  • Xcode Run(⌘R) 은 BikeCom 스킴 + iPhone 대상 (BikeComWatch 단독 Run 은 Watch 만).
  • Watch에 "The app could not be installed at this time" 이 뜨면:
      1) 이 스크립트로 iPhone + Watch 직접 설치 (Watch 앱 동기화 토글 OFF)
      2) iPhone Watch 앱 → 일반 → BikeCom → "Apple Watch에 설치" 끄기
      3) iPhone 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 신뢰
  • Watch 개발자 모드 (최초 1회): Watch 설정 → 개인정보 보호 및 보안 → 개발자 모드
  • 서명: Xcode TARGETS → BikeCom + BikeComWatch + BikeComWatchWidget → Team 9AWEB9NYHH

EOF
