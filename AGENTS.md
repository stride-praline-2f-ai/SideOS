# SideOS3 build discipline

- Develop and consolidate changes on main or a feature branch. Run the relevant local checks before pushing.
- Ordinary pushes and pull requests use the cheap Linux checks. Do not start a Mac IPA build for every editing commit.
- Request an IPA only when an installable build is needed: use workflow_dispatch or advance the fixed ipa/device branch or create an ipa-* tag after the changes are ready.
- Reuse the fixed ipa/device branch for automatic build requests so GitHub can reuse that branch's caches. Do not repeatedly advance it while editing. Finish the code and checks first, then request one build.
- Before starting or retrying a build, inspect Actions. Reuse a matching successful artifact or follow the matching running build. Do not cancel a useful active build for documentation or workflow-only edits.
- Keep simulator and preview jobs out of the device IPA workflow. Its Rust FFI build must use --device-only.
- Preserve component-cache input and toolchain fingerprints. Never reuse a compiled binary from a partial-prefix cache match.
- Duo release IPAs must link against the iOS 27.1+ SDK. Use the xcode-27 runner and verify actual Mach-O SDK load commands in the app, desktop, LiveProcess and installer. Never fake SDK metadata or fall back to SDK 26 for a Duo release.
- Do not put GitHub tokens into the app to implement asset updates. The current ChatGPT adapter is embedded Swift; changing it still needs a host rebuild until an explicit resource-update loader is implemented.
