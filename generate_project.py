#!/usr/bin/env python3
"""
Tunnexa Xcode Project Generator
================================
Generates Tunnexa.xcodeproj deterministically plus Info.plist files and
entitlements for both targets.

The generator is data-driven: every file, group, build phase and target is
declared once and the .pbxproj is assembled from those declarations. All
object IDs are stable 24-character hexadecimal values, so running this script
multiple times produces byte-identical output (verified at the end of the run).

Usage:
    python3 generate_project.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Deterministic ID factories
# ---------------------------------------------------------------------------

def file_ref_id(seq):
    return f"1100000200020002000000{seq:02X}"

def build_id(seq):
    return f"1100000100010001000000{seq:02X}"

def group_id(seq):
    return f"0000000200020002000000{seq:02X}"

def phase_id(seq):
    return f"8800000100010001000000{seq:02X}"

def framework_phase_id(seq):
    return f"6600000100010001000000{seq:02X}"

def product_file_id(seq):
    return f"2200000200020002000000{seq:02X}"

def target_id(seq):
    return f"2200000100010001000000{seq:02X}"

def target_dep_id(seq):
    return f"2200000300030003000000{seq:02X}"

def container_proxy_id(seq):
    return f"5500000100010001000000{seq:02X}"

def test_file_ref_id(seq):
    return f"4400000200020002000000{seq:02X}"

def test_build_id(seq):
    return f"1100000100010001000000{seq:02X}"

def config_id(seq):
    return f"7700000200020002000000{seq:02X}"

def config_list_id(seq):
    return f"7700000100010001000000{seq:02X}"

def package_ref_id(seq):
    return f"3300000100010001000000{seq:02X}"

def package_product_id(seq):
    return f"3300000200020002000000{seq:02X}"

# ---------------------------------------------------------------------------
# Source file inventory
# ---------------------------------------------------------------------------

APP_BUNDLE_ID = "com.rakib.tunnexa"
EXT_BUNDLE_ID = "com.rakib.tunnexa.PacketTunnel"
APP_GROUP = "group.com.rakib.tunnexa"

# (id, filename, path)
SHARED_FILES = [
    (file_ref_id(0x01), "SharedModels.swift", "Shared"),
    (file_ref_id(0x02), "SharedLogging.swift", "Shared"),
    (file_ref_id(0x04), "KeychainHelper.swift", "Shared"),
    (file_ref_id(0x19), "VPNEnvironmentDetector.swift", "Shared"),
    (file_ref_id(0x1A), "VPNErrorDetails.swift", "Shared"),
    (file_ref_id(0x1B), "SharedSettings.swift", "Shared"),
    (file_ref_id(0x1D), "TunnelState.swift", "Shared"),
]

APP_FILES = [
    # (id, filename, subgroup, compiled-into-app, compiled-into-extension)
    (file_ref_id(0x03), "YAMLParser.swift", "YAML", True, False),
    (file_ref_id(0x07), "VPNManager.swift", "VPN", True, False),
    (file_ref_id(0x15), "ProxyHealthTester.swift", "VPN", True, False),
    (file_ref_id(0x1C), "AutoReconnectPolicy.swift", "VPN", True, False),
    (file_ref_id(0x1E), "DiagnosticsRunner.swift", "VPN", True, False),
    (file_ref_id(0x23), "InAppProxyManager.swift", "VPN", True, False),
    (file_ref_id(0x08), "ProxyViewModel.swift", "ViewModels", True, False),
    (file_ref_id(0x09), "VPNViewModel.swift", "ViewModels", True, False),
    (file_ref_id(0x0A), "MainView.swift", "Views", True, False),
    (file_ref_id(0x0B), "ProxiesView.swift", "Views", True, False),
    (file_ref_id(0x0C), "DiagnosticsView.swift", "Views", True, False),
    (file_ref_id(0x0D), "SettingsView.swift", "Views", True, False),
    (file_ref_id(0x17), "AddProxySheet.swift", "Views", True, False),
    (file_ref_id(0x18), "ImportConfigSheet.swift", "Views", True, False),
    (file_ref_id(0x0E), "TunnexaApp.swift", "App", True, False),
]

EXT_FILES = [
    # (id, filename, subgroup, compiled-into-app, compiled-into-extension)
    (file_ref_id(0x05), "LocalProxyServer.swift", None, True, True),
    (file_ref_id(0x06), "PacketTunnelProvider.swift", None, False, True),
    (file_ref_id(0x1F), "TunnelEngine.swift", None, True, True),
    (file_ref_id(0x20), "ProxyEndpointResolver.swift", None, False, True),
    (file_ref_id(0x21), "EngineConfigBuilder.swift", None, True, True),
    (file_ref_id(0x22), "StartupStateMachine.swift", None, True, True),
]

TEST_FILES = [
    (test_file_ref_id(0x01), "YAMLParserTests.swift"),
    (test_file_ref_id(0x02), "RoutingTests.swift"),
    (test_file_ref_id(0x04), "VPNManagerTests.swift"),
    (test_file_ref_id(0x05), "SOCKS5ProtocolTests.swift"),
    (test_file_ref_id(0x06), "HealthTesterTests.swift"),
    (test_file_ref_id(0x07), "CredentialStoreTests.swift"),
    (test_file_ref_id(0x08), "AutoReconnectTests.swift"),
    (test_file_ref_id(0x09), "LogRedactionTests.swift"),
    (test_file_ref_id(0x0A), "TunnelEngineTests.swift"),
    (test_file_ref_id(0x0B), "EnvironmentDetectorTests.swift"),
    (test_file_ref_id(0x0C), "EngineConfigTests.swift"),
    (test_file_ref_id(0x0D), "StartupStateMachineTests.swift"),
]

APP_BUILD_SEQ = iter(range(0x01, 0x40))
EXT_BUILD_SEQ = iter(range(0x41, 0x60))

def next_app_build():
    return build_id(next(APP_BUILD_SEQ))

def next_ext_build():
    return build_id(next(EXT_BUILD_SEQ))


# Pre-assigned build file IDs (kept stable across generator changes)
def app_build_id(seq):
    return f"1100000100010001000000{seq:02X}"

APP_BUILD_BY_FILE = {
    # file_ref_id -> build id (app)
    file_ref_id(0x01): app_build_id(0x01),
    file_ref_id(0x02): app_build_id(0x03),
    file_ref_id(0x04): app_build_id(0x06),
    file_ref_id(0x03): app_build_id(0x05),
    file_ref_id(0x07): app_build_id(0x09),
    file_ref_id(0x15): app_build_id(0x15),
    file_ref_id(0x08): app_build_id(0x0A),
    file_ref_id(0x09): app_build_id(0x0B),
    file_ref_id(0x0A): app_build_id(0x0C),
    file_ref_id(0x0B): app_build_id(0x0D),
    file_ref_id(0x0C): app_build_id(0x0E),
    file_ref_id(0x0D): app_build_id(0x0F),
    file_ref_id(0x17): app_build_id(0x17),
    file_ref_id(0x18): app_build_id(0x18),
    file_ref_id(0x19): app_build_id(0x19),
    file_ref_id(0x1A): app_build_id(0x1B),
    file_ref_id(0x0E): app_build_id(0x10),
    file_ref_id(0x05): app_build_id(0x26),  # LocalProxyServer in App (for tests)
    file_ref_id(0x1B): app_build_id(0x1E),  # SharedSettings
    file_ref_id(0x1D): app_build_id(0x20),  # TunnelState
    file_ref_id(0x1C): app_build_id(0x22),  # AutoReconnectPolicy
    file_ref_id(0x1E): app_build_id(0x23),  # DiagnosticsRunner
    file_ref_id(0x1F): app_build_id(0x2E),  # TunnelEngine in App (for tests)
    file_ref_id(0x21): app_build_id(0x31),  # EngineConfigBuilder in App (for tests)
    file_ref_id(0x22): app_build_id(0x32),  # StartupStateMachine in App (for tests)
    file_ref_id(0x23): app_build_id(0x30),  # InAppProxyManager
}

EXT_BUILD_BY_FILE = {
    file_ref_id(0x01): app_build_id(0x02),
    file_ref_id(0x02): app_build_id(0x04),
    file_ref_id(0x04): app_build_id(0x16),
    file_ref_id(0x19): app_build_id(0x1A),
    file_ref_id(0x1A): app_build_id(0x1C),
    file_ref_id(0x05): app_build_id(0x07),
    file_ref_id(0x06): app_build_id(0x08),
    file_ref_id(0x1B): app_build_id(0x21),  # SharedSettings
    file_ref_id(0x1D): app_build_id(0x24),  # TunnelState
    file_ref_id(0x1F): app_build_id(0x27),  # TunnelEngine
    file_ref_id(0x20): app_build_id(0x28),  # ProxyEndpointResolver
    file_ref_id(0x21): app_build_id(0x33),  # EngineConfigBuilder
    file_ref_id(0x22): app_build_id(0x34),  # StartupStateMachine
}

TEST_BUILD_BY_FILE = {
    test_file_ref_id(0x01): app_build_id(0x13),
    test_file_ref_id(0x02): app_build_id(0x14),
    test_file_ref_id(0x04): app_build_id(0x1D),
    test_file_ref_id(0x05): app_build_id(0x29),
    test_file_ref_id(0x06): app_build_id(0x2A),
    test_file_ref_id(0x07): app_build_id(0x2B),
    test_file_ref_id(0x08): app_build_id(0x2C),
    test_file_ref_id(0x09): app_build_id(0x2D),
    test_file_ref_id(0x0A): app_build_id(0x2F),
    test_file_ref_id(0x0B): app_build_id(0x35),
    test_file_ref_id(0x0C): app_build_id(0x36),
    test_file_ref_id(0x0D): app_build_id(0x37),
}

# ---------------------------------------------------------------------------
# pbxproj assembly
# ---------------------------------------------------------------------------

APP_TARGET_ID = target_id(0x02)
EXT_TARGET_ID = target_id(0x01)
TEST_TARGET_ID = target_id(0x03)

APP_PRODUCT_ID = product_file_id(0x02)
EXT_PRODUCT_ID = product_file_id(0x01)
TEST_PRODUCT_ID = test_file_ref_id(0x03)

PROJECT_ID = "000000010001000100000001"
MAIN_GROUP_ID = group_id(0x01)
SHARED_GROUP_ID = group_id(0x02)
APP_GROUP_ID = group_id(0x03)
APP_SUBGROUP_IDS = {
    # NOTE: subgroups are PBXGroups — they MUST use the group_id() namespace.
    # Using file_ref_id() here collides with real file references (e.g. the
    # "App" subgroup vs TunnelEngine.swift, both file_ref_id(0x1F)) and makes
    # Xcode drop one of the objects, silently removing a source file from the
    # target. Kept at the same seq values so existing IDs stay stable.
    "App": group_id(0x1F),
    "Views": group_id(0x2F),
    "ViewModels": group_id(0x3F),
    "YAML": group_id(0x5F),
    "VPN": group_id(0x6F),
}
EXT_GROUP_ID = group_id(0x04)
TESTS_GROUP_ID = group_id(0x05)
PRODUCTS_GROUP_ID = group_id(0x06)

PACKAGE_REF_ID = package_ref_id(0x01)
PACKAGE_PRODUCT_ID = package_product_id(0x02)

ENTITLEMENTS_APP_REF = file_ref_id(0x0F)
ENTITLEMENTS_EXT_REF = file_ref_id(0x10)
PLIST_APP_REF = file_ref_id(0x11)
PLIST_EXT_REF = file_ref_id(0x12)

APP_SOURCES_PHASE = phase_id(0x01)
EXT_SOURCES_PHASE = phase_id(0x04)
TEST_SOURCES_PHASE = phase_id(0x05)
APP_FRAMEWORKS_PHASE = framework_phase_id(0x01)
EXT_FRAMEWORKS_PHASE = framework_phase_id(0x02)
TEST_FRAMEWORKS_PHASE = framework_phase_id(0x03)
EMBED_EXTENSIONS_PHASE = phase_id(0x02)

APP_EXT_DEP_ID = target_dep_id(0x01)
APP_TEST_DEP_ID = target_dep_id(0x02)
APP_EXT_PROXY_ID = container_proxy_id(0x01)
APP_TEST_PROXY_ID = container_proxy_id(0x02)

EXT_EMBED_BUILD_ID = app_build_id(0x11)
TUN2SOCKS_BUILD_ID = app_build_id(0x12)


def build_file_ref_line(fid, name):
    return f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"


def indent_lines(body, level=1):
    pad = "\t" * level
    return "\n".join(pad + line if line else "" for line in body.splitlines())


def build_pbxproj():
    lines = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")
    lines.append("")
    lines.append("/* Begin PBXBuildFile section */")

    # Shared files build entries
    for fid, fname, _ in SHARED_FILES:
        app_bid = APP_BUILD_BY_FILE[fid]
        ext_bid = EXT_BUILD_BY_FILE[fid]
        lines.append(f"\t\t{app_bid} /* {fname} in Sources (App) */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};")
        lines.append(f"\t\t{ext_bid} /* {fname} in Sources (Extension) */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};")

    for fid, fname, subgroup, in_app, in_ext in APP_FILES:
        if in_app:
            bid = APP_BUILD_BY_FILE[fid]
            lines.append(f"\t\t{bid} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};")
    for fid, fname, subgroup, in_app, in_ext in EXT_FILES:
        if in_app:
            bid = APP_BUILD_BY_FILE[fid]
            lines.append(f"\t\t{bid} /* {fname} in Sources (App) */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};")
        if in_ext:
            bid = EXT_BUILD_BY_FILE[fid]
            lines.append(f"\t\t{bid} /* {fname} in Sources (Extension) */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};")

    lines.append(f"\t\t{EXT_EMBED_BUILD_ID} /* TunnexaPacketTunnel.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {EXT_PRODUCT_ID} /* TunnexaPacketTunnel.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    lines.append(f"\t\t{TUN2SOCKS_BUILD_ID} /* Tun2SocksKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {PACKAGE_PRODUCT_ID} /* Tun2SocksKit */; }};")

    for fid, fname in TEST_FILES:
        bid = TEST_BUILD_BY_FILE[fid]
        lines.append(f"\t\t{bid} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};")

    lines.append("/* End PBXBuildFile section */")
    lines.append("")

    lines.append("/* Begin PBXContainerItemProxy section */")
    lines.append(f"\t\t{APP_EXT_PROXY_ID} /* PBXContainerItemProxy (App to Extension Dependency) */ = {{")
    lines.append("\t\t\tisa = PBXContainerItemProxy;")
    lines.append(f"\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;")
    lines.append("\t\t\tproxyType = 1;")
    lines.append(f"\t\t\tremoteGlobalIDString = {EXT_TARGET_ID} /* TunnexaPacketTunnel Target */;")
    lines.append("\t\t\tremoteInfo = TunnexaPacketTunnel;")
    lines.append("\t\t};")
    lines.append(f"\t\t{APP_TEST_PROXY_ID} /* PBXContainerItemProxy (App to Test Dependency) */ = {{")
    lines.append("\t\t\tisa = PBXContainerItemProxy;")
    lines.append(f"\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;")
    lines.append("\t\t\tproxyType = 1;")
    lines.append(f"\t\t\tremoteGlobalIDString = {APP_TARGET_ID} /* Tunnexa Target */;")
    lines.append("\t\t\tremoteInfo = Tunnexa;")
    lines.append("\t\t};")
    lines.append("/* End PBXContainerItemProxy section */")
    lines.append("")

    lines.append("/* Begin PBXFileReference section */")
    for fid, fname, _ in SHARED_FILES:
        lines.append(build_file_ref_line(fid, fname))
    for fid, fname, _, _, _ in APP_FILES + EXT_FILES:
        lines.append(build_file_ref_line(fid, fname))
    lines.append(f"\t\t{ENTITLEMENTS_APP_REF} /* Tunnexa.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Tunnexa.entitlements; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{ENTITLEMENTS_EXT_REF} /* TunnexaPacketTunnel.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = TunnexaPacketTunnel.entitlements; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{PLIST_APP_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{PLIST_EXT_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{EXT_PRODUCT_ID} /* TunnexaPacketTunnel.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = TunnexaPacketTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{APP_PRODUCT_ID} /* Tunnexa.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Tunnexa.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for fid, fname in TEST_FILES:
        lines.append(f"\t\t{fid} /* {fname} */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{TEST_PRODUCT_ID} /* TunnexaTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TunnexaTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append("/* End PBXFileReference section */")
    lines.append("")

    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    for phase, name in [(APP_FRAMEWORKS_PHASE, "Frameworks (App)"),
                        (EXT_FRAMEWORKS_PHASE, "Frameworks (Extension)"),
                        (TEST_FRAMEWORKS_PHASE, "Frameworks (Tests)")]:
        lines.append(f"\t\t{phase} /* {name} */ = {{")
        lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
        lines.append("\t\t\tbuildActionMask = 2147483647;")
        lines.append("\t\t\tfiles = (")
        if phase == EXT_FRAMEWORKS_PHASE:
            lines.append(f"\t\t\t\t{TUN2SOCKS_BUILD_ID} /* Tun2SocksKit in Frameworks */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append("\t\t};")
    lines.append("/* End PBXFrameworksBuildPhase section */")
    lines.append("")

    lines.append("/* Begin PBXGroup section */")
    lines.append(f"\t\t{MAIN_GROUP_ID} /* Main Group */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{SHARED_GROUP_ID} /* Shared */,")
    lines.append(f"\t\t\t\t{APP_GROUP_ID} /* Tunnexa App */,")
    lines.append(f"\t\t\t\t{EXT_GROUP_ID} /* TunnexaPacketTunnel Extension */,")
    lines.append(f"\t\t\t\t{TESTS_GROUP_ID} /* TunnexaTests */,")
    lines.append(f"\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    lines.append(f"\t\t{SHARED_GROUP_ID} /* Shared */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for fid, fname, _ in SHARED_FILES:
        lines.append(f"\t\t\t\t{fid} /* {fname} */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Shared;")
    lines.append("\t\t\tpath = Shared;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    # App group with subgroups
    lines.append(f"\t\t{APP_GROUP_ID} /* Tunnexa App */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for sub_id, sub_name in [("App", "App"), ("Views", "Views"), ("ViewModels", "ViewModels"),
                             ("YAML", "YAML"), ("VPN", "VPN")]:
        lines.append(f"\t\t\t\t{APP_SUBGROUP_IDS[sub_name]} /* {sub_name} */,")
    lines.append(f"\t\t\t\t{ENTITLEMENTS_APP_REF} /* Tunnexa.entitlements */,")
    lines.append(f"\t\t\t\t{PLIST_APP_REF} /* Info.plist */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Tunnexa;")
    lines.append("\t\t\tpath = Tunnexa;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    for sub_name in ["App", "Views", "ViewModels", "YAML", "VPN"]:
        sub_id = APP_SUBGROUP_IDS[sub_name]
        children = [fid for fid, fname, subgroup, _, _ in APP_FILES if subgroup == sub_name]
        lines.append(f"\t\t{sub_id} /* {sub_name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        for fid in children:
            fname = next(f for f, n, _, _, _ in APP_FILES if f == fid)
            lines.append(f"\t\t\t\t{fid} /* {fname} */,")
        lines.append("\t\t\t);")
        lines.append(f"\t\t\tname = {sub_name};")
        lines.append(f"\t\t\tpath = {sub_name};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")

    lines.append(f"\t\t{EXT_GROUP_ID} /* TunnexaPacketTunnel Extension */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for fid, fname, _, _, _ in EXT_FILES:
        lines.append(f"\t\t\t\t{fid} /* {fname} */,")
    lines.append(f"\t\t\t\t{ENTITLEMENTS_EXT_REF} /* TunnexaPacketTunnel.entitlements */,")
    lines.append(f"\t\t\t\t{PLIST_EXT_REF} /* Info.plist */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = TunnexaPacketTunnel;")
    lines.append("\t\t\tpath = TunnexaPacketTunnel;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    lines.append(f"\t\t{TESTS_GROUP_ID} /* TunnexaTests */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for fid, fname in TEST_FILES:
        lines.append(f"\t\t\t\t{fid} /* {fname} */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = TunnexaTests;")
    lines.append("\t\t\tpath = TunnexaTests;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    lines.append(f"\t\t{PRODUCTS_GROUP_ID} /* Products */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{APP_PRODUCT_ID} /* Tunnexa.app */,")
    lines.append(f"\t\t\t\t{EXT_PRODUCT_ID} /* TunnexaPacketTunnel.appex */,")
    lines.append(f"\t\t\t\t{TEST_PRODUCT_ID} /* TunnexaTests.xctest */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Products;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    lines.append("/* End PBXGroup section */")
    lines.append("")

    lines.append("/* Begin PBXNativeTarget section */")
    lines.append(f"\t\t{EXT_TARGET_ID} /* TunnexaPacketTunnel Target */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(f"\t\t\tbuildConfigurationList = {config_list_id(0x02)} /* Build configuration list for PBXNativeTarget \"TunnexaPacketTunnel\" */;")
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{EXT_SOURCES_PHASE} /* Sources (Extension) */,")
    lines.append(f"\t\t\t\t{EXT_FRAMEWORKS_PHASE} /* Frameworks (Extension) */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = TunnexaPacketTunnel;")
    lines.append("\t\t\tproductName = TunnexaPacketTunnel;")
    lines.append(f"\t\t\tproductReference = {EXT_PRODUCT_ID} /* TunnexaPacketTunnel.appex */;")
    lines.append("\t\t\tproductType = \"com.apple.product-type.app-extension\";")
    lines.append("\t\t};")

    lines.append(f"\t\t{APP_TARGET_ID} /* Tunnexa Target */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(f"\t\t\tbuildConfigurationList = {config_list_id(0x01)} /* Build configuration list for PBXNativeTarget \"Tunnexa\" */;")
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{APP_SOURCES_PHASE} /* Sources (App) */,")
    lines.append(f"\t\t\t\t{APP_FRAMEWORKS_PHASE} /* Frameworks (App) */,")
    lines.append(f"\t\t\t\t{EMBED_EXTENSIONS_PHASE} /* Embed App Extensions */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append(f"\t\t\t\t{APP_EXT_DEP_ID} /* PBXTargetDependency (App to Extension) */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Tunnexa;")
    lines.append("\t\t\tproductName = Tunnexa;")
    lines.append(f"\t\t\tproductReference = {APP_PRODUCT_ID} /* Tunnexa.app */;")
    lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    lines.append("\t\t};")

    lines.append(f"\t\t{TEST_TARGET_ID} /* TunnexaTests Target */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(f"\t\t\tbuildConfigurationList = {config_list_id(0x04)} /* Build configuration list for PBXNativeTarget \"TunnexaTests\" */;")
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{TEST_SOURCES_PHASE} /* Sources (Tests) */,")
    lines.append(f"\t\t\t\t{TEST_FRAMEWORKS_PHASE} /* Frameworks (Tests) */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append(f"\t\t\t\t{APP_TEST_DEP_ID} /* PBXTargetDependency (App to Test) */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = TunnexaTests;")
    lines.append("\t\t\tproductName = TunnexaTests;")
    lines.append(f"\t\t\tproductReference = {TEST_PRODUCT_ID} /* TunnexaTests.xctest */;")
    lines.append("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    lines.append("\t\t};")
    lines.append("/* End PBXNativeTarget section */")
    lines.append("")

    lines.append("/* Begin PBXProject section */")
    lines.append(f"\t\t{PROJECT_ID} /* Project object */ = {{")
    lines.append("\t\t\tisa = PBXProject;")
    lines.append("\t\t\tattributes = {")
    lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    lines.append("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    lines.append("\t\t\t\tLastUpgradeCheck = 1500;")
    lines.append("\t\t\t\tTargetAttributes = {")
    for tid in (EXT_TARGET_ID, APP_TARGET_ID, TEST_TARGET_ID):
        lines.append(f"\t\t\t\t\t{tid} = {{")
        lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
        lines.append("\t\t\t\t\t};")
    lines.append("\t\t\t\t};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tbuildConfigurationList = {config_list_id(0x03)} /* Build configuration list for PBXProject \"Tunnexa\" */;")
    lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    lines.append("\t\t\tdevelopmentRegion = en;")
    lines.append("\t\t\thasScannedForEncodings = 0;")
    lines.append("\t\t\tknownRegions = (")
    lines.append("\t\t\t\ten,")
    lines.append("\t\t\t\tBase,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tmainGroup = {MAIN_GROUP_ID} /* Main Group */;")
    lines.append(f"\t\t\tpackageReferences = (")
    lines.append(f"\t\t\t\t{PACKAGE_REF_ID} /* RemoteSwiftPackageReference \"Tun2SocksKit\" */,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP_ID} /* Products */;")
    lines.append("\t\t\tprojectDirPath = \"\";")
    lines.append("\t\t\tprojectRoot = \"\";")
    lines.append("\t\t\ttargets = (")
    lines.append(f"\t\t\t\t{APP_TARGET_ID} /* Tunnexa Target */,")
    lines.append(f"\t\t\t\t{EXT_TARGET_ID} /* TunnexaPacketTunnel Target */,")
    lines.append(f"\t\t\t\t{TEST_TARGET_ID} /* TunnexaTests Target */,")
    lines.append("\t\t\t);")
    lines.append("\t\t};")
    lines.append("/* End PBXProject section */")
    lines.append("")

    lines.append("/* Begin PBXCopyFilesBuildPhase section */")
    lines.append(f"\t\t{EMBED_EXTENSIONS_PHASE} /* Embed App Extensions */ = {{")
    lines.append("\t\t\tisa = PBXCopyFilesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tdstPath = \"\";")
    lines.append("\t\t\tdstSubfolderSpec = 13; // PlugIns subdirectory")
    lines.append("\t\t\tfiles = (")
    lines.append(f"\t\t\t\t{EXT_EMBED_BUILD_ID} /* TunnexaPacketTunnel.appex in Embed App Extensions */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = \"Embed App Extensions\";")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXCopyFilesBuildPhase section */")
    lines.append("")

    lines.append("/* Begin PBXSourcesBuildPhase section */")
    lines.append(f"\t\t{APP_SOURCES_PHASE} /* Sources (App) */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for fid, fname, _ in SHARED_FILES:
        lines.append(f"\t\t\t\t{APP_BUILD_BY_FILE[fid]} /* {fname} in Sources (App) */,")
    for fid, fname, _, in_app, _ in APP_FILES:
        if in_app:
            lines.append(f"\t\t\t\t{APP_BUILD_BY_FILE[fid]} /* {fname} in Sources */,")
    for fid, fname, _, in_app, _ in EXT_FILES:
        if in_app:
            lines.append(f"\t\t\t\t{APP_BUILD_BY_FILE[fid]} /* {fname} in Sources (App) */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")

    lines.append(f"\t\t{EXT_SOURCES_PHASE} /* Sources (Extension) */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for fid, fname, _ in SHARED_FILES:
        lines.append(f"\t\t\t\t{EXT_BUILD_BY_FILE[fid]} /* {fname} in Sources (Extension) */,")
    for fid, fname, _, _, in_ext in EXT_FILES:
        if in_ext:
            lines.append(f"\t\t\t\t{EXT_BUILD_BY_FILE[fid]} /* {fname} in Sources (Extension) */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")

    lines.append(f"\t\t{TEST_SOURCES_PHASE} /* Sources (Tests) */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for fid, fname in TEST_FILES:
        lines.append(f"\t\t\t\t{TEST_BUILD_BY_FILE[fid]} /* {fname} in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    lines.append("")

    lines.append("/* Begin PBXTargetDependency section */")
    lines.append(f"\t\t{APP_EXT_DEP_ID} /* PBXTargetDependency (App to Extension) */ = {{")
    lines.append("\t\t\tisa = PBXTargetDependency;")
    lines.append(f"\t\t\ttarget = {EXT_TARGET_ID} /* TunnexaPacketTunnel Target */;")
    lines.append(f"\t\t\ttargetProxy = {APP_EXT_PROXY_ID} /* PBXContainerItemProxy (App to Extension Dependency) */;")
    lines.append("\t\t};")
    lines.append(f"\t\t{APP_TEST_DEP_ID} /* PBXTargetDependency (App to Test) */ = {{")
    lines.append("\t\t\tisa = PBXTargetDependency;")
    lines.append(f"\t\t\ttarget = {APP_TARGET_ID} /* Tunnexa Target */;")
    lines.append(f"\t\t\ttargetProxy = {APP_TEST_PROXY_ID} /* PBXContainerItemProxy (App to Test Dependency) */;")
    lines.append("\t\t};")
    lines.append("/* End PBXTargetDependency section */")
    lines.append("")

    lines.append("/* Begin XCRemoteSwiftPackageReference section */")
    lines.append(f"\t\t{PACKAGE_REF_ID} /* RemoteSwiftPackageReference \"Tun2SocksKit\" */ = {{")
    lines.append("\t\t\tisa = XCRemoteSwiftPackageReference;")
    lines.append("\t\t\trepositoryURL = \"https://github.com/EbrahimTahernejad/Tun2SocksKit.git\";")
    lines.append("\t\t\trequirement = {")
    lines.append("\t\t\t\tkind = upToNextMajorVersion;")
    lines.append("\t\t\t\tminimumVersion = 5.15.0;")
    lines.append("\t\t\t};")
    lines.append("\t\t};")
    lines.append("/* End XCRemoteSwiftPackageReference section */")
    lines.append("")

    lines.append("/* Begin XCSwiftPackageProductDependency section */")
    lines.append(f"\t\t{PACKAGE_PRODUCT_ID} /* Tun2SocksKit */ = {{")
    lines.append("\t\t\tisa = XCSwiftPackageProductDependency;")
    lines.append(f"\t\t\tpackage = {PACKAGE_REF_ID} /* RemoteSwiftPackageReference \"Tun2SocksKit\" */;")
    lines.append("\t\t\tproductName = Tun2SocksKit;")
    lines.append("\t\t};")
    lines.append("/* End XCSwiftPackageProductDependency section */")
    lines.append("")

    # Build configurations
    lines.append("/* Begin XCBuildConfiguration section */")

    app_config = """
