#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_binary="$(mktemp -t tahoe-core.XXXXXX)"
trap 'rm -f "$test_binary"' EXIT
swiftc "$task_root/browser-app/Shared/IsolationPolicy.swift" "$task_root/browser-app/Tests/PolicyTests.swift" -o "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/installer/HomeData.swift" \
  "$task_root/embedded/tahoe/InstallerOperationState.swift" \
  "$task_root/embedded/tahoe/WindowState.swift" \
  "$task_root/embedded/installer/HomeDataTests.swift" -o "$test_binary"
chmod +x "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/refresh/RefreshSourcePolicy.swift" \
  "$task_root/embedded/refresh/RefreshSourcePolicyTests.swift" -o "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/tahoe/WindowState.swift" \
  "$task_root/embedded/tahoe/Address.swift" \
  "$task_root/embedded/tahoe/Persistence.swift" \
  "$task_root/embedded/tahoe/ChatWorkspaceState.swift" \
  "$task_root/embedded/tahoe/FileOperations.swift" \
  "$task_root/embedded/tahoe/Interaction.swift" \
  "$task_root/embedded/tahoe/WindowStateTests.swift" -o "$test_binary"
chmod +x "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/WindowState.swift" \
  "$task_root/embedded/tahoe/Address.swift" \
  "$task_root/embedded/tahoe/Persistence.swift" \
  "$task_root/embedded/tahoe/ChatWorkspaceState.swift" \
  "$task_root/embedded/tahoe/FileOperations.swift" \
  "$task_root/embedded/tahoe/FileWorker.swift" \
  "$task_root/embedded/tahoe/FileClipboard.swift" \
  "$task_root/embedded/tahoe/Interaction.swift" \
  "$task_root/embedded/tahoe/PageRestorationState.swift" \
  "$task_root/embedded/tahoe/ApplicationIdentity.swift" \
  "$task_root/embedded/tahoe/ProjectSafetyTests.swift" -o "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/WindowState.swift" \
  "$task_root/embedded/tahoe/DesktopInteractionState.swift" \
  "$task_root/embedded/tahoe/DesktopInteractionTests.swift" -o "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/tahoe/WebsiteIdentity.swift" \
  "$task_root/embedded/tahoe/WebsiteIdentityTests.swift" -o "$test_binary"
chmod +x "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/PageRestorationState.swift" \
  "$task_root/embedded/tahoe/PageRestoration.swift" \
  "$task_root/embedded/tahoe/PageRestorationTests.swift" -o "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/MotionPolicy.swift" \
  "$task_root/embedded/tahoe/MotionTests.swift" -o "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/tahoe/IconCropGeometry.swift" \
  "$task_root/embedded/tahoe/IconCropTests.swift" -o "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/tahoe/WindowState.swift" "$task_root/embedded/tahoe/OverviewLayout.swift" \
  "$task_root/embedded/tahoe/OverviewTests.swift" -o "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/WindowState.swift" "$task_root/embedded/tahoe/Persistence.swift" "$task_root/embedded/tahoe/ChatWorkspaceState.swift" "$task_root/embedded/tahoe/ChatWorkspaceTests.swift" -o "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/WindowState.swift" \
  "$task_root/embedded/tahoe/ViewportPolicy.swift" \
  "$task_root/embedded/tahoe/HostPickerHandoff.swift" \
  "$task_root/embedded/tahoe/HostPickerDirectory.swift" \
  "$task_root/embedded/tahoe/DuoFeatureTests.swift" -o "$test_binary"
"$test_binary"

swiftc "$task_root/embedded/tahoe/GuestLaunchState.swift" "$task_root/embedded/tahoe/GuestLaunchTests.swift" -o "$test_binary"
"$test_binary"
swiftc "$task_root/embedded/tahoe/WindowState.swift" "$task_root/embedded/tahoe/DisplayProtocol.swift" "$task_root/embedded/tahoe/DisplayProtocolTests.swift" -o "$test_binary"
"$test_binary"
