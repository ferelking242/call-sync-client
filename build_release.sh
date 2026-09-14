#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CallSync Client — Release build script
# Usage: ./build_release.sh [keystore.jks] [store_pass] [key_alias] [key_pass]
# If no keystore args provided, builds unsigned release APK.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║  CallSync Client — Release Builder   ║"
echo "╚══════════════════════════════════════╝"

# Check Flutter is installed
if ! command -v flutter &>/dev/null; then
  echo "❌  Flutter SDK not found. Install from https://flutter.dev"
  exit 1
fi

flutter --version

# Get dependencies
echo ""
echo "📦  Getting dependencies…"
flutter pub get

# Run analysis (non-fatal)
echo ""
echo "🔍  Running analysis…"
flutter analyze --no-fatal-infos || true

# Build
echo ""
if [ "${1:-}" != "" ]; then
  echo "🔑  Building SIGNED release APK…"
  export KEYSTORE_PATH="${1}"
  export STORE_PASSWORD="${2:-}"
  export KEY_ALIAS="${3:-upload}"
  export KEY_PASSWORD="${4:-}"
fi

flutter build apk --release --split-per-abi \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --tree-shake-icons

APK_DIR="build/app/outputs/flutter-apk"

echo ""
echo "✅  Build complete!"
find "$APK_DIR" -name '*-release.apk' -maxdepth 1 -print -exec du -h {} \;
echo ""
echo "Install on connected device:"
echo "   adb install -r $APK_DIR/app-arm64-v8a-release.apk"