\t\t{APP_DEBUG} /* Debug Configuration (App) */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Tunnexa/Tunnexa.entitlements;
\t\t\t\tCODE_SIGN_IDENTITY = "Apple Development";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "";
\t\t\t\tENABLE_DEBUG_DYLIB = NO;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Tunnexa/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Debug;
\t\t};
""".replace("{APP_DEBUG}", config_id(0x01))

    app_release_config = app_config.replace("Debug Configuration (App)", "Release Configuration (App)") \
        .replace("SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";", "SWIFT_OPTIMIZATION_LEVEL = \"-O\";") \
        .replace("name = Debug;", "name = Release;")
    app_release_config = app_release_config.replace(config_id(0x01), config_id(0x02))

    ext_config = """
\t\t{EXT_DEBUG} /* Debug Configuration (Extension) */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = TunnexaPacketTunnel/TunnexaPacketTunnel.entitlements;
\t\t\t\tCODE_SIGN_IDENTITY = "Apple Development";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = TunnexaPacketTunnel/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa.PacketTunnel;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Debug;
\t\t};
""".replace("{EXT_DEBUG}", config_id(0x03))

    ext_release_config = ext_config.replace("Debug Configuration (Extension)", "Release Configuration (Extension)") \
        .replace("SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";", "SWIFT_OPTIMIZATION_LEVEL = \"-O\";") \
        .replace("name = Debug;", "name = Release;")
    ext_release_config = ext_release_config.replace(config_id(0x03), config_id(0x04))

    project_debug = """
