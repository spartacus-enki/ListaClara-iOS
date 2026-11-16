#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
ci_step unsigned-iphone-build
ci_macos
ci_version
xcodebuild -project ListaClara.xcodeproj -scheme ListaClara -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DeviceDerivedData \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$IOS_VERSION" CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER" \
  build 2>&1 | tee build/logs/unsigned-iphone-build.log
printf '%s\n' 'Unsigned device build only: this is NOT an installable IPA.'
