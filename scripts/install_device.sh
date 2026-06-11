#!/usr/bin/env bash
# BikeComputer — 서명 포함 iPhone 설치 (Watch companion 포함)
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
  -project BikeComputer.xcodeproj \
  -scheme BikeComputer \
  -destination "id=${DEVICE_ID}" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build

APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeComputer.app' -not -path '*Index*' -newer BikeComputer.xcodeproj 2>/dev/null | head -1)
if [[ -z "$APP" || ! -d "$APP/PlugIns/BikeComputerWatch.app" ]]; then
  echo "❌ BikeComputer.app 또는 Watch companion 없음"
  exit 1
fi
echo "   ✓ $APP"
echo "   ✓ Watch: PlugIns/BikeComputerWatch.app"

echo "==> 3. iPhone에 설치"
if xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>/dev/null; then
  echo "   ✓ devicectl 설치 완료"
elif xcrun devicectl device install app --device "$DEVICE_ID" "$APP"; then
  echo "   ✓ devicectl 설치 완료"
else
  echo "   ⚠️ devicectl 실패 — Xcode에서 ⌘R 로 설치하세요"
fi

cat <<'EOF'

==> 4. Watch 설치 (iPhone에서 직접)

  ① Watch 개발자 모드 (최초 1회)
     Watch 설정 → 개인정보 보호 및 보안 → 개발자 모드 → ON → 재부팅

  ② iPhone Watch 앱
     일반 → (아래로 스크롤) → BikeComputer
     → "Apple Watch에 설치" 또는 "쇼 앱" ON

  ③ 안 보이면
     - iPhone·Watch에서 BikeComputer 삭제
     - Xcode: Product → Clean Build Folder
     - Xcode: BikeComputer 스킴 + iPhone 선택 → ⌘R
     - Watch 재부팅

  ④ Xcode 서명 (둘 다 Team 필요)
     TARGETS → BikeComputer → Signing & Capabilities → Team
     TARGETS → BikeComputerWatch → Signing & Capabilities → Team

EOF
