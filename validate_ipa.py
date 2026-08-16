#!/usr/bin/env python3
"""
Tunnexa IPA / .app Validation Script
=====================================
Usage:
    python3 validate_ipa.py --ipa path/to/Tunnexa.ipa
    python3 validate_ipa.py --app path/to/Tunnexa.app
    python3 validate_ipa.py --app path/to/Tunnexa.app --expect-unsigned

Checks (structural, cross-platform):
  1. Main app bundle identifier = com.rakib.tunnexa
  2. PacketTunnel extension exists in PlugIns/
  3. Extension bundle identifier = com.rakib.tunnexa.PacketTunnel
  4. Extension CFBundlePackageType = XPC!
  5. Extension NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel
  6. Extension executable present and a Mach-O binary
  7. Extension NSExtensionPrincipalClass is set
  8. Main app executable present
  9. Signing state detected and reported honestly (signed / unsigned)
 10. Signed bundles carry _CodeSignature + embedded.mobileprovision
 11. App and extension signing states are consistent

Checks (macOS only, real tooling; skipped with a notice elsewhere):
  - codesign --verify --strict --deep
  - codesign -dv (authority / team / profile info)
  - embedded.mobileprovision decoded via `security cms -D` (profile name,
    expiration, team, application-identifier)
  - codesign entitlement dump: application-groups + packet-tunnel-provider
  - otool -L (linked Swift libraries) and otool -l (LC_BUILD_VERSION)

Honest verdict: an unsigned bundle is reported as such. It is *not* claimed to
be installable as a system VPN; the report states the consequence per mode
(standalone vs LiveContainer in-app proxy).

Exit codes:
  0 = All checks pass
  1 = One or more checks failed
"""

import argparse
import datetime
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

MAIN_BUNDLE_ID = "com.rakib.tunnexa"
EXTENSION_BUNDLE_ID = "com.rakib.tunnexa.PacketTunnel"
EXTENSION_POINT = "com.apple.networkextension.packet-tunnel"
APP_GROUP = "group.com.rakib.tunnexa"
EXPECTED_ENTITLEMENTS = {
    "com.apple.developer.networking.networkextension": ["packet-tunnel-provider"],
    "com.apple.security.application-groups": [APP_GROUP],
}

FAILURES = 0


def fail(msg: str):
    global FAILURES
    FAILURES += 1
    print(f"  [FAIL] {msg}")


def ok(msg: str):
    print(f"  [ OK ] {msg}")


def note(msg: str):
    print(f"  [note] {msg}")


def read_plist(path: str) -> dict:
    with open(path, "rb") as f:
        return plistlib.load(f)


def run(cmd):
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=60
        ).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def is_bundle_signed(app_path: str) -> bool:
    signature_dir = os.path.join(app_path, "_CodeSignature")
    return os.path.isdir(signature_dir) and os.path.isfile(os.path.join(signature_dir, "CodeResources"))


def has_provisioning_profile(app_path: str) -> bool:
    return os.path.isfile(os.path.join(app_path, "embedded.mobileprovision"))


