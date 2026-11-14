#!/bin/bash
set -euo pipefail
engine_root="$(cd "$1" && pwd)"
task_root="$(cd "$(dirname "$0")/.." && pwd)"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${RUNNER_TEMP:-/tmp}/sideos-security-fixtures-target}"
cargo test --locked --manifest-path "$engine_root/rust-core/Cargo.toml" -p apple-codesign-quick --lib
PROPTEST_CASES=16 PROPTEST_MAX_SHRINK_ITERS=0 cargo test --locked --manifest-path "$task_root/embedded/installer/security/vendor/srp/Cargo.toml"
cargo test --locked --manifest-path "$task_root/tools/archive-fixture/Cargo.toml"
echo 'Independent CMS verification and tamper refusal, signer attributes, SRP and hostile IPA extraction fixtures passed.'
