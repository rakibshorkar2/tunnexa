import os

def create_project():
    print("Generating Tunnexa Xcode Project structure...")

    # Define directories
    xcodeproj_dir = "Tunnexa.xcodeproj"
    workspace_dir = os.path.join(xcodeproj_dir, "project.xcworkspace")
    os.makedirs(workspace_dir, exist_ok=True)

    # 1. Write project.xcworkspace/contents.xcworkspacedata
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

    # 2. Write project.pbxproj
    # We use stable deterministic 24-character hexadecimal IDs for our files, groups, targets and build configurations.
    pbxproj_content = """// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		110000010001000100000001 /* SharedModels.swift in Sources (App) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000001 /* SharedModels.swift */; };
		110000010001000100000002 /* SharedModels.swift in Sources (Extension) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000001 /* SharedModels.swift */; };
		110000010001000100000003 /* SharedLogging.swift in Sources (App) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000002 /* SharedLogging.swift */; };
		110000010001000100000004 /* SharedLogging.swift in Sources (Extension) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000002 /* SharedLogging.swift */; };
		110000010001000100000005 /* YAMLParser.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000003 /* YAMLParser.swift */; };
		110000010001000100000006 /* KeychainHelper.swift in Sources (App) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000004 /* KeychainHelper.swift */; };
		110000010001000100000016 /* KeychainHelper.swift in Sources (Extension) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000004 /* KeychainHelper.swift */; };
		110000010001000100000007 /* LocalProxyServer.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000005 /* LocalProxyServer.swift */; };
		110000010001000100000008 /* PacketTunnelProvider.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000006 /* PacketTunnelProvider.swift */; };
		110000010001000100000009 /* VPNManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000007 /* VPNManager.swift */; };
		11000001000100010000000A /* ProxyViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000008 /* ProxyViewModel.swift */; };
		11000001000100010000000B /* VPNViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000009 /* VPNViewModel.swift */; };
		11000001000100010000000C /* MainView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11000002000200020000000A /* MainView.swift */; };
		11000001000100010000000D /* ProxiesView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11000002000200020000000B /* ProxiesView.swift */; };
		11000001000100010000000E /* DiagnosticsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11000002000200020000000C /* DiagnosticsView.swift */; };
		11000001000100010000000F /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11000002000200020000000D /* SettingsView.swift */; };
		110000010001000100000010 /* TunnexaApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11000002000200020000000E /* TunnexaApp.swift */; };
		110000010001000100000011 /* TunnexaPacketTunnel.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = 220000020002000200000001 /* TunnexaPacketTunnel.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		110000010001000100000012 /* Tun2SocksKit in Frameworks */ = {isa = PBXBuildFile; productRef = 330000020002000200000002 /* Tun2SocksKit */; };
		110000010001000100000013 /* YAMLParserTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 440000020002000200000001 /* YAMLParserTests.swift */; };
		110000010001000100000014 /* RoutingTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 440000020002000200000002 /* RoutingTests.swift */; };
		11000001000100010000001D /* VPNManagerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 440000020002000200000004 /* VPNManagerTests.swift */; };
		110000010001000100000015 /* ProxyHealthTester.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000015 /* ProxyHealthTester.swift */; };
		110000010001000100000017 /* AddProxySheet.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000017 /* AddProxySheet.swift */; };
		110000010001000100000018 /* ImportConfigSheet.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000020002000200000018 /* ImportConfigSheet.swift */; };
		110000010001000100000019 /* VPNEnvironmentDetector.swift in Sources (App) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000019 /* VPNEnvironmentDetector.swift */; };
		11000001000100010000001A /* VPNEnvironmentDetector.swift in Sources (Extension) */ = {isa = PBXBuildFile; fileRef = 110000020002000200000019 /* VPNEnvironmentDetector.swift */; };
		11000001000100010000001B /* VPNErrorDetails.swift in Sources (App) */ = {isa = PBXBuildFile; fileRef = 11000002000200020000001A /* VPNErrorDetails.swift */; };
		11000001000100010000001C /* VPNErrorDetails.swift in Sources (Extension) */ = {isa = PBXBuildFile; fileRef = 11000002000200020000001A /* VPNErrorDetails.swift */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		550000010001000100000001 /* PBXContainerItemProxy (App to Extension Dependency) */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000010001000100000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 220000010001000100000001 /* TunnexaPacketTunnel Target */;
			remoteInfo = TunnexaPacketTunnel;
		};
		550000010001000100000002 /* PBXContainerItemProxy (App to Test Dependency) */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000010001000100000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 220000010001000100000002 /* Tunnexa Target */;
			remoteInfo = Tunnexa;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		110000020002000200000001 /* SharedModels.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = SharedModels.swift; sourceTree = "<group>"; };
		110000020002000200000002 /* SharedLogging.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = SharedLogging.swift; sourceTree = "<group>"; };
		110000020002000200000003 /* YAMLParser.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = YAMLParser.swift; sourceTree = "<group>"; };
		110000020002000200000004 /* KeychainHelper.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = KeychainHelper.swift; sourceTree = "<group>"; };
		110000020002000200000005 /* LocalProxyServer.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = LocalProxyServer.swift; sourceTree = "<group>"; };
		110000020002000200000006 /* PacketTunnelProvider.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = PacketTunnelProvider.swift; sourceTree = "<group>"; };
		110000020002000200000007 /* VPNManager.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = VPNManager.swift; sourceTree = "<group>"; };
		110000020002000200000015 /* ProxyHealthTester.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = ProxyHealthTester.swift; sourceTree = "<group>"; };
		110000020002000200000008 /* ProxyViewModel.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = ProxyViewModel.swift; sourceTree = "<group>"; };
		110000020002000200000009 /* VPNViewModel.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = VPNViewModel.swift; sourceTree = "<group>"; };
		11000002000200020000000A /* MainView.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = MainView.swift; sourceTree = "<group>"; };
		11000002000200020000000B /* ProxiesView.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = ProxiesView.swift; sourceTree = "<group>"; };
		11000002000200020000000C /* DiagnosticsView.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = DiagnosticsView.swift; sourceTree = "<group>"; };
		11000002000200020000000D /* SettingsView.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		110000020002000200000017 /* AddProxySheet.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = AddProxySheet.swift; sourceTree = "<group>"; };
		110000020002000200000018 /* ImportConfigSheet.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = ImportConfigSheet.swift; sourceTree = "<group>"; };
		11000002000200020000000E /* TunnexaApp.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = TunnexaApp.swift; sourceTree = "<group>"; };
		11000002000200020000000F /* Tunnexa.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Tunnexa.entitlements; sourceTree = "<group>"; };
		110000020002000200000010 /* TunnexaPacketTunnel.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = TunnexaPacketTunnel.entitlements; sourceTree = "<group>"; };
		110000020002000200000011 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		110000020002000200000012 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		220000020002000200000001 /* TunnexaPacketTunnel.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = TunnexaPacketTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; };
		220000020002000200000002 /* Tunnexa.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Tunnexa.app; sourceTree = BUILT_PRODUCTS_DIR; };
		440000020002000200000001 /* YAMLParserTests.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = YAMLParserTests.swift; sourceTree = "<group>"; };
		440000020002000200000002 /* RoutingTests.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = RoutingTests.swift; sourceTree = "<group>"; };
		440000020002000200000004 /* VPNManagerTests.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = VPNManagerTests.swift; sourceTree = "<group>"; };
		440000020002000200000003 /* TunnexaTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TunnexaTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		110000020002000200000019 /* VPNEnvironmentDetector.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = VPNEnvironmentDetector.swift; sourceTree = "<group>"; };
		11000002000200020000001A /* VPNErrorDetails.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = VPNErrorDetails.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		660000010001000100000001 /* Frameworks (App) */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		660000010001000100000002 /* Frameworks (Extension) */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				110000010001000100000012 /* Tun2SocksKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		660000010001000100000003 /* Frameworks (Tests) */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		000000020002000200000001 /* Main Group */ = {
			isa = PBXGroup;
			children = (
				000000020002000200000002 /* Shared */,
				000000020002000200000003 /* Tunnexa App */,
				000000020002000200000004 /* TunnexaPacketTunnel Extension */,
				000000020002000200000005 /* TunnexaTests */,
				000000020002000200000006 /* Products */,
			);
			sourceTree = "<group>";
		};
		000000020002000200000002 /* Shared */ = {
			isa = PBXGroup;
			children = (
				110000020002000200000001 /* SharedModels.swift */,
				110000020002000200000002 /* SharedLogging.swift */,
				110000020002000200000004 /* KeychainHelper.swift */,
				110000020002000200000019 /* VPNEnvironmentDetector.swift */,
				11000002000200020000001A /* VPNErrorDetails.swift */,
			);
			name = Shared;
			path = Shared;
			sourceTree = "<group>";
		};
		000000020002000200000003 /* Tunnexa App */ = {
			isa = PBXGroup;
			children = (
				11000002000200020000001F /* App */,
				11000002000200020000002F /* Views */,
				11000002000200020000003F /* ViewModels */,
				11000002000200020000005F /* YAML */,
				11000002000200020000006F /* VPN */,
				11000002000200020000000F /* Tunnexa.entitlements */,
				110000020002000200000011 /* Info.plist */,
			);
			name = Tunnexa;
			path = Tunnexa;
			sourceTree = "<group>";
		};
		11000002000200020000001F /* App */ = {
			isa = PBXGroup;
			children = (
				11000002000200020000000E /* TunnexaApp.swift */,
			);
			name = App;
			path = App;
			sourceTree = "<group>";
		};
		11000002000200020000002F /* Views */ = {
			isa = PBXGroup;
			children = (
				11000002000200020000000A /* MainView.swift */,
				11000002000200020000000B /* ProxiesView.swift */,
				11000002000200020000000C /* DiagnosticsView.swift */,
				11000002000200020000000D /* SettingsView.swift */,
				110000020002000200000017 /* AddProxySheet.swift */,
				110000020002000200000018 /* ImportConfigSheet.swift */,
			);
			name = Views;
			path = Views;
			sourceTree = "<group>";
		};
		11000002000200020000003F /* ViewModels */ = {
			isa = PBXGroup;
			children = (
				110000020002000200000008 /* ProxyViewModel.swift */,
				110000020002000200000009 /* VPNViewModel.swift */,
			);
			name = ViewModels;
			path = ViewModels;
			sourceTree = "<group>";
		};
		11000002000200020000005F /* YAML */ = {
			isa = PBXGroup;
			children = (
				110000020002000200000003 /* YAMLParser.swift */,
			);
			name = YAML;
			path = YAML;
			sourceTree = "<group>";
		};
		11000002000200020000006F /* VPN */ = {
			isa = PBXGroup;
			children = (
				110000020002000200000007 /* VPNManager.swift */,
				110000020002000200000015 /* ProxyHealthTester.swift */,
			);
			name = VPN;
			path = VPN;
			sourceTree = "<group>";
		};
		000000020002000200000004 /* TunnexaPacketTunnel Extension */ = {
			isa = PBXGroup;
			children = (
				110000020002000200000006 /* PacketTunnelProvider.swift */,
				110000020002000200000005 /* LocalProxyServer.swift */,
				110000020002000200000010 /* TunnexaPacketTunnel.entitlements */,
				110000020002000200000012 /* Info.plist */,
			);
			name = TunnexaPacketTunnel;
			path = TunnexaPacketTunnel;
			sourceTree = "<group>";
		};
		000000020002000200000005 /* TunnexaTests */ = {
			isa = PBXGroup;
			children = (
				440000020002000200000001 /* YAMLParserTests.swift */,
				440000020002000200000002 /* RoutingTests.swift */,
				440000020002000200000004 /* VPNManagerTests.swift */,
			);
			name = TunnexaTests;
			path = TunnexaTests;
			sourceTree = "<group>";
		};
		000000020002000200000006 /* Products */ = {
			isa = PBXGroup;
			children = (
				220000020002000200000002 /* Tunnexa.app */,
				220000020002000200000001 /* TunnexaPacketTunnel.appex */,
				440000020002000200000003 /* TunnexaTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		220000010001000100000001 /* TunnexaPacketTunnel Target */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 770000010001000100000002 /* Build configuration list for PBXNativeTarget "TunnexaPacketTunnel" */;
			buildPhases = (
				880000010001000100000004 /* Sources (Extension) */,
				660000010001000100000002 /* Frameworks (Extension) */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TunnexaPacketTunnel;
			productName = TunnexaPacketTunnel;
			productReference = 22000002000200020001 /* TunnexaPacketTunnel.appex */;
			productType = "com.apple.product-type.app-extension";
		};
		220000010001000100000002 /* Tunnexa Target */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 770000010001000100000001 /* Build configuration list for PBXNativeTarget "Tunnexa" */;
			buildPhases = (
				880000010001000100000001 /* Sources (App) */,
				660000010001000100000001 /* Frameworks (App) */,
				880000010001000100000002 /* Embed App Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				220000030003000300000001 /* PBXTargetDependency (App to Extension) */,
			);
			name = Tunnexa;
			productName = Tunnexa;
			productReference = 22000002000200020002 /* Tunnexa.app */;
			productType = "com.apple.product-type.application";
		};
		220000010001000100000003 /* TunnexaTests Target */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 770000010001000100000003 /* Build configuration list for PBXNativeTarget "TunnexaTests" */;
			buildPhases = (
				880000010001000100000005 /* Sources (Tests) */,
				660000010001000100000003 /* Frameworks (Tests) */,
			);
			buildRules = (
			);
			dependencies = (
				220000030003000300000002 /* PBXTargetDependency (App to Test) */,
			);
			name = TunnexaTests;
			productName = TunnexaTests;
			productReference = 44000002000200020003 /* TunnexaTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		000000010001000100000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					220000010001000100000001 = {
						CreatedOnToolsVersion = 15.0;
					};
					220000010001000100000002 = {
						CreatedOnToolsVersion = 15.0;
					};
					220000010001000100000003 = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = 770000010001000100000003 /* Build configuration list for PBXProject "Tunnexa" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 000000020002000200000001 /* Main Group */;
			packageReferences = (
				330000010001000100000001 /* RemoteSwiftPackageReference "Tun2SocksKit" */,
			);
			productRefGroup = 000000020002000200000006 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				220000010001000100000002 /* Tunnexa Target */,
				220000010001000100000001 /* TunnexaPacketTunnel Target */,
				220000010001000100000003 /* TunnexaTests Target */,
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		880000010001000100000001 /* Sources (App) */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				110000010001000100000001 /* SharedModels.swift in Sources (App) */,
				110000010001000100000003 /* SharedLogging.swift in Sources (App) */,
				110000010001000100000006 /* KeychainHelper.swift in Sources (App) */,
				110000010001000100000005 /* YAMLParser.swift in Sources */,
				110000010001000100000009 /* VPNManager.swift in Sources */,
				110000010001000100000015 /* ProxyHealthTester.swift in Sources */,
				11000001000100010000000A /* ProxyViewModel.swift in Sources */,
				11000001000100010000000B /* VPNViewModel.swift in Sources */,
				11000001000100010000000C /* MainView.swift in Sources */,
				11000001000100010000000D /* ProxiesView.swift in Sources */,
				11000001000100010000000E /* DiagnosticsView.swift in Sources */,
				11000001000100010000000F /* SettingsView.swift in Sources */,
				110000010001000100000017 /* AddProxySheet.swift in Sources */,
				110000010001000100000018 /* ImportConfigSheet.swift in Sources */,
				110000010001000100000019 /* VPNEnvironmentDetector.swift in Sources (App) */,
				11000001000100010000001B /* VPNErrorDetails.swift in Sources (App) */,
				110000010001000100000010 /* TunnexaApp.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		880000010001000100000004 /* Sources (Extension) */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				110000010001000100000002 /* SharedModels.swift in Sources (Extension) */,
				110000010001000100000004 /* SharedLogging.swift in Sources (Extension) */,
				110000010001000100000016 /* KeychainHelper.swift in Sources (Extension) */,
				11000001000100010000001A /* VPNEnvironmentDetector.swift in Sources (Extension) */,
				11000001000100010000001C /* VPNErrorDetails.swift in Sources (Extension) */,
				110000010001000100000007 /* LocalProxyServer.swift in Sources */,
				110000010001000100000008 /* PacketTunnelProvider.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		880000010001000100000005 /* Sources (Tests) */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				110000010001000100000013 /* YAMLParserTests.swift in Sources */,
				110000010001000100000014 /* RoutingTests.swift in Sources */,
				11000001000100010000001D /* VPNManagerTests.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXCopyFilesBuildPhase section */
		880000010001000100000002 /* Embed App Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13; // PlugIns subdirectory
			files = (
				110000010001000100000011 /* TunnexaPacketTunnel.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXTargetDependency section */
		220000030003000300000001 /* PBXTargetDependency (App to Extension) */ = {
			isa = PBXTargetDependency;
			target = 220000010001000100000001 /* TunnexaPacketTunnel Target */;
			targetProxy = 550000010001000100000001 /* PBXContainerItemProxy (App to Extension Dependency) */;
		};
		220000030003000300000002 /* PBXTargetDependency (App to Test) */ = {
			isa = PBXTargetDependency;
			target = 220000010001000100000002 /* Tunnexa Target */;
			targetProxy = 550000010001000100000002 /* PBXContainerItemProxy (App to Test Dependency) */;
		};
/* End PBXTargetDependency section */

/* Begin XCRemoteSwiftPackageReference section */
		330000010001000100000001 /* RemoteSwiftPackageReference "Tun2SocksKit" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/EbrahimTahernejad/Tun2SocksKit.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 5.15.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		330000020002000200000002 /* Tun2SocksKit */ = {
			isa = XCSwiftPackageProductDependency;
			package = 330000010001000100000001 /* RemoteSwiftPackageReference "Tun2SocksKit" */;
			productName = Tun2SocksKit;
		};
/* End XCSwiftPackageProductDependency section */

/* Begin XCBuildConfiguration section */
		770000020002000200000001 /* Debug Configuration (App) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CODE_SIGN_ENTITLEMENTS = Tunnexa/Tunnexa.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Tunnexa/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		770000020002000200000002 /* Release Configuration (App) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CODE_SIGN_ENTITLEMENTS = Tunnexa/Tunnexa.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Tunnexa/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
		770000020002000200000003 /* Debug Configuration (Extension) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CODE_SIGN_ENTITLEMENTS = TunnexaPacketTunnel/TunnexaPacketTunnel.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TunnexaPacketTunnel/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa.PacketTunnel;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		770000020002000200000004 /* Release Configuration (Extension) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CODE_SIGN_ENTITLEMENTS = TunnexaPacketTunnel/TunnexaPacketTunnel.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TunnexaPacketTunnel/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa.PacketTunnel;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
		770000020002000200000005 /* Debug Configuration (Project) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CLANG_WARN_BLOCK_PCT_TO_POINTER_CAST = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
			};
			name = Debug;
		};
		770000020002000200000006 /* Release Configuration (Project) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CLANG_WARN_BLOCK_PCT_TO_POINTER_CAST = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = iphoneos;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		770000020002000200000007 /* Debug Configuration (Tests) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa.TunnexaTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tunnexa.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tunnexa";
			};
			name = Debug;
		};
		770000020002000200000008 /* Release Configuration (Tests) */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.rakib.tunnexa.TunnexaTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tunnexa.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tunnexa";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		770000010001000100000001 /* Build configuration list for PBXNativeTarget "Tunnexa" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				770000020002000200000001 /* Debug */,
				770000020002000200000002 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		770000010001000100000002 /* Build configuration list for PBXNativeTarget "TunnexaPacketTunnel" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				770000020002000200000003 /* Debug */,
				770000020002000200000004 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		770000010001000100000003 /* Build configuration list for PBXProject "Tunnexa" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				770000020002000200000005 /* Debug */,
				770000020002000200000006 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		770000010001000100000004 /* Build configuration list for PBXNativeTarget "TunnexaTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				77000002000200020007 /* Debug */,
				77000002000200020008 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 000000010001000100000001 /* Project object */;
}
"""
    with open(os.path.join(xcodeproj_dir, "project.pbxproj"), "w", encoding="utf-8") as f:
        f.write(pbxproj_content)

    print("Created Tunnexa.xcodeproj structures successfully.")

    # 3. Create Plists and Entitlements
    write_plists()

