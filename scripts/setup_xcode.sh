#!/usr/bin/env bash
# BikeComputer — Xcode 프로젝트 생성 + Watch 타깃 확인 + Xcode 열기
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen 이 없습니다. 먼저 실행:"
  echo "   brew install xcodegen"
  exit 1
fi

echo "==> 1/3 Xcode 프로젝트 생성 (project.yml → BikeComputer.xcodeproj)"
xcodegen generate

echo "==> 2/3 Watch 타깃 확인"
if ! "$XCODEBUILD" -project BikeComputer.xcodeproj -list 2>/dev/null | grep -q BikeComputerWatch; then
  echo "❌ BikeComputerWatch 타깃이 없습니다. project.yml 을 확인하세요."
  exit 1
fi

if ! grep -q 'BikeComputerWatch' BikeComputer.xcodeproj/xcshareddata/xcschemes/BikeComputer.xcscheme; then
  echo "❌ BikeComputer 스킴에 Watch 빌드가 없습니다."
  exit 1
fi

echo "   ✓ 타깃: BikeComputer, BikeComputerWatch"
echo "   ✓ 스킴: BikeComputer (Watch 포함 빌드)"

echo "==> 3/4 빌드 검증 (Watch 포함)"
if "$XCODEBUILD" \
  -project BikeComputer.xcodeproj \
  -scheme BikeComputer \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO >/tmp/bike_watch_check.log 2>&1; then
  APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeComputer.app' -not -path '*Index*' 2>/dev/null | head -1)
  if [[ -n "$APP" && -d "$APP/PlugIns/BikeComputerWatch.app" ]]; then
    echo "   ✓ PlugIns/BikeComputerWatch.app 생성됨"
  else
    echo "   ❌ Watch 앱 임베드 실패 — 로그: /tmp/bike_watch_check.log"
    exit 1
  fi
else
  echo "   ❌ 빌드 실패 — 로그: /tmp/bike_watch_check.log"
  tail -20 /tmp/bike_watch_check.log
  exit 1
fi

echo "==> 4/4 Xcode 열기"
open BikeComputer.xcodeproj

cat <<'EOF'

다음 단계 (Xcode):
  1. 상단 스킴: BikeComputer  (BikeComputerWatch 아님)
  2. 기기: 본인 iPhone (시뮬레이터 X)
  3. 왼쪽 파란 아이콘 BikeComputer → TARGETS:
       BikeComputer        ← iPhone
       BikeComputerWatch   ← Watch (둘 다 있어야 함)
  4. Signing & Capabilities → BikeComputer + BikeComputerWatch 둘 다 Team 설정
  5. ⌘R Run 후 빌드 로그에 "Build target BikeComputerWatch" 있는지 확인

Watch 앱은 iPhone 앱 PlugIns 안에 묶여 설치됩니다.
설치 후: iPhone Watch 앱 → 일반 → BikeComputer → Apple Watch에 설치 ON

문제 시: ./scripts/check_watch.sh

EOF
