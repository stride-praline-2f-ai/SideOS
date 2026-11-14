#!/bin/bash
set -euo pipefail

# Full-display iPhone Duo support is selected by the linked SDK, not by the
# deployment target or a plist label. Never fall back to the iOS 26 SDK.
task_xcode_root="${SIDEOS_XCODE_ROOT:-/Applications}"
for task_xcode in "$task_xcode_root"/Xcode_27.2.app "$task_xcode_root"/Xcode_27.1.app "$task_xcode_root"/Xcode.app; do
    if [[ ! -d "$task_xcode/Contents/Developer" ]]; then continue; fi
    if ! task_ios_sdk="$(DEVELOPER_DIR="$task_xcode/Contents/Developer" xcrun --sdk iphoneos --show-sdk-version)"; then continue; fi
    if python3 - "$task_ios_sdk" <<'PYSDK'
import re, sys
match = re.fullmatch(r"(\d+)\.(\d+)(?:\.(\d+))?", sys.argv[1].strip())
sys.exit(0 if match and tuple(int(v or 0) for v in match.groups()) >= (27, 1, 0) else 1)
PYSDK
    then
        export DEVELOPER_DIR="$task_xcode/Contents/Developer"
        xcodebuild -version
        echo "::notice title=Duo native SDK::iOS $task_ios_sdk at $task_xcode"
        if [[ -n "${GITHUB_ENV:-}" ]]; then
            echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"
        fi
        exit 0
    fi
    echo "Skipping $task_xcode: iOS SDK $task_ios_sdk does not provide the full Duo display."
done
echo 'Xcode 27.1+ with the iOS 27.1+ SDK is required for the full Duo display. No older-SDK IPA will be built.' >&2
exit 1
