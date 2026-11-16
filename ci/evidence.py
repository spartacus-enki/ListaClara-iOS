#!/usr/bin/env python3
"""Write actual runner step outcomes only; never invent a build ID/result."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
folder = root/'build/evidence'
folder.mkdir(parents=True, exist_ok=True)
command, step = sys.argv[1:3]
assert step.replace('-', '').isalnum()
path = folder/(step+'.json')
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
if command == 'start':
    data = {'step': step, 'status': 'running', 'started_at': now,
            'codemagic_build_id': os.environ.get('CM_BUILD_ID'),
            'codemagic_workflow': os.environ.get('CM_WORKFLOW_NAME'),
            'commit': subprocess.check_output(['git','rev-parse','HEAD'], cwd=root, text=True).strip()}
else:
    data = json.loads(path.read_text())
    data.update(ended_at=now, exit_code=int(sys.argv[3]), status='passed' if int(sys.argv[3]) == 0 else 'failed')
path.write_text(json.dumps(data, indent=2)+'\n')
