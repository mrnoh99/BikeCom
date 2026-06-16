#!/usr/bin/env bash
# Xcode ⌘R 직후 또는 수동으로 Watch 앱만 재설치한다.
# iPhone Watch 앱 동기화 대신 devicectl 로 Watch 에 직접 설치.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# 시뮬레이터 빌드면 건너뜀
case "${PLATFORM_NAME:-}${EFFECTIVE_PLATFORM_NAME:-}" in
  *simulator*) exit 0 ;;
esac

pick_watch_id() {
  local json
  json="$(mktemp)"
  trap 'rm -f "$json"' RETURN
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
  python3 - "$json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    props = d.get("deviceProperties") or {}
    hw = d.get("hardwareProperties") or {}
    conn = d.get("connectionProperties") or {}
    name = props.get("name") or ""
    ident = d.get("identifier") or ""
    platform = (hw.get("platform") or "").lower()
    device_type = (hw.get("deviceType") or "").lower()
    pairing = (conn.get("pairingState") or "").lower()
    if pairing != "paired":
        continue
    if device_type == "applewatch" or "watch" in platform or "watch" in name.lower():
        print(f"WATCH_NAME={name}")
        print(f"WATCH_INSTALL_ID={ident}")
        break
PY
}

resolve_watch_app() {
  local app=""
  if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${WRAPPER_NAME:-}" && -d "${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Watch/BikeComWatch.app" ]]; then
    app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
  else
    app=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeCom.app' -not -path '*Index*' 2>/dev/null | head -1)
  fi
  if [[ -z "$app" || ! -d "$app/Watch/BikeComWatch.app" ]]; then
    echo "❌ BikeComWatch.app 을 찾지 못했습니다. BikeCom 스킴으로 iPhone 실기기 빌드 후 다시 시도하세요."
    exit 1
  fi
  echo "$app/Watch/BikeComWatch.app"
}

WATCH_APP="$(resolve_watch_app)"

WATCH_NAME=""
WATCH_INSTALL_ID=""
while IFS= read -r line; do
  case "$line" in
    WATCH_NAME=*) WATCH_NAME="${line#WATCH_NAME=}" ;;
    WATCH_INSTALL_ID=*) WATCH_INSTALL_ID="${line#WATCH_INSTALL_ID=}" ;;
  esac
done < <(pick_watch_id)

if [[ -z "${WATCH_INSTALL_ID:-}" ]]; then
  echo "⚠️ 페어링된 Apple Watch 없음 — Watch 설치 건너뜀"
  exit 0
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :WKApplication' "$WATCH_APP/Info.plist" 2>/dev/null)" != "true" ]]; then
  echo "❌ WKApplication != true — xcodegen generate 후 재빌드"
  exit 1
fi
if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$WATCH_APP/Info.plist" >/dev/null 2>&1; then
  echo "❌ Watch CFBundleIconName 없음 — 설치 실패 원인"
  exit 1
fi

echo "==> Watch 설치: $WATCH_NAME"
echo "    $WATCH_APP"

for attempt in 1 2; do
  if [[ "$attempt" -gt 1 ]]; then
    echo "    재시도 ($attempt/2)…"
    sleep 2
  fi
  if xcrun devicectl device install app --device "$WATCH_INSTALL_ID" "$WATCH_APP"; then
    echo "✓ Watch 설치 완료 (com.jaisungnoh.bikecom.watchkitapp)"
    exit 0
  fi
done

echo "❌ Watch 설치 실패"
echo "   → Watch 개발자 모드 ON, iPhone Watch 앱에서 \"Apple Watch에 설치\" OFF"
echo "   → ./scripts/install_device.sh"
exit 1
