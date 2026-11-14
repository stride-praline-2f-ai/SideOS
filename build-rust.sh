#!/bin/bash
# The device IPA only needs --device-only. Keep --all-platforms (the default)
# for local developers who explicitly need the simulator XCFramework slice.
set -euo pipefail

build_mode="${1:---all-platforms}"
case "$build_mode" in
  --device-only|--all-platforms) ;;
  *) echo 'Usage: build-rust.sh [--device-only|--all-platforms]' >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo 'Usage: build-rust.sh [--device-only|--all-platforms]' >&2
  exit 2
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.4}"
if ! command -v cargo >/dev/null 2>&1 && [[ -r "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo 'Cargo is not on PATH. Install Rust or load its shell environment before building.' >&2
  exit 1
fi

export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=${HOME}=/build"
export CFLAGS="${CFLAGS:-} -ffile-prefix-map=${HOME}=/build"
export TARGET_CFLAGS="${TARGET_CFLAGS:-} -ffile-prefix-map=${HOME}=/build"

task_root="$(cd "$(dirname "$0")" && pwd)"
cd "$task_root/rust-core"
cargo build --locked --release --target aarch64-apple-ios

framework_arguments=(-library "$task_root/rust-core/target/aarch64-apple-ios/release/libsideinstaller_ffi.a" -headers "$task_root/rust-core/include")
if [[ "$build_mode" == --all-platforms ]]; then
  cargo build --locked --release --target aarch64-apple-ios-sim
  framework_arguments+=(-library "$task_root/rust-core/target/aarch64-apple-ios-sim/release/libsideinstaller_ffi.a" -headers "$task_root/rust-core/include")
fi
cd "$task_root"
rm -rf "$task_root/SideInstallerFFI.xcframework"
xcodebuild -create-xcframework "${framework_arguments[@]}" -output "$task_root/SideInstallerFFI.xcframework"
echo 'SideInstallerFFI.xcframework is ready.'
