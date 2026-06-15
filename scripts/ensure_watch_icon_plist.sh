#!/usr/bin/env bash
# Watch 앱 Info.plist 에 CFBundleIconName 을 보장한다(없으면 watchOS 기기 설치 실패).
# 인자: 대상 Info.plist 경로 (없으면 Xcode 빌드 환경 변수 사용)
set -euo pipefail

PLIST="${1:-${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}/Info.plist}"
ICON_NAME="${ASSETCATALOG_COMPILER_APPICON_NAME:-AppIcon}"

if [[ ! -f "$PLIST" ]]; then
  echo "warning: ensure_watch_icon_plist — plist not found: $PLIST" >&2
  exit 0
fi

/usr/libexec/PlistBuddy -c "Add :CFBundleIcons dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName string ${ICON_NAME}" "$PLIST"
# xcodegen 이 넣는 iOS 전용 키 — watch 번들 검증을 깨뜨릴 수 있음
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons:UINewsstandIcon" "$PLIST" 2>/dev/null || true

if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$PLIST" >/dev/null 2>&1; then
  echo "error: failed to set CFBundleIconName on $PLIST" >&2
  exit 1
fi

# Xcode dependency analysis: output stamp so the run script phase can be skipped when unchanged.
if [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
  mkdir -p "$DERIVED_FILE_DIR"
  touch "$DERIVED_FILE_DIR/ensure_watch_icon_plist.stamp"
fi
