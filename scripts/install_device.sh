#!/usr/bin/env bash
# BikeCom — 서명 포함 iPhone 설치 (Watch companion 포함)
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

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  echo ""
  echo "연결된 iPhone (시뮬레이터 제외):"
  xcrun xctrace list devices 2>/dev/null | grep -E 'iPhone' | grep -v Simulator || true
  echo ""
  echo "사용법: ./scripts/install_device.sh <iPhone-UDID>"
  echo "UDID 은 괄호 안 문자열입니다. 예: ./scripts/install_device.sh 00008101-..."
  exit 1
fi

echo "==> 2. iPhone 빌드 (Watch 포함)"
"$XCODEBUILD" \
  -project BikeCom.xcodeproj \
  -scheme BikeCom \
  -destination "id=${DEVICE_ID}" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build

APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeCom.app' -not -path '*Index*' -newer BikeCom.xcodeproj 2>/dev/null | head -1)
if [[ -z "$APP" || ! -d "$APP/Watch/BikeComWatch.app" ]]; then
  echo "❌ BikeCom.app 또는 Watch companion 없음"
  exit 1
fi
echo "   ✓ $APP"
echo "   ✓ Watch: Watch/BikeComWatch.app"

echo "==> 3. iPhone에 설치"
if xcrun devicectl device install app --device "$DEVICE_ID" "$APP"; then
  echo "   ✓ iPhone 설치 완료"
else
  echo "   ❌ iPhone 설치 실패 — Xcode에서 BikeCom 스킴 + iPhone 선택 → ⌘R"
  exit 1
fi

WATCH_APP="$APP/Watch/BikeComWatch.app"
echo ""
echo "==> 4. Watch에 직접 설치"
WATCH_LINES="$(xcrun xctrace list devices 2>/dev/null | grep -E 'Apple Watch' | grep -v Simulator || true)"
if [[ -z "$WATCH_LINES" ]]; then
  echo "   ⚠️ 연결된 Watch 없음"
  echo "   → iPhone Watch 앱 → 일반 → BikeCom → Apple Watch에 설치 ON"
else
  INSTALLED=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    WATCH_ID="$(echo "$line" | sed -E 's/.*\(([0-9A-Fa-f-]+)\)[[:space:]]*$/\1/')"
    WATCH_NAME="$(echo "$line" | sed -E 's/[[:space:]]*\([0-9A-Fa-f-]+\)[[:space:]]*$//')"
    echo "   → $WATCH_NAME ($WATCH_ID)"
    if xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"; then
      echo "   ✓ Watch 설치 완료"
      INSTALLED=1
    else
      echo "   ❌ Watch 설치 실패"
    fi
  done <<< "$WATCH_LINES"
  if [[ "$INSTALLED" -eq 0 ]]; then
    echo "   → iPhone Watch 앱 → 일반 → BikeCom → Apple Watch에 설치 ON"
  fi
fi

cat <<'EOF'

참고:
  • ./scripts/build.sh 는 컴파일만 합니다(CODE_SIGNING_ALLOWED=NO → 기기 설치 없음).
  • Xcode Device Monitor 에 "No app installed" 가 보이면 이 스크립트 또는 Xcode ⌘R 로 설치하세요.
  • 스킴은 BikeCom (BikeComWatch 단독 Run 은 Watch 만 대상 — companion 은 iPhone 경유).

Watch 개발자 모드 (최초 1회): Watch 설정 → 개인정보 보호 및 보안 → 개발자 모드 → ON → 재부팅
Xcode 서명: TARGETS → BikeCom + BikeComWatch 둘 다 Team 설정

EOF
