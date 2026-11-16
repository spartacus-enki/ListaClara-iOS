#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
ci_step signed-adhoc-ipa
ci_macos
ci_version
: "${IOS_TEST_DEVICE_UDID:?Configure the target iPhone UDID as a secret Codemagic variable in lista_clara_ios_adhoc}"
# Codemagic environment.ios_signing imports the owner's uploaded certificate/profile.
# No Apple account secret is stored in the repository or printed here.
xcode-project use-profiles --project ListaClara.xcodeproj \
  --archive-method ad-hoc --export-options-plist "$CI_ROOT/build/export-options.plist"
xcode-project build-ipa --project ListaClara.xcodeproj --scheme ListaClara --config Release \
  --archive-directory build/ios/xcarchive --ipa-directory build/ios/export \
  --export-options-plist "$CI_ROOT/build/export-options.plist" \
  --archive-xcargs "MARKETING_VERSION=$IOS_VERSION CURRENT_PROJECT_VERSION=$IOS_BUILD_NUMBER COMPILER_INDEX_STORE_ENABLE=NO" \
  2>&1 | tee build/logs/archive-export.log
python3 ci/verify_ipa.py --directory build/ios/export --bundle-id "${IOS_BUNDLE_ID:-mx.listaclara.ios}" \
  --output build/evidence/ipa-verification.json

# Only verified exports enter the artifact glob advertised as installable.
mkdir -p build/ios/ipa
mv build/ios/export/*.ipa build/ios/ipa/