\t\t{PROJ_DEBUG} /* Debug Configuration (Project) */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCLANG_WARN_BLOCK_PCT_TO_POINTER_CAST = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t};
\t\t\tname = Debug;
\t\t};
""".replace("{PROJ_DEBUG}", config_id(0x05))

    project_release = """
\t\t{PROJ_RELEASE} /* Release Configuration (Project) */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCLANG_WARN_BLOCK_PCT_TO_POINTER_CAST = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCOPY_PHASE_STRIP = YES;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};
""".replace("{PROJ_RELEASE}", config_id(0x06))

    test_debug = """
\t\t{TEST_DEBUG} /* Debug Configuration (Tests) */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@loader_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa.TunnexaTests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tunnexa.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tunnexa";
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t};
\t\t\tname = Debug;
\t\t};
""".replace("{TEST_DEBUG}", config_id(0x07))

    test_release = test_debug.replace("Debug Configuration (Tests)", "Release Configuration (Tests)") \
        .replace("SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";", "SWIFT_OPTIMIZATION_LEVEL = \"-O\";") \
        .replace("name = Debug;", "name = Release;")
    test_release = test_release.replace(config_id(0x07), config_id(0x08))

    for block in (app_config, app_release_config, ext_config, ext_release_config,
                  project_debug, project_release, test_debug, test_release):
        lines.append(block)

    lines.append("/* End XCBuildConfiguration section */")
    lines.append("")

    lines.append("/* Begin XCConfigurationList section */")
    for cl_id, comment, config_ids, default in [
        (config_list_id(0x01), "Build configuration list for PBXNativeTarget \"Tunnexa\"", [config_id(0x01), config_id(0x02)], "Release"),
        (config_list_id(0x02), "Build configuration list for PBXNativeTarget \"TunnexaPacketTunnel\"", [config_id(0x03), config_id(0x04)], "Release"),
        (config_list_id(0x03), "Build configuration list for PBXProject \"Tunnexa\"", [config_id(0x05), config_id(0x06)], "Release"),
        (config_list_id(0x04), "Build configuration list for PBXNativeTarget \"TunnexaTests\"", [config_id(0x07), config_id(0x08)], "Release"),
    ]:
        lines.append(f"\t\t{cl_id} /* {comment} */ = {{")
        lines.append("\t\t\tisa = XCConfigurationList;")
        lines.append("\t\t\tbuildConfigurations = (")
        for cid in config_ids:
            lines.append(f"\t\t\t\t{cid} /* {'Debug' if cid.endswith('01') or cid.endswith('03') or cid.endswith('05') or cid.endswith('07') else 'Release'} */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        lines.append(f"\t\t\tdefaultConfigurationName = {default};")
        lines.append("\t\t};")
    lines.append("/* End XCConfigurationList section */")
    lines.append("\t};")
    lines.append(f"\trootObject = {PROJECT_ID} /* Project object */;")
    lines.append("}")
    return "\n".join(lines)


def write_plists():
    os.makedirs(os.path.join(ROOT, "Tunnexa"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "TunnexaPacketTunnel"), exist_ok=True)

    app_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>en</string>
\t<key>CFBundleDisplayName</key>
\t<string>Tunnexa</string>
\t<key>CFBundleExecutable</key>
\t<string>$(EXECUTABLE_NAME)</string>
\t<key>CFBundleIdentifier</key>
\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
\t<key>CFBundleInfoDictionaryVersion</key>
\t<string>6.0</string>
\t<key>CFBundleName</key>
\t<string>$(PRODUCT_NAME)</string>
\t<key>CFBundlePackageType</key>
\t<string>APPL</string>
\t<key>CFBundleShortVersionString</key>
\t<string>1.0.0</string>
\t<key>CFBundleVersion</key>
\t<string>1</string>
\t<key>LSRequiresIPhoneOS</key>
\t<true/>
\t<key>UIApplicationSceneManifest</key>
\t<dict>
\t\t<key>UIApplicationSupportsMultipleScenes</key>
\t\t<false/>
\t</dict>
\t<key>UILaunchScreen</key>
\t<dict/>
\t<key>UISupportedInterfaceOrientations</key>
\t<array>
\t\t<string>UIInterfaceOrientationPortrait</string>
\t</array>
\t<key>NSAppTransportSecurity</key>
\t<dict>
\t\t<key>NSAllowsArbitraryLoads</key>
\t\t<true/>
\t</dict>
\t<key>CFBundleDocumentTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleTypeName</key>
\t\t\t<string>YAML Configuration</string>
\t\t\t<key>LSHandlerRank</key>
\t\t\t<string>Owner</string>
\t\t\t<key>LSItemContentTypes</key>
\t\t\t<array>
\t\t\t\t<string>public.yaml</string>
\t\t\t\t<string>public.yml</string>
\t\t\t</array>
\t\t</dict>
\t</array>
\t<key>UTImportedTypeDeclarations</key>
\t<array>
\t\t<dict>
\t\t\t<key>UTTypeConformsTo</key>
\t\t\t<array>
\t\t\t\t<string>public.text</string>
\t\t\t\t<string>public.data</string>
\t\t\t</array>
\t\t\t<key>UTTypeDescription</key>
\t\t\t<string>YAML Configuration File</string>
\t\t\t<key>UTTypeIdentifier</key>
\t\t\t<string>public.yaml</string>
\t\t\t<key>UTTypeTagSpecification</key>
\t\t\t<dict>
\t\t\t\t<key>public.filename-extension</key>
\t\t\t\t<array>
\t\t\t\t\t<string>yaml</string>
\t\t\t\t\t<string>yml</string>
\t\t\t\t</array>
\t\t\t</dict>
\t\t</dict>
\t</array>
</dict>
</plist>
"""
    with open(os.path.join(ROOT, "Tunnexa", "Info.plist"), "w", encoding="utf-8") as f:
        f.write(app_plist)

    ext_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>en</string>
