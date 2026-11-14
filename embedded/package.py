#!/usr/bin/env python3
"""Package a native SideInstaller build into an adapted LiveContainer host."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
from pathlib import Path

HOST_ID = "com.aault.livecontainer.sideinstaller"
MIN_DUO_SDK = (27, 1, 0)


def linked_ios_sdk(data):
    """Read the real Mach-O SDK load command; Info.plist labels cannot opt in."""
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise ValueError('Expected a native 64-bit Mach-O for SDK verification.')
    count, size = struct.unpack_from('<II', data, 16)
    end = 32 + size
    if count > 4096 or end > len(data):
        raise ValueError('Invalid Mach-O load command bounds.')
    offset = 32
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError('Truncated Mach-O load command.')
        command, length = struct.unpack_from('<II', data, offset)
        if length < 8 or offset + length > end:
            raise ValueError('Invalid Mach-O load command length.')
        if command == 0x32 and length >= 24:  # LC_BUILD_VERSION
            platform, _, sdk = struct.unpack_from('<III', data, offset + 8)
            if platform != 2:
                raise ValueError('The packaged component was not built for an iOS device.')
            return (sdk >> 16, (sdk >> 8) & 255, sdk & 255)
        if command == 0x25 and length >= 16:  # LC_VERSION_MIN_IPHONEOS
            sdk = struct.unpack_from('<I', data, offset + 12)[0]
            return (sdk >> 16, (sdk >> 8) & 255, sdk & 255)
        offset += length
    raise ValueError('The packaged binary has no verifiable iOS SDK load command.')


def verify_duo_linked_sdks(app):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    declared = re.fullmatch(r'iphoneos(\d+)\.(\d+)(?:\.(\d+))?', info.get('DTSDKName', ''))
    if not declared or tuple(int(v or 0) for v in declared.groups()) < MIN_DUO_SDK:
        raise ValueError('Full Duo display requires the iOS 27.1+ SDK; the host reports an older or unknown SDK.')
    binaries = {
        'host': app / info['CFBundleExecutable'],
        'desktop': app / 'Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI',
        'liveProcess': app / 'PlugIns/LiveProcess.appex/LiveProcess',
        'installer': app / 'Frameworks/SideInstallerApp.framework/SideInstaller',
    }
    versions = {}
    for name, path in binaries.items():
        sdk = linked_ios_sdk(path.read_bytes())
        if sdk < MIN_DUO_SDK:
            raise ValueError(f'{name} is linked against iOS {sdk[0]}.{sdk[1]}; full Duo display requires iOS 27.1+ SDK binaries.')
        versions[name] = '.'.join(map(str, sdk))
    return {'duoLinkedSDKVerified': True, 'linkedIOSSDKs': versions}


def verify_native_display_configuration(info):
    if not {1, 2}.issubset(set(info.get("UIDeviceFamily", []))):
        raise ValueError("The host must support both iPhone and iPad display families.")
    if not isinstance(info.get("UILaunchScreen"), dict) or any(
            key in info for key in ("UILaunchStoryboardName", "UILaunchImageFile", "UILaunchImages")):
        raise ValueError("The host still uses legacy or missing launch resources instead of an adaptive launch screen.")
    if info.get("UIRequiresFullScreen") is True:
        raise ValueError("The host must allow native scene resizing.")
    return {"nativeDisplayConfigurationVerified": True}


def verify_desktop_components(app):
    host = app / "Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI"
    guest = app / "Frameworks/SideInstallerApp.framework/SideInstaller"
    installer_revision = os.environ.get("SI_INSTALLER_REVISION")
    installer_version = os.environ.get("SI_INSTALLER_VERSION")
    if installer_revision:
        info = plistlib.loads((guest.parent / "Info.plist").read_bytes())
        if info.get("SIEmbeddedInstallerRevision") != installer_revision or info.get("CFBundleShortVersionString") != installer_version:
            raise ValueError("The packaged installer does not match the pinned official version and revision.")
    host_data = host.read_bytes()
    guest_data = guest.read_bytes()
    # These current-shell capabilities live in the actual native UI framework,
    # rather than the editable version plist or copied source notices.
    if not all(value in host_data for value in (b"Search Open Tabs", b"Storage & Recovery")):
        raise ValueError("The packaged UI framework lacks the modern SideOS desktop. Refusing to label a legacy renderer as the current release.")
    if b"Refresh stopped to preserve the installed SideOS desktop." not in guest_data:
        raise ValueError("The packaged installer lacks the SideOS self-refresh source guard.")
    if b"IPA contains an unsafe path, link, size or duplicate entry" not in guest_data:
        raise ValueError("The packaged installer lacks the bounded IPA extraction policy.")
    display_report = verify_native_display_configuration(plistlib.loads((app / "Info.plist").read_bytes()))
    bootstrap = app / "Frameworks/LiveContainerShared.framework/LiveContainerShared"
    picker_hooks = app / "Frameworks/TweakLoader.dylib"
    if not bootstrap.is_file() or not picker_hooks.is_file():
        raise ValueError("The packaged installer lacks its LiveContainer Files runtime.")
    bootstrap_data, picker_data = bootstrap.read_bytes(), picker_hooks.read_bytes()
    if not all(value in bootstrap_data for value in (
            b"../../Frameworks/TweakLoader.dylib", b"SideInstaller Files runtime:")):
        raise ValueError("The installer Files runtime still has the old hosted-process loader.")
    if not all(value in picker_data for value in (b"DOCConfiguration", b"hook_setHostIdentifier:")):
        raise ValueError("The packaged LiveContainer picker lacks its file-access identity hook.")
    if b"TahoeInstallerPickerServer" not in host_data or b"Files access runtime: SideOS host picker requested" not in guest_data:
        raise ValueError("The packaged installer lacks the SideOS host-owned IPA picker.")
    if b"LCGuestExtension" not in bootstrap_data:
        raise ValueError("The packaged runtime lacks the pinned nightly's guest helper support.")
    sdk_report = verify_duo_linked_sdks(app)
    return {**display_report, **sdk_report, "modernDesktopVerified": True, "selfRefreshSourceGuardVerified": True,
            "desktopRuntimeSHA256": hashlib.sha256(host_data).hexdigest(),
            "installerRuntimeSHA256": hashlib.sha256(guest_data).hexdigest(),
            "installerFilesRuntimePackaged": True,
            "installerHostPickerPackaged": True,
            "nightlyGuestHelpersPackaged": True,
            "installerFilesRuntimeSHA256": hashlib.sha256(bootstrap_data).hexdigest(),
            "pickerHooksSHA256": hashlib.sha256(picker_data).hexdigest()}


def entitlement_template(path, bundle_id):
    # This is upstream's ad-hoc placeholder, not a signing account. Resigning
    # must replace it with the user's actual development team and profile.
    text = path.read_text()
    for key, value in {
        "$(DEVELOPMENT_TEAM)": "AAAAA11111", "$(AppIdentifierPrefix)": "AAAAA11111.",
        "$(PRODUCT_BUNDLE_IDENTIFIER)": bundle_id,
        "$(APP_GROUP_SIDESTORE)": "group." + HOST_ID,
        "$(APP_GROUP_ALTSTORE)": "group." + HOST_ID + ".shared",
    }.items():
        text = text.replace(key, value)
    data = plistlib.loads(text.encode())
    data["application-identifier"] = "AAAAA11111." + bundle_id
    data["com.apple.developer.team-identifier"] = "AAAAA11111"
    assert "$(" not in json.dumps(data), "Unresolved signing template macro"
    assert "com.kdt.livecontainer.shared" not in json.dumps(data)
    return data


def update_plist(path, change):
    with path.open("rb") as stream:
        data = plistlib.load(stream)
    change(data)
    with path.open("wb") as stream:
        plistlib.dump(data, stream, sort_keys=False)


def package(host, guest, output, dylibify, upstream, jit_products, jit_source):
    output.mkdir(parents=True, exist_ok=True)
    payload = output / "Payload"
    if payload.exists():
        raise ValueError("Refusing to overwrite a previous Payload; use a fresh output directory.")
    payload.mkdir()
    app = payload / "LiveContainer.app"
    shutil.copytree(host, app)
    update_plist(app / "Info.plist", lambda data: data.update(
        CFBundleDisplayName="SideOS", CFBundleName="SideOS", CFBundleShortVersionString="3.1.0",
        NSLocalNetworkUsageDescription="Connect SideOS devices on your local network for an encrypted extended display.",
        NSBonjourServices=sorted(set(data.get("NSBonjourServices", [])) | {"_sideos-screen._tcp"}),
        CFBundleVersion=os.environ.get("SI_BUILD_NUMBER", data["CFBundleVersion"]),
        SISideInstallerRevision=os.environ.get("SI_INSTALLER_REVISION", "unknown"),
        SISideInstallerVersion=os.environ.get("SI_INSTALLER_VERSION", "unknown"),
        SILiveContainerRevision=os.environ.get("SI_LIVECONTAINER_REVISION", "unknown"),
        SILiveContainerRelease=os.environ.get("SI_LIVECONTAINER_RELEASE", "unknown")))
    shutil.copytree(jit_products / "SIJITHelper.appex", app / "PlugIns/SIJITHelper.appex")
    shutil.copytree(jit_products / "StikJIT.framework", app / "Frameworks/StikJIT.framework")
    host_info = plistlib.loads((app / "Info.plist").read_bytes())
    update_plist(app / "PlugIns/SIJITHelper.appex/Info.plist", lambda data: data.update({
        key: host_info[key] for key in ("CFBundleVersion", "CFBundleShortVersionString")}))
    helper_binary = app / "PlugIns/SIJITHelper.appex/SIJITHelper"
    if "@rpath/StikJIT.framework/StikJIT" not in subprocess.check_output(["otool", "-L", str(helper_binary)], text=True):
        raise ValueError("The debugger helper is not linked to the bundled StikJIT framework.")
    if "@executable_path/../../Frameworks" not in subprocess.check_output(["otool", "-l", str(helper_binary)], text=True):
        raise ValueError("The debugger helper cannot resolve the framework in the host's Frameworks directory.")
    framework = app / "Frameworks/SideInstallerApp.framework"
    shutil.copytree(guest, framework)
    binary = framework / "SideInstaller"
    converted = framework / "SideInstaller.dylib"
    subprocess.run([str(dylibify), str(binary), str(converted)], check=True)
    converted.replace(binary)
    # Same conversion used by upstream's embedded SideStore flavour.
    # A normal sideloader must sign the finished host/frameworks/extensions.
    subprocess.run(["ldid", "-S", str(binary)], check=True)
    if struct.unpack_from("<I", binary.read_bytes(), 12)[0] != 6:
        raise ValueError("Embedded SideInstaller was not converted to MH_DYLIB.")
    shutil.copyfile(upstream / ".github/sidelc/LCAppInfo.plist", framework / "LCAppInfo.plist")

    support = app / "Frameworks/SideStoreSupport.framework"
    metadata = support / "Metadata.appintents"
    if not metadata.is_dir():
        raise ValueError("Host refresh bridge's App Intents metadata was not generated.")
    if (app / "Metadata.appintents").exists():
        shutil.rmtree(app / "Metadata.appintents")
    shutil.copytree(metadata, app / "Metadata.appintents")

    # App extensions must be immediate children of the actual host, not nested
    # under a guest framework. Retain the pairing Live Activity extension.
    plugins = framework / "PlugIns"
    if plugins.exists():
        (app / "PlugIns").mkdir(exist_ok=True)
        for extension in plugins.iterdir():
            if extension.suffix != ".appex":
                raise ValueError(f"Unexpected embedded plugin: {extension.name}")
            destination = app / "PlugIns" / extension.name
            shutil.move(str(extension), destination)
            update_plist(destination / "Info.plist", lambda data: data.update(
                CFBundleIdentifier=HOST_ID + ".PairingActivity",
                CFBundleShortVersionString=host_info["CFBundleShortVersionString"],
                CFBundleVersion=host_info["CFBundleVersion"]))
        plugins.rmdir()

    def merge_guest_permissions(data):
        data["NSCalendarsFullAccessUsageDescription"] = "SideOS shows your upcoming events in the optional Agenda view. Events stay on this iPad and are not included in diagnostics."
        guest_info = plistlib.loads((guest / "Info.plist").read_bytes())
        for key in ("NSLocalNetworkUsageDescription", "NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription", "NSSupportsLiveActivities"):
            if key in guest_info:
                data[key] = guest_info[key]
        for key in ("LSApplicationQueriesSchemes", "NSBonjourServices", "UIBackgroundModes"):
            data[key] = list(dict.fromkeys(data.get(key, []) + guest_info.get(key, [])))
        data["SIEmbeddedGuestVersion"] = guest_info["CFBundleShortVersionString"]
        data["SIEmbeddedSourceRevision"] = os.environ.get("SI_SOURCE_REVISION", "local-evaluation")
        data["SIEmbeddedSourceRepository"] = os.environ.get("SI_SOURCE_REPOSITORY", "stride-praline-2f-ai/SideOS")
    update_plist(app / "Info.plist", merge_guest_permissions)

    for signature in list(app.rglob("_CodeSignature")):
        shutil.rmtree(signature)
    for provision in app.rglob("embedded.mobileprovision"):
        provision.unlink()

    report = verify_release(app)
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    # Source notices travel with the experimental build.
    notices = app / "EmbeddedSourceNotices"
    notices.mkdir()
    installer_ui = Path(__file__).resolve().parent / "installer"
    if installer_ui.exists():
        shutil.copytree(installer_ui, notices / "SideInstallerHome", ignore=shutil.ignore_patterns("__pycache__"))
    if (upstream / ".tahoe-adapted").exists():
        desktop = Path(__file__).resolve().parent / "tahoe"
        shutil.copytree(desktop, notices / "TahoeDesktop", ignore=shutil.ignore_patterns("__pycache__"))
        (notices / "Tahoe-LiveContainer-adaptation.patch").write_bytes(
            subprocess.check_output(["git", "-C", str(upstream), "diff", "--binary", "HEAD"]))
        # Include generated untracked source units as well as the tracked diff.
        generated = notices / "LiveContainer-generated-source"
        for name in subprocess.check_output(
                ["git", "-C", str(upstream), "ls-files", "--others", "--exclude-standard"], text=True).splitlines():
            source = upstream / name
            if source.suffix not in (".swift", ".m", ".h", ".inc"):
                continue
            target = generated / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        (notices / "Tahoe-SOURCE.txt").write_text(
            "Integration: https://github.com/" + os.environ.get("SI_SOURCE_REPOSITORY", "stride-praline-2f-ai/SideOS") + "/tree/" + os.environ.get("SI_SOURCE_REVISION", "main") + "\n"
            "Runtime: https://github.com/LiveContainer/LiveContainer/tree/" + os.environ.get("SI_LIVECONTAINER_REVISION", "unknown") + "\n"
            "Build: .github/workflows/private-build.yml in the integration repository.\n"
            "Tracked runtime adaptation and generated source units are included alongside this notice.\n")
    shutil.copyfile(upstream / "LICENSE", notices / "LiveContainer-LICENSE")
    shutil.copyfile(Path(__file__).resolve().parent.parent / "LICENSE.md", notices / "SideInstaller-LICENSE.md")
    refresh_source = Path(__file__).resolve().parent.parent / "ios-app/SideOSRefreshSourcePolicy.swift"
    shutil.copyfile(refresh_source, notices / "SideOS-RefreshSourcePolicy.swift")
    shutil.copyfile(jit_source / "LICENSE", notices / "StikJIT-MPL-2.0-LICENSE")
    shutil.copyfile(jit_source / "README.md", notices / "StikJIT-README.md")
    for source in ("JITSession.swift", "StikJIT.swift", "IdeviceFFI.swift"):
        shutil.copyfile(jit_source / "Sources" / source, notices / ("StikJIT-" + source))
    shutil.copyfile(jit_source / "SI-ScriptRunner-lifetime.patch", notices / "StikJIT-MODIFICATIONS.txt")
    (notices / "StikJIT-SOURCE.txt").write_text(
        "StikJIT sources: https://github.com/StikDebug/StikJIT/tree/32287268fa5824f9edce4cb359f5833ce0cf7b00\n"
        "Framework modifications include ScriptRunner lifetime, prepared-device API and stage diagnostics.\n"
        "All three modified MPL Swift source files are included alongside this notice. Bundled idevice FFI and scripts retain upstream licenses.\n"
        "Integration source: https://github.com/aaULTra/SideInstaller/tree/feature/livecontainer-sideinstaller/embedded/jit\n")
    # Preserve LC's signing requests in ad-hoc signatures. A build with signing
    # disabled alone would lose app/keychain groups that IPA resigners read.
    templates = [(app, upstream / "entitlements.xml")]
    templates.append((app / "PlugIns/SIJITHelper.appex", jit_source / "SIJITHelper.entitlements"))
    for extension in (app / "PlugIns").glob("*.appex"):
        source = upstream / extension.stem / (extension.stem + ".entitlements")
        if source.exists():
            templates.append((extension, source))
    for bundle, source in templates:
        data = plistlib.loads((bundle / "Info.plist").read_bytes())
        template = entitlement_template(source, data["CFBundleIdentifier"])
        location = notices / (bundle.stem + "-entitlements.plist")
        location.write_bytes(plistlib.dumps(template))
        executable = bundle / data["CFBundleExecutable"]
        subprocess.run(["ldid", "-S" + str(location), str(executable)], check=True)
        recovered = plistlib.loads(subprocess.check_output(["ldid", "-e", str(executable)]))
        assert recovered == template, "Signing entitlement template was not preserved"
    report["scopedSigningEntitlementsPreserved"] = True
    report["maliciousGuestIsolationVerified"] = False
    security = Path(__file__).resolve().parent / 'installer/security'
    actual_lock = Path(__file__).resolve().parent.parent / 'rust-core/Cargo.lock'
    expected_lock = security / 'Cargo.lock'
    if actual_lock.read_bytes() != expected_lock.read_bytes():
        raise ValueError('The installer dependency lock differs from the reviewed security lock.')
    report['installerDependencyLockSHA256'] = hashlib.sha256(actual_lock.read_bytes()).hexdigest()
    report['installerDependencyPolicyVerified'] = True
    report['boundedIPAExtractionVerified'] = True
    shutil.copytree(security, notices / 'InstallerSecurity', ignore=shutil.ignore_patterns('target', '__pycache__'))
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    ipa_name = "SideOS3-" + os.environ.get("SI_BUILD_NUMBER", "local") + "-" + os.environ.get("SI_SOURCE_REVISION", "development")[:8] + "-unsigned.ipa"
    subprocess.run(["ditto", "-c", "-k", "--keepParent", "Payload", ipa_name],
                   cwd=output, check=True)
    repository = os.environ.get("SI_SOURCE_REPOSITORY", "stride-praline-2f-ai/SideOS")
    release = {"sideInstallerVersion": os.environ.get("SI_INSTALLER_VERSION", "unknown"),
               "sideInstallerRevision": os.environ.get("SI_INSTALLER_REVISION", "unknown"),
               "version": "3.1.0", "build": os.environ.get("SI_BUILD_NUMBER", "local"),
               "sourceRevision": os.environ.get("SI_SOURCE_REVISION", "development"),
               "liveContainerRevision": os.environ.get("SI_LIVECONTAINER_REVISION", "unknown"),
               "liveContainerRelease": os.environ.get("SI_LIVECONTAINER_RELEASE", "unknown"),
               "repository": repository, "ipa": ipa_name, "unsigned": True,
               "deviceValidation": "required", "workflow": "private-build.yml"}
    (output / "release.json").write_text(json.dumps(release, indent=2) + "\n")


def verify(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == HOST_ID, "Experimental host must not overwrite stock LiveContainer"
    guest = app / "Frameworks/SideInstallerApp.framework"
    assert guest.is_dir() and (guest / "SideInstaller").is_file()
    assert not (app / "Frameworks/SideStoreApp.framework").exists(), "Do not ship an unused SideStore app"
    assert not (guest / "PlugIns").exists(), "Nested app extensions are not installable"
    assert (app / "PlugIns/LiveProcess.appex").is_dir()
    helper = app / "PlugIns/SIJITHelper.appex"
    assert helper.is_dir(), "Built-in JIT helper must be embedded in the actual host"
    helper_info = plistlib.loads((helper / "Info.plist").read_bytes())
    assert helper_info["NSExtension"]["NSExtensionPrincipalClass"] == "SIJITHelperHandler"
    assert not (helper / "Frameworks").exists(), "JIT framework must live at host Frameworks"
    jit = app / "Frameworks/StikJIT.framework"
    verify_jit_framework(jit)
    assert (jit / "StikJIT").is_file()
    assert (jit / "universal.js").is_file(), "Universal script must be bundled"
    assert struct.unpack_from("<I", (guest / "SideInstaller").read_bytes(), 12)[0] == 6
    for extension in (app / "PlugIns").glob("*.appex"):
        extension_info = plistlib.loads((extension / "Info.plist").read_bytes())
        assert extension_info["CFBundleIdentifier"].startswith(HOST_ID + "."), extension.name
    actions = json.loads((app / "Metadata.appintents/extract.actionsdata").read_bytes())
    refresh = actions["actions"]["RefreshAllAppsIntent"]
    assert refresh["isDiscoverable"]
    assert refresh["openAppWhenRun"] is False
    assert refresh["fullyQualifiedTypeName"].startswith("SideStoreSupport.")
    assert any(shortcut["actionIdentifier"] == "RefreshAllAppsIntent" for shortcut in actions["autoShortcuts"])
    protocols = refresh["systemProtocols"]
    assert "com.apple.link.systemProtocol.ForegroundContinuable" in protocols
    assert "com.apple.link.systemProtocol.ProgressReporting" in protocols
    return {"host": HOST_ID, "guest": "SideInstaller", "containsSideStoreApp": False,
            "nativeRefreshIntent": True, "builtInGuestJIT": True,
            "jitFrameworkMetadataVerified": True,
            "extensions": sorted(x.name for x in (app / "PlugIns").glob("*.appex")),
            "runtimeDeviceTests": "required; compile/package checks do not prove device execution"}


def verify_release(app):
    """A shipped SideOS IPA must pass both generic and desktop-specific gates."""
    return {**verify(app), **verify_desktop_components(app)}


def verify_jit_framework(framework):
    path = framework / "Info.plist"
    if not path.is_file():
        raise ValueError("StikJIT.framework/Info.plist is missing; refusing to package an uninstallable framework.")
    try:
        info = plistlib.loads(path.read_bytes())
    except (plistlib.InvalidFileException, ValueError) as error:
        raise ValueError("StikJIT.framework/Info.plist is malformed") from error
    if not isinstance(info, dict):
        raise ValueError("StikJIT.framework/Info.plist must contain a dictionary")
    for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleName",
                "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion"):
        value = info.get(key)
        if not isinstance(value, str) or not value or "$(" in value:
            raise ValueError(f"StikJIT.framework/Info.plist has invalid or unresolved {key}")
    if info.get("CFBundlePackageType") != "FMWK" or info["CFBundleExecutable"] != "StikJIT":
        raise ValueError("StikJIT.framework must declare FMWK and its actual StikJIT executable")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("StikJIT.framework does not declare the iPhoneOS platform")
    if not (framework / info["CFBundleExecutable"]).is_file():
        raise ValueError("StikJIT.framework's declared executable is missing")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("host", "guest", "output", "dylibify", "upstream", "jit-products", "jit-source"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    package(*(getattr(args, key).resolve() for key in ("host", "guest", "output", "dylibify", "upstream", "jit_products", "jit_source")))