def write_plists():
    # Make target directories
    os.makedirs("Tunnexa", exist_ok=True)
    os.makedirs("TunnexaPacketTunnel", exist_ok=True)

    app_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Tunnexa</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
	</dict>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>YAML Configuration</string>
			<key>LSHandlerRank</key>
			<string>Owner</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.yaml</string>
				<string>public.yml</string>
			</array>
		</dict>
	</array>
	<key>UTImportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.text</string>
				<string>public.data</string>
			</array>
			<key>UTTypeDescription</key>
			<string>YAML Configuration File</string>
			<key>UTTypeIdentifier</key>
			<string>public.yaml</string>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>yaml</string>
					<string>yml</string>
				</array>
			</dict>
		</dict>
	</array>
</dict>
</plist>
"""
    with open("Tunnexa/Info.plist", "w", encoding="utf-8") as f:
        f.write(app_plist)

    ext_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>TunnexaPacketTunnel</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.networkextension.packet-tunnel</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
	</dict>
</dict>
</plist>
"""
    with open("TunnexaPacketTunnel/Info.plist", "w", encoding="utf-8") as f:
        f.write(ext_plist)

    app_entitlements = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.rakib.tunnexa</string>
	</array>
	<key>com.apple.developer.networking.networkextension</key>
	<array>
		<string>packet-tunnel-provider</string>
	</array>
</dict>
</plist>
"""
    with open("Tunnexa/Tunnexa.entitlements", "w", encoding="utf-8") as f:
        f.write(app_entitlements)

    ext_entitlements = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.rakib.tunnexa</string>
	</array>
	<key>com.apple.developer.networking.networkextension</key>
	<array>
		<string>packet-tunnel-provider</string>
	</array>
</dict>
</plist>
"""
    with open("TunnexaPacketTunnel/TunnexaPacketTunnel.entitlements", "w", encoding="utf-8") as f:
        f.write(ext_entitlements)

    print("Created entitlements and Plist configurations.")

if __name__ == "__main__":
    create_project()