\t<key>CFBundleDisplayName</key>
\t<string>TunnexaPacketTunnel</string>
\t<key>CFBundleExecutable</key>
\t<string>$(EXECUTABLE_NAME)</string>
\t<key>CFBundleIdentifier</key>
\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
\t<key>CFBundleInfoDictionaryVersion</key>
\t<string>6.0</string>
\t<key>CFBundleName</key>
\t<string>$(PRODUCT_NAME)</string>
\t<key>CFBundlePackageType</key>
\t<string>XPC!</string>
\t<key>CFBundleShortVersionString</key>
\t<string>1.0.0</string>
\t<key>CFBundleVersion</key>
\t<string>1</string>
\t<key>NSExtension</key>
\t<dict>
\t\t<key>NSExtensionPointIdentifier</key>
\t\t<string>com.apple.networkextension.packet-tunnel</string>
\t\t<key>NSExtensionPrincipalClass</key>
\t\t<string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
\t</dict>
</dict>
</plist>
"""
    with open(os.path.join(ROOT, "TunnexaPacketTunnel", "Info.plist"), "w", encoding="utf-8") as f:
        f.write(ext_plist)

    entitlements = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>group.com.rakib.tunnexa</string>
\t</array>
\t<key>com.apple.developer.networking.networkextension</key>
\t<array>
\t\t<string>packet-tunnel-provider</string>
\t</array>
</dict>
</plist>
"""
    with open(os.path.join(ROOT, "Tunnexa", "Tunnexa.entitlements"), "w", encoding="utf-8") as f:
        f.write(entitlements)
    with open(os.path.join(ROOT, "TunnexaPacketTunnel", "TunnexaPacketTunnel.entitlements"), "w", encoding="utf-8") as f:
        f.write(entitlements)


