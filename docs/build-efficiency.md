# Efficient builds and future updates

## Current policy

Ordinary main pushes and pull requests run the Linux Swift, page-adapter and build-script checks. Documentation-only changes do not start checks. Device IPA builds are explicit: select Run workflow in **SideOS3 Device IPA**, advance the fixed `ipa/device` branch, or push an `ipa-*` tag. Legacy `build/**` edit branches no longer trigger an IPA. Reuse `ipa/device` rather than creating a new branch per build: GitHub caches are scoped to the current/default branch. Manual builds from main share default-branch caches. The first build under the new cache layout must populate its component caches.

There is at most one active IPA workflow. An active release build finishes; GitHub retains only the newest pending request. Cheap checks cancel their own superseded runs. Editing CI does not justify restarting a useful native build.

The device build caches four raw products independently: the desktop host app, JIT products, device Rust XCFramework, and embedded installer app. Exact keys include the source inputs, pinned foundation revisions, build workflow and native toolchain. Successful products are saved immediately, even if a later component fails. Prefix fallback is used only for Cargo intermediates, which Cargo revalidates; compiled app and framework caches require exact matches.

The IPA path runs `build-rust.sh --device-only`. Simulator Rust compilation and simulator-target installation are omitted. A compiled FFI cache hit skips Cargo completely, including the large Cargo-target restore. Local development can still use `--all-platforms` (the script's compatible default).

Core tests run once on Linux, with only Apple-specific integration/signing checks on the Mac. Node test dependencies use a lockfile and npm cache. IPA ZIPs are uploaded without redundant compression and retained for 14 days; extra diagnostic artifacts are kept only on failure, for 3 days. Packaging and binary verification always run, including cache hits.

## What needs rebuilding?

| Change | Work required |
| --- | --- |
| ChatGPT sidebar/tab logic or CSS today | The adapter currently lives in a Swift string, so rebuild the host; reuse unchanged JIT, installer and Rust products, then package the IPA. |
| Native Swift/SwiftUI or WebKit bridge API | Rebuild affected native products, package and sign/install the new IPA. |
| Rust/runtime or ABI changes | Rebuild affected FFI/installer products; exact source/toolchain fingerprints prevent stale reuse. |
| Packaging or signing only | Reuse matching compiled products and package/re-sign; native compilation can be skipped. |
| Tests or documentation only | Cheap checks as appropriate; no IPA request. |
| Website content or existing user settings | No new IPA. |

## A future web-only fast path

Separating the ChatGPT JavaScript/CSS from the Swift string would require one native host update. A bundled resource loader would then allow small asset-only IPA repackaging without compiling the native apps. It would still require reinstalling/re-signing that IPA.

Avoiding an IPA entirely would require an explicit versioned asset-update/import feature in the app, with bridge-version compatibility, integrity checks, rollback and a bundled fallback. That delivery mechanism is not implemented here. A private GitHub repository cannot be used as an unauthenticated update CDN, and an app must not contain a GitHub personal access token.
