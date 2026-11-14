#!/bin/bash
# Compile, launch and exercise the actual SwiftUI desktop on an installed iPad.
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
mkdir -p native-results

if [[ -z "${TAHOE_SIMULATOR:-}" ]]; then
TAHOE_SIMULATOR="$(python3 - <<'PY'
import json, re, subprocess
sdk = tuple(map(int, subprocess.check_output(
    ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True
).strip().split('.')[:2]))
devices = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True
))['devices']
candidates = []
for runtime, items in devices.items():
    match = re.search(r'iOS-(\d+)-(\d+)', runtime)
    if not match:
        continue
    version = tuple(map(int, match.groups()))
    if not (26, 0) <= version <= sdk:
        continue
    for device in items:
        if 'iPad' in device['name'] and device.get('isAvailable', True):
            candidates.append((version, device))
if not candidates:
    raise SystemExit('No available iPad Simulator with iOS 26 and the selected SDK')
candidates.sort(key=lambda item: (item[0], '13' in item[1]['name'], 'Pro' in item[1]['name']), reverse=True)
print(candidates[0][1]['udid'])
PY
)"
fi
export TAHOE_SIMULATOR
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "TAHOE_SIMULATOR=$TAHOE_SIMULATOR" >> "$GITHUB_ENV"
fi

request_simulator_boot() {
python3 - <<'PYBOOT'
import json, os, subprocess
simulator = os.environ['TAHOE_SIMULATOR']
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))['devices']
selected = next(device for items in devices.values() for device in items if device['udid'] == simulator)
if selected['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', simulator], check=True, timeout=120)
PYBOOT
}

build_app() {
# A fresh hosted iPad may spend several minutes migrating its system data.
# Start that work before compilation rather than at the UI-test deadline.
request_simulator_boot
xcodebuild -project embedded/tahoe/preview/TahoePreview.xcodeproj \
    -scheme TahoePreview -destination "platform=iOS Simulator,id=$TAHOE_SIMULATOR" \
    -derivedDataPath native-derived CODE_SIGNING_ALLOWED=NO \
    build-for-testing 2>&1 | tee native-results/compile.log

}

run_tests() {
request_simulator_boot
python3 - <<'PY'
import os, subprocess
simulator = os.environ['TAHOE_SIMULATOR']
subprocess.run(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], check=True, timeout=600)
PY

xcodebuild -project embedded/tahoe/preview/TahoePreview.xcodeproj \
    -scheme TahoePreview -destination "platform=iOS Simulator,id=$TAHOE_SIMULATOR" \
    -derivedDataPath native-derived -resultBundlePath native-results/desktop.xcresult \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180 \
    -only-testing:TahoePreviewUITests/DesktopUITests/testBrowserTopPocketAndUnderScrollScreenshots \
    -only-testing:TahoePreviewUITests/DesktopUITests/testGlassToolbarCancelsDraggedPressAndActivatesOnce \
    -only-testing:TahoePreviewUITests/DesktopUITests/testBrowserChromeControlsRemainAccessible \
    -only-testing:TahoePreviewUITests/DesktopUITests/testGoogleSearchPanelAppearsBeforeRemoteAutocomplete \
    -only-testing:TahoePreviewUITests/DesktopUITests/testBrowserGoogleSuggestionPanelAndSearchFallback \
    -only-testing:TahoePreviewUITests/DesktopUITests/testBrowserProfilesKeepTabsSeparateAndRestorable \
    -only-testing:TahoePreviewUITests/DesktopUITests/testBrowserTabSwitchPreservesBothLivePages \
    -only-testing:TahoePreviewUITests/DesktopUITests/testFinderSelectionAndRename \
    -only-testing:TahoePreviewUITests/DesktopUITests/testMissionControlSelectsWindowAndAddsDesktop \
    CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | tee native-results/tests.log

}

launch_app() {
# Leave the tested application running, with deterministic local showcase data.
xcrun simctl install "$TAHOE_SIMULATOR" native-derived/Build/Products/Debug-iphonesimulator/TahoePreview.app
python3 - <<'PY'
import os, subprocess, time
from pathlib import Path
simulator = os.environ['TAHOE_SIMULATOR']
bundle = 'com.aault.tahoedesktop.preview'
data = Path(subprocess.check_output(
    ['xcrun', 'simctl', 'get_app_container', simulator, bundle, 'data'], text=True
).strip())
ready = data / 'Library/Caches/tahoe-preview-ready'
for appearance in ('light', 'dark'):
    subprocess.run(['xcrun', 'simctl', 'terminate', simulator, bundle], check=False)
    ready.unlink(missing_ok=True)
    subprocess.run(['xcrun', 'simctl', 'launch', simulator, bundle,
                    '--uitest', '--showcase', '--browser-reference', '--' + appearance], check=True, timeout=120)
    deadline = time.monotonic() + 90
    while not ready.exists():
        if time.monotonic() >= deadline:
            raise SystemExit('Desktop did not finish launching in ' + appearance + ' appearance')
        time.sleep(0.25)
    time.sleep(2)
    subprocess.run(['xcrun', 'simctl', 'io', simulator, 'screenshot',
                    'native-results/desktop-' + appearance + '.png'], check=True, timeout=30)
print('Native desktop compiled, passed interaction tests, and launched in both appearances.')
PY
}

case "${1:-all}" in
    build) build_app ;;
    test) run_tests ;;
    launch) launch_app ;;
    all) build_app; run_tests; launch_app ;;
    *) echo 'Usage: bash tools/test-native.sh [build|test|launch|all]' >&2; exit 2 ;;
esac
