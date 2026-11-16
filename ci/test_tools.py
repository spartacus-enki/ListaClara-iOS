#!/usr/bin/env python3
"""Linux validation of delivery/CI safeguards, not an Apple compiler substitute."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
ROOT=Path(__file__).resolve().parents[1]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
ipa=module('ipa_gate',ROOT/'ci/verify_ipa.py')
installer=module('installer',ROOT/'Tools/conserve_project.py')

class ConfigurationTests(unittest.TestCase):
    def test_yaml_compatible_json_workflows_and_no_publication(self):
        config=json.loads((ROOT/'codemagic.yaml').read_text())
        self.assertEqual(set(config['workflows']),{'ios-validate','ios-adhoc'})
        for flow in config['workflows'].values():
            self.assertNotIn('publishing',flow); self.assertNotIn('triggering',flow)
            self.assertEqual(flow['instance_type'],'mac_mini_m2')
            for step in flow['scripts']:
                command=step['script'].split()
                self.assertEqual(command[0],'bash'); self.assertTrue((ROOT/command[1]).is_file())
        self.assertNotIn('ios_signing',config['workflows']['ios-validate']['environment'])
        signed=config['workflows']['ios-adhoc']['environment']
        self.assertEqual(signed['ios_signing'],{'distribution_type':'ad_hoc','bundle_identifier':'mx.listaclara.ios'})
        self.assertIn('lista_clara_ios_adhoc',signed['groups'])
    def test_refuse_existing_or_android_destination(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(AssertionError): installer.safe_destination(Path(temp))
            allowed=Path(temp)/'independent-ios'
            self.assertEqual(installer.safe_destination(allowed),allowed.resolve())
        for path in [installer.ANDROID, installer.ANDROID/'new-ios', installer.ANDROID.parent]:
            with self.assertRaises(AssertionError): installer.safe_destination(path)
    def test_safe_destination_resolves_symlinked_parent(self):
        # macOS temporary paths may be reached through a symlink. The installer
        # intentionally returns a canonical path; this must not fail preflight.
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp).resolve()
            real=base/'real'; real.mkdir()
            alias=base/'alias'; alias.symlink_to(real,target_is_directory=True)
            allowed=alias/'independent-ios'
            self.assertEqual(installer.safe_destination(allowed),real/'independent-ios')
            self.assertFalse(allowed.exists())
            # Resolving an alias must still reject an already-existing directory.
            with self.assertRaises(AssertionError): installer.safe_destination(alias)
    def test_source_archive_cannot_masquerade_as_app(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp); fixture=folder/'source.zip'; output=folder/'out'; output.mkdir()
            with zipfile.ZipFile(fixture,'w') as archive: archive.writestr('Sources/Test.swift','// source')
            with self.assertRaises(AssertionError): ipa.inspect_payload(fixture,output)
    def test_reject_simulator_payload(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp); fixture=folder/'simulator.zip'; output=folder/'out'; output.mkdir()
            with zipfile.ZipFile(fixture,'w') as archive:
                archive.writestr('Payload/Test.app/Info.plist',plistlib.dumps({'CFBundleSupportedPlatforms':['iPhoneSimulator']}))
            with self.assertRaises(AssertionError): ipa.inspect_payload(fixture,output)
    def test_reject_zip_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp); fixture=folder/'traversal.zip'; output=folder/'out'; output.mkdir()
            with zipfile.ZipFile(fixture,'w') as archive: archive.writestr('../escape','bad')
            with self.assertRaises(AssertionError): ipa.inspect_payload(fixture,output)
            self.assertFalse((folder/'escape').exists())
    def test_project_and_yaml_bundle_ids_match(self):
        config=json.loads((ROOT/'codemagic.yaml').read_text())
        for flow in config['workflows'].values():
            bundle=flow['environment']['vars']['IOS_BUNDLE_ID']
            self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = "'+bundle+'"',(ROOT/'ListaClara.xcodeproj/project.pbxproj').read_text())
        self.assertIn('1.0.0',(ROOT/'Tools/generate_project.py').read_text())
if __name__=='__main__': unittest.main(verbosity=2)
