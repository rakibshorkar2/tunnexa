#!/usr/bin/env python3
"""
Tunnexa IPA / .app Validation Script
=====================================
Usage:
    python3 validate_ipa.py --ipa path/to/Tunnexa.ipa
    python3 validate_ipa.py --app path/to/Tunnexa.app

Checks:
  1. Main app bundle identifier = com.rakib.tunnexa
  2. PacketTunnel extension exists in PlugIns/
  3. Extension bundle identifier = com.rakib.tunnexa.PacketTunnel
  4. Extension CFBundlePackageType = XPC!
  5. Extension NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel
  6. Extension executable present
  7. Extension NSExtensionPrincipalClass is set

Exit codes:
  0 = All checks pass
  1 = One or more checks failed
"""

import argparse
import json
import os
import plistlib
import sys
import zipfile
import tempfile
import shutil

MAIN_BUNDLE_ID = "com.rakib.tunnexa"
EXTENSION_BUNDLE_ID = "com.rakib.tunnexa.PacketTunnel"
EXTENSION_POINT = "com.apple.networkextension.packet-tunnel"


def fail(msg: str):
    print(f"  [FAIL] {msg}")


def ok(msg: str):
    print(f"  [ OK ] {msg}")


def read_plist(path: str) -> dict:
    with open(path, "rb") as f:
        return plistlib.load(f)


def validate_app(app_path: str) -> bool:
    print(f"\n=== Validating: {app_path} ===\n")
    all_passed = True

    # --- Main App Checks ---
    main_plist_path = os.path.join(app_path, "Info.plist")
    if not os.path.isfile(main_plist_path):
        fail("Info.plist not found in main app bundle")
        return False

    main_plist = read_plist(main_plist_path)
    main_bundle_id = main_plist.get("CFBundleIdentifier", "")

    if main_bundle_id == MAIN_BUNDLE_ID:
        ok(f"Main app bundle ID: {main_bundle_id}")
    else:
        fail(f"Main app bundle ID: '{main_bundle_id}' (expected '{MAIN_BUNDLE_ID}')")
        all_passed = False

    package_type = main_plist.get("CFBundlePackageType", "")
    if package_type == "APPL":
        ok(f"Main app CFBundlePackageType: {package_type}")
    else:
        fail(f"Main app CFBundlePackageType: '{package_type}' (expected 'APPL')")
        all_passed = False

    # --- Extension Checks ---
    plugins_dir = os.path.join(app_path, "PlugIns")
    if not os.path.isdir(plugins_dir):
        fail("PlugIns/ directory not found — extension is not embedded!")
        return False

    ok(f"PlugIns/ directory present")

    extension_name = "TunnexaPacketTunnel.appex"
    extension_path = os.path.join(plugins_dir, extension_name)

    if not os.path.isdir(extension_path):
        fail(f"Extension '{extension_name}' not found in PlugIns/")
        all_passed = False
        print("\n  Available items in PlugIns/:")
        for item in os.listdir(plugins_dir):
            print(f"    - {item}")
        return False

    ok(f"Extension '{extension_name}' found")

    ext_plist_path = os.path.join(extension_path, "Info.plist")
    if not os.path.isfile(ext_plist_path):
        fail("Extension Info.plist not found")
        return False

    ext_plist = read_plist(ext_plist_path)

    ext_bundle_id = ext_plist.get("CFBundleIdentifier", "")
    if ext_bundle_id == EXTENSION_BUNDLE_ID:
        ok(f"Extension bundle ID: {ext_bundle_id}")
    else:
        fail(f"Extension bundle ID: '{ext_bundle_id}' (expected '{EXTENSION_BUNDLE_ID}')")
        all_passed = False

    ext_package_type = ext_plist.get("CFBundlePackageType", "")
    if ext_package_type == "XPC!":
        ok(f"Extension CFBundlePackageType: {ext_package_type}")
    else:
        fail(f"Extension CFBundlePackageType: '{ext_package_type}' (expected 'XPC!')")
        all_passed = False

    ns_extension = ext_plist.get("NSExtension", {})
    ext_point = ns_extension.get("NSExtensionPointIdentifier", "")
    if ext_point == EXTENSION_POINT:
        ok(f"Extension NSExtensionPointIdentifier: {ext_point}")
    else:
        fail(f"Extension NSExtensionPointIdentifier: '{ext_point}' (expected '{EXTENSION_POINT}')")
        all_passed = False

    principal_class = ns_extension.get("NSExtensionPrincipalClass", "")
    if principal_class:
        ok(f"Extension NSExtensionPrincipalClass: {principal_class}")
    else:
        fail("Extension NSExtensionPrincipalClass is empty or missing")
        all_passed = False

    # Check executable
    ext_executable_name = ext_plist.get("CFBundleExecutable", "TunnexaPacketTunnel")
    ext_executable_path = os.path.join(extension_path, ext_executable_name)
    if os.path.isfile(ext_executable_path):
        size = os.path.getsize(ext_executable_path)
        ok(f"Extension executable '{ext_executable_name}' present ({size:,} bytes)")
    else:
        fail(f"Extension executable '{ext_executable_name}' NOT found at {ext_executable_path}")
        all_passed = False

    print()
    if all_passed:
        print("=== VALIDATION PASSED — Tunnexa.app is correctly packaged ===")
    else:
        print("=== VALIDATION FAILED — See FAIL entries above ===")

    return all_passed


def extract_ipa(ipa_path: str) -> str:
    tmpdir = tempfile.mkdtemp(prefix="tunnexa_validate_")
    with zipfile.ZipFile(ipa_path, "r") as zf:
        zf.extractall(tmpdir)

    payload_dir = os.path.join(tmpdir, "Payload")
    if not os.path.isdir(payload_dir):
        print("ERROR: IPA does not contain a Payload/ directory")
        sys.exit(1)

    apps = [d for d in os.listdir(payload_dir) if d.endswith(".app")]
    if not apps:
        print("ERROR: No .app bundle found in Payload/")
        sys.exit(1)

    return os.path.join(payload_dir, apps[0]), tmpdir


def main():
    parser = argparse.ArgumentParser(description="Validate Tunnexa IPA or .app bundle packaging")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--ipa", metavar="PATH", help="Path to Tunnexa IPA file")
    group.add_argument("--app", metavar="PATH", help="Path to Tunnexa.app directory")
    args = parser.parse_args()

    tmpdir = None
    try:
        if args.ipa:
            if not os.path.isfile(args.ipa):
                print(f"ERROR: IPA not found: {args.ipa}")
                sys.exit(1)
            app_path, tmpdir = extract_ipa(args.ipa)
        else:
            app_path = args.app
            if not os.path.isdir(app_path):
                print(f"ERROR: .app not found: {app_path}")
                sys.exit(1)

        passed = validate_app(app_path)
        sys.exit(0 if passed else 1)
    finally:
        if tmpdir and os.path.isdir(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    main()
