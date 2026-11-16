#!/usr/bin/env python3
"""Owner-run permanent installation, from a verified local Git bundle.
No privilege escalation, network publication, Android writes or service operations.
"""
import argparse
import datetime
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ORIGINAL_SHA256 = 'fa20b9aca4e68a2ebf680cf35f67f3bd3140490ee55997bde47819df31590493'
ANDROID = Path('/home/dexanox/Servicios/TaskFamily/ListaClara')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def safe_destination(path):
    path = path.expanduser().resolve()
    assert path != ANDROID and not path.is_relative_to(ANDROID) and not ANDROID.is_relative_to(path), 'Destination must be independent of Android'
    assert not os.path.lexists(path), 'Destination already exists; refusing overwrite'
    assert path.parent.is_dir(), 'Create/choose an owner-writable parent first'
    return path

def conserve(bundle, original, destination, bundle_sha256):
    destination = safe_destination(destination)
    assert sha(original) == ORIGINAL_SHA256, 'Original archive integrity mismatch'
    assert sha(bundle) == bundle_sha256, 'Git bundle integrity mismatch'
    backup_root = destination.parent/(destination.name+'-backups')
    assert not backup_root.is_symlink(), 'Refusing symlinked backup root'
    backup_root.mkdir(mode=0o700, exist_ok=True)
    date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-')
    backup = Path(tempfile.mkdtemp(prefix=date, dir=backup_root))
    for source in [bundle, original]:
        copy=backup/source.name; shutil.copy2(source, copy)
        assert sha(copy) == sha(source), 'Backup copy mismatch'
        Path(str(copy)+'.sha256').write_text(sha(copy)+'  '+copy.name+'\n')
    # Git verifies object hashes on import. It will not overwrite a nonempty directory.
    subprocess.run(['git','clone','--branch','main',str(backup/bundle.name),str(destination)],check=True)
    destination.chmod(0o700)
    subprocess.run(['git','-C',str(destination),'remote','remove','origin'],check=True)
    subprocess.run(['git','-C',str(destination),'fsck','--full'],check=True)
    subprocess.run(['python3',str(destination/'Tools/validate_delivery.py')],check=True)
    print('Permanent iOS checkout:', destination)
    print('Independent backups:', backup)
    print('No external remote configured; no source publication performed.')
    return backup

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--bundle',type=Path,required=True)
    parser.add_argument('--bundle-sha256',required=True)
    parser.add_argument('--original-archive',type=Path,default=Path('/tmp/ListaClara-iOS-1.0.0.tar.gz'))
    parser.add_argument('--destination',type=Path,default=Path('/home/dexanox/Servicios/TaskFamily/ListaClara-iOS'))
    args=parser.parse_args()
    conserve(args.bundle.resolve(),args.original_archive.resolve(),args.destination,args.bundle_sha256)
if __name__=='__main__': main()
