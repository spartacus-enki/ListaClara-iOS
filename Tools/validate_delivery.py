#!/usr/bin/env python3
"""Validate project structure, not Swift syntax/typechecking or Xcode compilation."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
source = (root/'ListaClara.xcodeproj/project.pbxproj').read_text()
source = re.sub(r'//[^\n]*', '', source)
tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', source)
position = 0
def parse():
    global position
    token = tokens[position]; position += 1
    if token == '{':
        result = {}
        while tokens[position] != '}':
            key = parse(); assert tokens[position] == '='; position += 1
            result[key] = parse(); assert tokens[position] == ';'; position += 1
        position += 1; return result
    if token == '(':
        result = []
        while tokens[position] != ')':
            result.append(parse())
            if tokens[position] == ',': position += 1
        position += 1; return result
    return json.loads(token) if token.startswith('"') else token
project = parse(); assert position == len(tokens)
objects = project['objects']; assert project['rootObject'] in objects
for key, value in objects.items():
    assert re.fullmatch('[A-F0-9]{24}', key)
    for attribute in ['fileRef','buildConfigurationList','mainGroup','productRefGroup','productReference','target','targetProxy','containerPortal','remoteGlobalIDString']:
        if attribute in value: assert value[attribute] in objects, (key, attribute)
    for attribute in ['children','buildConfigurations','buildPhases','dependencies','targets','files']:
        for reference in value.get(attribute, []): assert reference in objects, (key, attribute)
    if value.get('lastKnownFileType') == 'sourcecode.swift': assert (root/value['path']).is_file()
app = next(v for v in objects.values() if v.get('productType') == 'com.apple.product-type.application')
test = next(v for v in objects.values() if v.get('productType') == 'com.apple.product-type.bundle.unit-test')
for target in [app, test]: assert target['buildPhases']
all_build_files = {v['fileRef'] for v in objects.values() if v['isa']=='PBXBuildFile'}
assert len(all_build_files) == len(list((root/'Sources').rglob('*.swift'))) + len(list((root/'Tests').glob('*.swift')))
for scheme in (root/'ListaClara.xcodeproj').rglob('*.xcscheme'):
    tree = ET.parse(scheme)
    for node in tree.findall('.//BuildableReference'): assert node.attrib['BlueprintIdentifier'] in objects
info = plistlib.loads((root/'Sources/App/Info.plist').read_bytes())
assert 'NSAppTransportSecurity' not in info
assert info['NSFaceIDUsageDescription']
assert not info.get('UIBackgroundModes')
assert (root/'Package.swift').is_file()
print('PASS: OpenStep project parsed; all references, source membership, app/test targets, scheme and Info.plist validated.')
print('NOT VERIFIED: Swift parsing/typechecking, SDK linkage, Xcode build, tests, signing, device behavior.')
# Read source only. No DBs, signing material, caches or generated Android build products.
android = Path('/home/dexanox/Servicios/TaskFamily/ListaClara')
if android.is_dir():
    paths = []
    for directory in ['app/src','domain/src','data/src','data/schemas','docs','scripts','server']:
        for p in (android/directory).rglob('*'):
            if p.is_file() and not any(x in {'.venv','__pycache__','data','static'} for x in p.relative_to(android/directory).parts[:-1]):
                paths.append(p)
    paths += [p for p in android.iterdir() if p.is_file() and p.suffix in {'.kts','.properties','.md'}]
    hashes = {str(p.relative_to(android)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}
    manifest = root/'Docs/android-source-sha256.json'
    if manifest.exists():
        assert json.loads(manifest.read_text()) == hashes, 'Android source changed since delivery snapshot; review owner/concurrent changes.'
        print(f'PASS: {len(hashes)} Android source/reference files match the delivery snapshot.')
    else:
        manifest.write_text(json.dumps(hashes, indent=2)+'\n')
        print(f'Recorded read-only delivery snapshot of {len(hashes)} Android source/reference files; not a pre-session baseline.')
