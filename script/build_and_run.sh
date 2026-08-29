#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TomorrowPet"
BUNDLE_ID="com.tomorrowpet.desktop"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/tomorrow-pet"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
MODULE_CACHE="$BUILD_ROOT/module-cache"
SWIFTPM_CACHE="$BUILD_ROOT/swiftpm-cache"
BUILD_LOG="$BUILD_ROOT/swift-build.log"

mkdir -p "$BUILD_ROOT" "$MODULE_CACHE" "$SWIFTPM_CACHE"

prepare_compatible_toolchain() {
  local system_sdk compatible_sdk compiler_signature sdk_interface sdk_signature overlay empty_map
  system_sdk="$(cd "$(xcrun --sdk macosx --show-sdk-path)" && pwd -P)"
  compatible_sdk="$BUILD_ROOT/MacOSX.sdk"
  compiler_signature="$(swiftc -version | sed -n 's/.*(\(swiftlang-[^ ]*\).*/\1/p')"
  sdk_interface="$system_sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
  sdk_signature="$(sed -n 's/.*(\(swiftlang-[^ ]*\).*/\1/p' "$sdk_interface" | head -1)"

  if [[ "$compiler_signature" != "$sdk_signature" ]]; then
    if [[ ! -d "$compatible_sdk" ]] || ! rg -q "$compiler_signature" "$compatible_sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"; then
      rm -rf "$compatible_sdk"
      cp -cR "$system_sdk" "$compatible_sdk"
      find "$compatible_sdk" -name '*.swiftinterface' -print0 \
        | xargs -0 sed -i '' "s/$sdk_signature/$compiler_signature/g"
    fi
  else
    compatible_sdk="$system_sdk"
  fi

  empty_map="$BUILD_ROOT/empty.modulemap"
  overlay="$BUILD_ROOT/swift-overlay.yaml"
  : > "$empty_map"
  printf "%s\n" \
    "{" \
    "  'version': 0," \
    "  'case-sensitive': 'false'," \
    "  'roots': [{" \
    "    'type': 'file'," \
    "    'name': '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap'," \
    "    'external-contents': '$empty_map'" \
    "  }]" \
    "}" > "$overlay"

  COMPATIBLE_SDK="$compatible_sdk"
  VFS_OVERLAY="$overlay"
}

build_directly() {
  prepare_compatible_toolchain
  local source_files=()
  while IFS= read -r source_file; do
    source_files+=("$source_file")
  done < <(find "$ROOT_DIR/Sources/TomorrowPet" -name '*.swift' -print | sort)

  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    -vfsoverlay "$VFS_OVERLAY" \
    -sdk "$COMPATIBLE_SDK" \
    -target "arm64-apple-macosx$MIN_SYSTEM_VERSION" \
    -module-cache-path "$MODULE_CACHE" \
    -g \
    -o "$BUILD_ROOT/$APP_NAME" \
    "${source_files[@]}"

  BUILD_BINARY="$BUILD_ROOT/$APP_NAME"
}

build_app() {
  export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
  export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"

  if [[ -f "$BUILD_ROOT/use-direct-build" ]]; then
    build_directly
  elif swift build --cache-path "$SWIFTPM_CACHE" >"$BUILD_LOG" 2>&1; then
    BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
  elif rg -q 'Invalid manifest|SDK is not supported|SwiftShims|PackageDescription' "$BUILD_LOG"; then
    echo "SwiftPM toolchain mismatch detected; using the project-local compatibility build."
    : > "$BUILD_ROOT/use-direct-build"
    build_directly
  else
    cat "$BUILD_LOG" >&2
    exit 1
  fi
}

stage_bundle() {
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>明日团子</string>
  <key>CFBundleDisplayName</key>
  <string>明日团子</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>明日团子读取你的日历，以显示明天和未来七天的固定安排，并帮助你规划任务。</string>
  <key>NSCalendarsUsageDescription</key>
  <string>明日团子读取你的日历，以帮助你制定每日和每周计划。</string>
</dict>
</plist>
PLIST

  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
}

run_self_tests() {
  prepare_compatible_toolchain
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    -vfsoverlay "$VFS_OVERLAY" \
    -sdk "$COMPATIBLE_SDK" \
    -target "arm64-apple-macosx$MIN_SYSTEM_VERSION" \
    -module-cache-path "$MODULE_CACHE" \
    -o "$BUILD_ROOT/TomorrowPetSelfTests" \
    "$ROOT_DIR/Sources/TomorrowPet/Models/TaskModels.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Models/PlanningModels.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Models/GoogleCalendarModels.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Models/DailySOPModels.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Stores/TaskStore.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Stores/DailySOPStore.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Stores/AppPreferences.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Services/KeychainService.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Services/GoogleOAuthService.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Services/GoogleCalendarService.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Services/CalendarService.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Services/OpenAIPlanningService.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Services/OpenAITaskBreakdownService.swift" \
    "$ROOT_DIR/Sources/TomorrowPet/Support/AppNotifications.swift" \
    "$ROOT_DIR/script/SelfTest.swift"
  "$BUILD_ROOT/TomorrowPetSelfTests"
}

if [[ "$MODE" == "--test" || "$MODE" == "test" ]]; then
  run_self_tests
  exit 0
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
build_app
stage_bundle

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify|--test]" >&2
    exit 2
    ;;
esac
