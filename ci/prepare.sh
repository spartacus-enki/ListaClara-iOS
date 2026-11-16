#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
ci_step preflight
ci_macos
ci_version
PYTHONDONTWRITEBYTECODE=1 python3 ci/test_tools.py 2>&1 | tee build/logs/ci-safeguard-tests.log
xcodebuild -version | tee build/logs/xcode-version.log
swift --version | tee build/logs/swift-version.log
# Validate the checked-in project first. Do not regenerate over Codemagic signing settings.
python3 Tools/validate_delivery.py | tee build/logs/project-validation.log
xcodebuild -list -project ListaClara.xcodeproj | tee build/logs/project-list.log
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
info={'version':os.environ['IOS_VERSION'], 'build_number':os.environ['IOS_BUILD_NUMBER'],
      'bundle_id':os.environ.get('IOS_BUNDLE_ID','mx.listaclara.ios'),
      'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
      'build_id':os.environ.get('CM_BUILD_ID'), 'distribution':'none'}
Path('build/evidence/build-metadata.json').write_text(json.dumps(info,indent=2)+'\n')
PY