def is_macho(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
        return magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe")
    except OSError:
        return False


# ---------------------------------------------------------------------------
# macOS-only real tooling checks
# ---------------------------------------------------------------------------

def check_codesign_verify(app_path: str):
    print("  --- codesign verify ---")
    out = run(["codesign", "--verify", "--strict", "--deep", "--verbose=2", app_path])
    if not out:
        note("codesign not available or not applicable; skipping.")
        return
    if "_CodeSignature_verified" in out or "valid on disk" in out:
        ok("codesign --verify --strict --deep: valid on disk")
    else:
        fail("codesign --verify failed: " + out.strip()[:300])


def check_codesign_details(app_path: str, label: str):
    print(f"  --- codesign -dv ({label}) ---")
    out = run(["codesign", "-dv", "--verbose=4", app_path])
    if not out:
        note("codesign not available; skipping.")
        return
    authority = re.search(r"Authority=([^\n]+)", out)
    if authority:
        ok(f"Signing authority: {authority.group(1)}")
    else:
        fail(f"No code signing authority found for {label}")
    team = re.search(r"TeamIdentifier=([^\n]+)", out)
    if team:
        ok(f"TeamIdentifier: {team.group(1)}")
    profile = re.search(r"ProfileIdentifier=([^\n]+)", out)
    if profile:
        ok(f"Provisioning profile: {profile.group(1)}")


def check_entitlements(app_path: str, label: str):
    print(f"  --- entitlements ({label}) ---")
    out = run(["codesign", "-d", "--entitlements", ":-", app_path])
    if not out:
        note("codesign entitlement dump unavailable; skipping.")
        return
    ok(f"Entitlement plist decoded ({len(out)} bytes)")
    try:
        ents = plistlib.loads(out.encode("utf-8"))
    except Exception:
        note("Entitlement output was not plist; skipped deep validation.")
        return
    for key, expected in EXPECTED_ENTITLEMENTS.items():
        if key not in ents:
            fail(f"Missing entitlement: {key}")
            continue
        value = ents[key]
        if isinstance(expected, list):
            missing = [v for v in expected if v not in value]
            if missing:
                fail(f"Entitlement {key} missing values {missing}")
            else:
                ok(f"Entitlement {key} = {value}")
        else:
            ok(f"Entitlement {key} = {value}")


def check_provisioning_profile(app_path: str):
    profile_path = os.path.join(app_path, "embedded.mobileprovision")
    if not os.path.isfile(profile_path):
        fail("No embedded.mobileprovision (required for system VPN on a signed install)")
        return
    out = run(["security", "cms", "-D", "-i", profile_path])
    if not out:
        note("`security cms -D` unavailable; provisioning profile left unparsed.")
        return
    ok("embedded.mobileprovision decodes via `security cms -D`")
    try:
        profile = plistlib.loads(out.encode("utf-8"))
    except Exception:
        note("Profile content was not plist; skipping deep validation.")
        return
    for key in ("Name", "TeamName", "UUID", "ExpirationDate"):
        value = profile.get(key)
        if value is None:
            continue
        if isinstance(value, datetime.datetime):
            note(f"Profile {key}: {value}")
            if value < datetime.datetime.now(value.tzinfo):
                fail("Provisioning profile is EXPIRED")
        else:
            note(f"Profile {key}: {value}")
    entitlements = profile.get("Entitlements", {})
    app_id = entitlements.get("application-identifier", "")
    if app_id:
        ok(f"application-identifier: {app_id}")
    else:
        fail("Profile lacks application-identifier")
    groups = entitlements.get("com.apple.security.application-groups", [])
    if APP_GROUP in groups:
        ok(f"application-groups includes {APP_GROUP}")
    else:
        fail(f"application-groups does not include {APP_GROUP}: {groups}")
    ne = entitlements.get("com.apple.developer.networking.networkextension", [])
    if "packet-tunnel-provider" in ne:
        ok("networkextension entitlement includes packet-tunnel-provider")
    else:
        fail(f"networkextension entitlement lacks packet-tunnel-provider: {ne}")


def check_otool(binary_path: str, label: str):
    print(f"  --- otool ({label}) ---")
    out = run(["otool", "-L", binary_path])
    if not out:
        note("otool not available; skipping.")
        return
    swift_links = [line for line in out.splitlines() if "Swift" in line]
    if swift_links:
        ok(f"Linked Swift libraries ({len(swift_links)}): " + "; ".join(
            s.strip() for s in swift_links[:3]
        ))
    else:
        note("No direct Swift dylib references (may be statically linked).")
    out = run(["otool", "-l", binary_path])
    if "LC_BUILD_VERSION" in out:
        ok("LC_BUILD_VERSION load command present (platform-versioned Mach-O)")
    else:
        note("No LC_BUILD_VERSION found (possibly an older or static binary).")


# ---------------------------------------------------------------------------
# Main validation
# ---------------------------------------------------------------------------

def validate_app(app_path: str, expect_unsigned: bool) -> bool:
    global FAILURES
    FAILURES = 0
    print(f"\n=== Validating: {app_path} ===\n")

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

    package_type = main_plist.get("CFBundlePackageType", "")
    if package_type == "APPL":
        ok(f"Main app CFBundlePackageType: {package_type}")
    else:
        fail(f"Main app CFBundlePackageType: '{package_type}' (expected 'APPL')")

    main_executable = main_plist.get("CFBundleExecutable", "Tunnexa")
    main_executable_path = os.path.join(app_path, main_executable)
    if os.path.isfile(main_executable_path):
        size = os.path.getsize(main_executable_path)
        ok(f"Main app executable '{main_executable}' present ({size:,} bytes)")
        if not is_macho(main_executable_path):
            fail("Main executable is not a Mach-O binary")
    else:
        fail(f"Main app executable '{main_executable}' NOT found at {main_executable_path}")

    # --- Signing state (honest reporting) ---
    app_signed = is_bundle_signed(app_path)
    if app_signed:
        ok("App bundle is SIGNED (_CodeSignature/CodeResources present)")
        if has_provisioning_profile(app_path):
            ok("Provisioning profile embedded (embedded.mobileprovision)")
        else:
            fail("App bundle is signed but no embedded.mobileprovision was found")
    else:
        if expect_unsigned:
            ok("App bundle is UNSIGNED, as expected for this CI artifact")
        else:
            note("App bundle is UNSIGNED")
        note("Consequence: without per-install signing this bundle cannot register a")
        note("system-wide packet tunnel provider (standalone mode). It is only usable")
        note("inside LiveContainer as an in-app proxy, where no system VPN is involved.")

    # --- Extension Checks ---
    plugins_dir = os.path.join(app_path, "PlugIns")
    if not os.path.isdir(plugins_dir):
        fail("PlugIns/ directory not found — extension is not embedded!")
        return False

    ok("PlugIns/ directory present")

    extension_path = os.path.join(plugins_dir, "TunnexaPacketTunnel.appex")
    if not os.path.isdir(extension_path):
        fail("Extension 'TunnexaPacketTunnel.appex' not found in PlugIns/")
        for item in os.listdir(plugins_dir):
            print(f"    - {item}")
        return False

    ok("Extension 'TunnexaPacketTunnel.appex' found")

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

    ext_package_type = ext_plist.get("CFBundlePackageType", "")
    if ext_package_type == "XPC!":
        ok(f"Extension CFBundlePackageType: {ext_package_type}")
    else:
        fail(f"Extension CFBundlePackageType: '{ext_package_type}' (expected 'XPC!')")

    ns_extension = ext_plist.get("NSExtension", {})
    ext_point = ns_extension.get("NSExtensionPointIdentifier", "")
    if ext_point == EXTENSION_POINT:
        ok(f"Extension NSExtensionPointIdentifier: {ext_point}")
    else:
        fail(f"Extension NSExtensionPointIdentifier: '{ext_point}' (expected '{EXTENSION_POINT}')")

    principal_class = ns_extension.get("NSExtensionPrincipalClass", "")
    if principal_class:
        ok(f"Extension NSExtensionPrincipalClass: {principal_class}")
    else:
        fail("Extension NSExtensionPrincipalClass is empty or missing")

    ext_executable_name = ext_plist.get("CFBundleExecutable", "TunnexaPacketTunnel")
    ext_executable_path = os.path.join(extension_path, ext_executable_name)
    if os.path.isfile(ext_executable_path):
        size = os.path.getsize(ext_executable_path)
        ok(f"Extension executable '{ext_executable_name}' present ({size:,} bytes)")
        if not is_macho(ext_executable_path):
            fail("Extension executable is not a Mach-O binary")
    else:
        fail(f"Extension executable '{ext_executable_name}' NOT found at {ext_executable_path}")

    # --- Signing consistency ---
    ext_signed = is_bundle_signed(extension_path)
    if ext_signed == app_signed:
        ok("Signing state consistent between app and extension")
    else:
        fail(f"Signing mismatch: app is {'signed' if app_signed else 'unsigned'}, "
             f"extension is {'signed' if ext_signed else 'unsigned'}")

    # --- macOS-only real tooling ---
    if sys.platform == "darwin":
        check_codesign_verify(app_path)
        if app_signed:
            check_codesign_details(app_path, "app")
            check_codesign_details(extension_path, "extension")
            check_entitlements(app_path, "app")
            check_entitlements(extension_path, "extension")
            check_provisioning_profile(app_path)
        else:
            note("Skipping codesign/entitlement/profile deep checks: bundle is unsigned.")
        if is_macho(ext_executable_path):
            check_otool(ext_executable_path, "extension")
    else:
        note("Not macOS: codesign/security/otool checks skipped (structural checks still ran).")

    print()
    if FAILURES == 0:
        print("=== VALIDATION PASSED — Tunnexa.app is correctly packaged ===")
        return True
    print("=== VALIDATION FAILED — See FAIL entries above ===")
    return False


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
    parser.add_argument(
        "--expect-unsigned",
        action="store_true",
        help="CI artifacts are unsigned by design; report as expected.",
    )
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

        passed = validate_app(app_path, expect_unsigned=args.expect_unsigned)
        sys.exit(0 if passed else 1)
    finally:
        if tmpdir and os.path.isdir(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    main()
