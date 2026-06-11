#!/usr/bin/env bash
# BikeComputer 빌드 스크립트
# - XcodeGen 으로 .xcodeproj 생성
# - watchOS 시뮬레이터 런타임이 없으면 자동 다운로드 시도
# - iOS + watch 컴패니언 앱 빌드
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen 이 필요합니다: brew install xcodegen"
  exit 1
fi

echo "==> Xcode 프로젝트 생성"
xcodegen generate

echo "==> Swift 패키지 의존성 해결"
"$XCODEBUILD" -project BikeComputer.xcodeproj -scheme BikeComputer -resolvePackageDependencies

# 워치 컴패니언 스킴은 watchOS 시뮬레이터 런타임이 필요하다.
if ! "$XCODEBUILD" -project BikeComputer.xcodeproj -scheme BikeComputer -showdestinations 2>/dev/null \
  | grep -q 'watchOS Simulator'; then
  echo "==> watchOS 시뮬레이터 런타임 다운로드 (최초 1회, 수 GB)"
  "$XCODEBUILD" -downloadPlatform watchOS
fi

echo "==> 빌드"
"$XCODEBUILD" \
  -project BikeComputer.xcodeproj \
  -scheme BikeComputer \
  -destination 'generic/platform=iOS' \
  -configuration "${CONFIGURATION:-Debug}" \
  build \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  ONLY_ACTIVE_ARCH="${ONLY_ACTIVE_ARCH:-NO}"

echo "==> BUILD SUCCEEDED"

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "NO" ]]; then
  echo ""
  echo "참고: CODE_SIGNING_ALLOWED=NO 이므로 iPhone/Watch에 설치되지 않습니다."
  echo "실기기 설치: xcodegen generate && open BikeComputer.xcodeproj"
  echo "  → BikeComputer 스킴, 본인 Team 서명, iPhone에 Run(⌘R)"
  echo "  → Watch 앱은 iPhone 설치 후 Watch 앱에서 'Apple Watch에 설치' 확인"
fi