def validate_project(pbxproj_path):
    """Integrity check: every referenced object ID must be defined exactly once.

    Two objects sharing one ID (e.g. a subgroup allocated from the file-ref
    namespace) silently makes Xcode drop one of them — a source file can
    vanish from a target without any 'undefined reference' symptom.
    """
    with open(pbxproj_path, encoding="utf-8") as f:
        content = f.read()

    defined = re.findall(r"^\t\t([0-9A-F]{24}) ", content, re.M)
    duplicate_ids = sorted({d for d in defined if defined.count(d) > 1})
    if duplicate_ids:
        for dup in duplicate_ids:
            print(f"  [FAIL] Object ID defined more than once: {dup}")
        return False

    defined_set = set(defined)
    referenced = set(re.findall(r"= ([0-9A-F]{24}) ", content))
    referenced |= set(re.findall(r"remoteGlobalIDString = ([0-9A-F]{24})", content))

    missing = referenced - defined_set
    if missing:
        for m in sorted(missing):
            print(f"  [FAIL] Undefined object ID referenced: {m}")
        return False

    # No 20-char or malformed IDs should exist
    bad_ids = re.findall(r"\b[0-9A-F]{17,23}\b", content)
    bad_ids = [b for b in bad_ids if len(b) != 24]
    if bad_ids:
        print(f"  [FAIL] Malformed IDs found: {set(bad_ids)}")
        return False

    print("  [ OK ] All pbxproj object references resolve.")
    return True


