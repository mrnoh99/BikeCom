#!/usr/bin/env bash
# Watch 앱이 빌드·임베드 되는지 확인
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"

echo "==> xcodegen"
xcodegen generate

echo "==> 타깃 확인"
"$XCODEBUILD" -project BikeComputer.xcodeproj -list | grep -E 'Targets:|BikeComputer'

echo "==> 빌드 (iPhone + Watch)"
"$XCODEBUILD" \
  -project BikeComputer.xcodeproj \
  -scheme BikeComputer \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO

APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeComputer.app' -not -path '*Index*' 2>/dev/null | head -1)
WATCH="$APP/PlugIns/BikeComputerWatch.app"

echo ""
echo "==> 결과"
if [[ -z "$APP" ]]; then
  echo "❌ BikeComputer.app 없음"
  exit 1
fi
echo "✓ iPhone 앱: $APP"

if [[ ! -d "$WATCH" ]]; then
  echo "❌ Watch 앱 없음: $WATCH"
  echo "   → Product → Scheme → Edit Scheme → Build 에 BikeComputerWatch 체크"
  exit 1
fi
echo "✓ Watch 앱: $WATCH"

if [[ ! -f "$WATCH/Assets.car" ]]; then
  echo "❌ Watch 아이콘(Assets.car) 없음 — 실기기 설치 실패 원인"
  exit 1
fi
echo "✓ Watch 아이콘: Assets.car"

plutil -p "$WATCH/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleDisplayName|WKCompanion' || true

echo ""
echo "✅ 빌드 OK — Watch 앱은 iPhone 앱 안에 포함되어 있습니다."
echo ""
echo "⚠️  check_watch.sh 는 기기에 설치하지 않습니다."
echo "실기기 설치:"
echo "  1) Xcode: BikeComputer 스킴 → iPhone → Team 서명 → ⌘R"
echo "  2) 또는: ./scripts/install_device.sh <iPhone-UDID>"
echo "  3) iPhone Watch 앱 → 일반 → BikeComputer → 설치 ON"
echo "  4) Watch: 설정 → 개발자 모드 ON (최초 1회)"
