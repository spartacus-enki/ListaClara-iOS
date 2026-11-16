#!/usr/bin/env python3
"""Require a real arm64 iPhone app, verified signature and matching Ad Hoc profile.
This is a CI gate, not proof of physical device installation or app functionality.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile
import zipfile

def inspect_payload(ipa, folder):
    with zipfile.ZipFile(ipa) as archive:
        assert len(archive.infolist()) < 50000, 'Unexpected IPA member count'
        assert sum(m.file_size for m in archive.infolist()) < 2 * 1024**3, 'Unexpected IPA size'
        for member in archive.infolist():
            dest = (folder/member.filename).resolve()
            assert dest.is_relative_to(folder.resolve()), 'Unsafe IPA path'
            assert not ((member.external_attr >> 16) & 0o170000) == 0o120000, 'Unexpected IPA symlink'
        archive.extractall(folder)
    apps = list((folder/'Payload').glob('*.app'))
    assert len(apps) == 1, 'Expected exactly one iPhone app in Payload'
    app = apps[0]
    info = plistlib.loads((app/'Info.plist').read_bytes())
    assert info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Not an iPhoneOS device build'
    executable = app/info['CFBundleExecutable']
    assert executable.is_file(), 'Missing executable'
    assert (app/'_CodeSignature/CodeResources').is_file(), 'Missing code signature'
    assert (app/'embedded.mobileprovision').is_file(), 'Missing provisioning profile'
    # ZIP extraction may lose Unix execute bits; restore only this validated executable.
    executable.chmod(executable.stat().st_mode | 0o100)
    return app, info, executable

def verify(ipa, bundle_id, udid):
    assert platform.system() == 'Darwin', 'Signature verification requires macOS/security/codesign/lipo'
    assert udid, 'IOS_TEST_DEVICE_UDID is required; never print its value'
    with tempfile.TemporaryDirectory(prefix='listaclara-ipa-') as temp:
        app, info, executable = inspect_payload(ipa, Path(temp))
        assert info['CFBundleIdentifier'] == bundle_id, 'Bundle ID mismatch'
        architecture = subprocess.check_output(['lipo','-archs',str(executable)], text=True).split()
        assert 'arm64' in architecture, 'No arm64 device executable'
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)], check=True, capture_output=True)
        profile = plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(app/'embedded.mobileprovision')]))
        certificate_prefix = str(Path(temp)/'signing-certificate-')
        subprocess.run(['codesign','--display','--extract-certificates',certificate_prefix,str(app)],check=True,capture_output=True)
        certificate = Path(certificate_prefix+'0')
        assert certificate.is_file(), 'No signing certificate; ad hoc local signatures are not accepted'
        assert certificate.read_bytes() in profile.get('DeveloperCertificates', []), 'Signing certificate is not authorized by embedded profile'
        signature = plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)], stderr=subprocess.DEVNULL))
        expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
        assert expiry > datetime.datetime.now(datetime.timezone.utc), 'Expired profile'
        assert not profile.get('ProvisionsAllDevices', False), 'Expected Ad Hoc, not enterprise'
        assert udid in profile.get('ProvisionedDevices', []), 'Target iPhone is not registered in this profile'
        entitlements = profile['Entitlements']
        assert not entitlements.get('get-task-allow', False), 'Expected distribution profile, not development'
        assert signature.get('get-task-allow', False) is False, 'Debug entitlement in distribution app'
        app_identifier = entitlements['application-identifier']
        assert app_identifier.endswith('.'+bundle_id) and '*' not in app_identifier, 'Expected explicit app profile'
        assert signature.get('application-identifier') == app_identifier, 'Signed app/profile identity mismatch'
        team = profile['TeamIdentifier'][0]
        assert signature.get('com.apple.developer.team-identifier') == team, 'Signing team mismatch'
        return {'status':'signature-and-profile-verified', 'artifact':ipa.name,
                'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),
                'bundle_id':bundle_id,'version':info['CFBundleShortVersionString'],'build_number':info['CFBundleVersion'],
                'architectures':architecture,'distribution':'ad_hoc','profile_expires_at':expiry.isoformat(),
                'target_device_registered':True,'physical_installation_tested':False,
                'codemagic_build_id':os.environ.get('CM_BUILD_ID'),'commit':os.environ.get('CM_COMMIT')}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--directory',type=Path,required=True)
    parser.add_argument('--bundle-id',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    ipas=list(args.directory.glob('*.ipa'))
    assert len(ipas)==1, 'Expected exactly one exported .ipa; no synthetic/fallback artifact is accepted'
    result=verify(ipas[0],args.bundle_id,os.environ.get('IOS_TEST_DEVICE_UDID'))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Verified signed Ad Hoc IPA and target-device profile membership. Physical installation still requires testing.')
if __name__=='__main__': main()
