#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run again after adding Swift files."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
objects = {}


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(object_key, isa, **fields):
    key = identifier(object_key)
    objects[key] = {"isa": isa, **fields}
    return key


def settings(name, values):
    configurations = []
    for mode in ["Debug", "Release"]:
        configuration = dict(values)
        configuration["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if mode == "Debug" else "-O"
        configuration["DEBUG_INFORMATION_FORMAT"] = "dwarf" if mode == "Debug" else "dwarf-with-dsym"
        if mode == "Debug":
            configuration["ENABLE_TESTABILITY"] = "YES"
            configuration["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        configurations.append(add(name + mode, "XCBuildConfiguration", name=mode, buildSettings=configuration))
    return add(name + "Configurations", "XCConfigurationList", buildConfigurations=configurations,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


def source_group(folder):
    references, builds = [], []
    for source in sorted((ROOT / folder).glob("*.swift")):
        reference = add(str(source.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="sourcecode.swift", path=source.name, sourceTree="<group>")
        references.append(reference)
        builds.append(add(str(source.relative_to(ROOT)) + "Build", "PBXBuildFile", fileRef=reference))
    return references, builds


app_files, app_builds = source_group("Reader")
test_files, test_builds = source_group("ReaderTests")
assets = add("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Assets.xcassets", sourceTree="<group>")
app_files.append(assets)
plist = add("plist", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
app_files.append(plist)
app_group = add("AppGroup", "PBXGroup", children=app_files, path="Reader", sourceTree="<group>")
tests_group = add("TestsGroup", "PBXGroup", children=test_files, path="ReaderTests", sourceTree="<group>")
app_product = add("AppProduct", "PBXFileReference", explicitFileType="wrapper.application", path="Reader.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("TestsProduct", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="ReaderTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products = add("Products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main = add("Main", "PBXGroup", children=[app_group, tests_group, products], sourceTree="<group>")
app_phases = [add("AppSources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=app_builds, runOnlyForDeploymentPostprocessing="0"),
              add("AppFrameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0"),
              add("AppResources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=[add("AssetsBuild", "PBXBuildFile", fileRef=assets)], runOnlyForDeploymentPostprocessing="0")]
test_phases = [add("TestSources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=test_builds, runOnlyForDeploymentPostprocessing="0"),
               add("TestFrameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")]
base = {"IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0", "SDKROOT": "iphoneos", "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES", "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGN_STYLE": "Automatic",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO"}
app_config = settings("App", {**base, "PRODUCT_NAME": "Reader", "PRODUCT_BUNDLE_IDENTIFIER": "org.reader-rust.reader",
                              "INFOPLIST_FILE": "Reader/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                              "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1"})
test_config = settings("Tests", {**base, "PRODUCT_NAME": "ReaderTests", "PRODUCT_BUNDLE_IDENTIFIER": "org.reader-rust.reader.tests",
                                 "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Reader.app/Reader", "BUNDLE_LOADER": "$(TEST_HOST)"})
proxy = add("TestProxy", "PBXContainerItemProxy", containerPortal=identifier("Project"), proxyType="1", remoteGlobalIDString=identifier("App"), remoteInfo="Reader")
dependency = add("TestDependency", "PBXTargetDependency", target=identifier("App"), targetProxy=proxy)
app = add("App", "PBXNativeTarget", buildConfigurationList=app_config, buildPhases=app_phases, buildRules=[], dependencies=[],
          name="Reader", productName="Reader", productReference=app_product, productType="com.apple.product-type.application")
tests = add("Tests", "PBXNativeTarget", buildConfigurationList=test_config, buildPhases=test_phases, buildRules=[], dependencies=[dependency],
            name="ReaderTests", productName="ReaderTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
project = add("Project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES"},
              buildConfigurationList=settings("Project", base), compatibilityVersion="Xcode 14.0", developmentRegion="en",
              hasScannedForEncodings="0", knownRegions=["en", "zh-Hans", "Base"], mainGroup=main, productRefGroup=products,
              projectDirPath="", projectRoot="", targets=[app, tests])


def serialize(value, depth=0):
    if isinstance(value, dict):
        body = "\n".join("\t" * (depth + 1) + json.dumps(k) + " = " + serialize(v, depth + 1) + ";" for k, v in value.items())
        return "{\n" + body + "\n" + "\t" * depth + "}"
    if isinstance(value, list):
        return "(" + ", ".join(serialize(item, depth) for item in value) + ("," if value else "") + ")"
    return json.dumps(value)


project_root = ROOT / "Reader.xcodeproj"
project_root.mkdir(exist_ok=True)
(project_root / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}) + "\n")
scheme_dir = project_root / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def reference(target, name, extension):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:Reader.xcodeproj"/>'


(scheme_dir / "Reader.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app, "Reader", "app")}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables><TestableReference skipped="NO" parallelizable="NO">{reference(tests, "ReaderTests", "xctest")}</TestableReference></Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app, "Reader", "app")}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app, "Reader", "app")}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated ios/Reader.xcodeproj")