def build_scheme():
    """Shared scheme with the test action wired to TunnexaTests.

    Without this, Xcode auto-generates a scheme that has no TestAction and
    `xcodebuild test` fails with 'Scheme Tunnexa is not currently configured
    for the test action'.
    """
    app_ref = (
        f'<BuildableReference\n'
        f'               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{APP_TARGET_ID}"\n'
        f'               BuildableName = "Tunnexa.app"\n'
        f'               BlueprintName = "Tunnexa"\n'
        f'               ReferencedContainer = "container:Tunnexa.xcodeproj">\n'
        f'            </BuildableReference>'
    )
    ext_ref = (
        f'<BuildableReference\n'
        f'               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{EXT_TARGET_ID}"\n'
        f'               BuildableName = "TunnexaPacketTunnel.appex"\n'
        f'               BlueprintName = "TunnexaPacketTunnel"\n'
        f'               ReferencedContainer = "container:Tunnexa.xcodeproj">\n'
        f'            </BuildableReference>'
    )
    test_ref = (
        f'<BuildableReference\n'
        f'               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{TEST_TARGET_ID}"\n'
        f'               BuildableName = "TunnexaTests.xctest"\n'
        f'               BlueprintName = "TunnexaTests"\n'
        f'               ReferencedContainer = "container:Tunnexa.xcodeproj">\n'
        f'            </BuildableReference>'
    )

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ext_ref}
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "YES">
            {test_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            {test_ref}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def create_project():
    print("Generating Tunnexa Xcode Project structure...")

    xcodeproj_dir = os.path.join(ROOT, "Tunnexa.xcodeproj")
    workspace_dir = os.path.join(xcodeproj_dir, "project.xcworkspace")
    os.makedirs(workspace_dir, exist_ok=True)

    workspace_content = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    with open(os.path.join(workspace_dir, "contents.xcworkspacedata"), "w", encoding="utf-8") as f:
        f.write(workspace_content)

    pbxproj_path = os.path.join(xcodeproj_dir, "project.pbxproj")
    pbxproj_content = build_pbxproj()
    with open(pbxproj_path, "w", encoding="utf-8") as f:
        f.write(pbxproj_content)

    scheme_dir = os.path.join(xcodeproj_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, "Tunnexa.xcscheme"), "w", encoding="utf-8") as f:
        f.write(build_scheme())

    print("Created Tunnexa.xcodeproj structures successfully.")

    write_plists()
    print("Created entitlements and Plist configurations.")

    if not validate_project(pbxproj_path):
        sys.exit(1)

    # Determinism check: generating twice must produce identical output.
    with open(pbxproj_path, encoding="utf-8") as f:
        first = f.read()
    second = build_pbxproj()
    if first != second:
        print("  [FAIL] Generator is not deterministic.")
        sys.exit(1)
    print("  [ OK ] Generator is deterministic.")


if __name__ == "__main__":
    create_project()