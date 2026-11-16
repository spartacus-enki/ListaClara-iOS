#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generator; edits iOS output only."""
from pathlib import Path
import hashlib
import plistlib
root = Path(__file__).resolve().parents[1]
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def ref(name): return uid(name)
objects = {}
def add(name, content): objects[uid(name)] = content; return uid(name)
def sequence(items): return '(' + ', '.join(items) + ',)' if items else '()'
app_sources = sorted((root/'Sources').rglob('*.swift'))
tests = sorted((root/'Tests').glob('*.swift'))
file_refs = []
for p in app_sources + tests:
    path = p.relative_to(root).as_posix()
    f = add(path, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "'+path+'"; sourceTree = SOURCE_ROOT;}')
    add('build:'+path, '{isa = PBXBuildFile; fileRef = '+f+';}')
    file_refs.append(f)
app_product = add('appProduct', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = ListaClara.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product = add('testProduct', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ListaClaraTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
products = add('products', '{isa = PBXGroup; name = Products; children = '+sequence([app_product, test_product])+'; sourceTree = "<group>";}')
main = add('main', '{isa = PBXGroup; children = '+sequence(file_refs+[products])+'; sourceTree = "<group>";}')
for name, files in [('app',app_sources),('test',tests)]:
    add(name+'Sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+sequence([ref('build:'+p.relative_to(root).as_posix()) for p in files])+'; runOnlyForDeploymentPostprocessing = 0;}')
    add(name+'Frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
    add(name+'Resources', '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
for target in ['project','app','test']:
    ids=[]
    for config in ['Debug','Release']:
        settings={'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'16.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1','CLANG_ENABLE_MODULES':'YES'}
        settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config=='Debug' else '', 'ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO'})
        if target=='app': settings.update({'PRODUCT_NAME':'ListaClara','PRODUCT_MODULE_NAME':'ListaClaraCore','PRODUCT_BUNDLE_IDENTIFIER':'mx.listaclara.ios','INFOPLIST_FILE':'Sources/App/Info.plist','CODE_SIGN_STYLE':'Automatic','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'2','GENERATE_INFOPLIST_FILE':'NO'})
        if target=='test': settings.update({'PRODUCT_NAME':'ListaClaraTests','PRODUCT_BUNDLE_IDENTIFIER':'mx.listaclara.ios.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/ListaClara.app/ListaClara','BUNDLE_LOADER':'$(TEST_HOST)','CODE_SIGN_STYLE':'Automatic'})
        pairs=' '.join(k+' = "'+v+'";' for k,v in settings.items())
        ids.append(add(target+config, '{isa = XCBuildConfiguration; buildSettings = {'+pairs+'}; name = '+config+';}'))
    add(target+'Configurations','{isa = XCConfigurationList; buildConfigurations = '+sequence(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
proxy=add('proxy','{isa = PBXContainerItemProxy; containerPortal = '+ref('project')+'; proxyType = 1; remoteGlobalIDString = '+ref('appTarget')+'; remoteInfo = ListaClara;}')
dep=add('testDependency','{isa = PBXTargetDependency; target = '+ref('appTarget')+'; targetProxy = '+proxy+';}')
for name in ['app','test']:
    add(name+'Target','{isa = PBXNativeTarget; buildConfigurationList = '+ref(name+'Configurations')+'; buildPhases = '+sequence([ref(name+'Sources'),ref(name+'Frameworks'),ref(name+'Resources')])+'; buildRules = (); dependencies = '+sequence([dep] if name=='test' else [])+'; name = '+('ListaClara' if name=='app' else 'ListaClaraTests')+'; productName = '+('ListaClara' if name=='app' else 'ListaClaraTests')+'; productReference = '+(app_product if name=='app' else test_product)+'; productType = "com.apple.product-type.'+('application' if name=='app' else 'bundle.unit-test')+'";}')
add('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = '+ref('projectConfigurations')+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = es; knownRegions = (es, en, Base); mainGroup = '+main+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+sequence([ref('appTarget'),ref('testTarget')])+';}')
project=root/'ListaClara.xcodeproj'
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = '+v+';' for k,v in sorted(objects.items()))+'\n}; rootObject = '+ref('project')+'; }\n')
(project/'xcshareddata/xcschemes/ListaClara.xcscheme').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
 <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'''+ref('appTarget')+'''" BuildableName="ListaClara.app" BlueprintName="ListaClara" ReferencedContainer="container:ListaClara.xcodeproj"/></BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'''+ref('testTarget')+'''" BuildableName="ListaClaraTests.xctest" BlueprintName="ListaClaraTests" ReferencedContainer="container:ListaClara.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'''+ref('appTarget')+'''" BuildableName="ListaClara.app" BlueprintName="ListaClara" ReferencedContainer="container:ListaClara.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
info={'CFBundleDevelopmentRegion':'es','CFBundleDisplayName':'Lista Clara','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'NSLocalNetworkUsageDescription':'Conectar con tu servidor Lista Clara en la red local.','UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'NSFaceIDUsageDescription':'Desbloquear tus listas y tareas con Face ID.'}
(root/'Sources/App/Info.plist').write_bytes(plistlib.dumps(info))
print(f'Generated app + test targets; {len(app_sources)} Swift source files, {len(tests)} test files')
