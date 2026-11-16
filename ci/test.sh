#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
ci_step swift-and-simulator-tests
ci_macos
ci_version
swift test 2>&1 | tee build/logs/swift-test.log
xcrun simctl list devices available --json > build/evidence/simulators.json
CI_SIMULATOR_ID="$(python3 - <<'PY'
import json
from pathlib import Path
j=json.loads(Path('build/evidence/simulators.json').read_text())
devices=[d for runtime,ds in j['devices'].items() if 'iOS' in runtime for d in ds if d.get('isAvailable') and d.get('name','').startswith('iPhone')]
if not devices: raise SystemExit('No available iPhone iOS simulator installed in selected Xcode image')
devices.sort(key=lambda d: d.get('state') != 'Booted')
print(devices[0]['udid'])
PY
)"
xcrun simctl boot "$CI_SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$CI_SIMULATOR_ID" -b
xcodebuild -project ListaClara.xcodeproj -scheme ListaClara -configuration Debug \
  -destination "platform=iOS Simulator,id=$CI_SIMULATOR_ID" \
  -derivedDataPath build/DerivedData -resultBundlePath build/results/ListaClara.xcresult \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$IOS_VERSION" CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER" \
  test 2>&1 | tee build/logs/xcode-test.log
