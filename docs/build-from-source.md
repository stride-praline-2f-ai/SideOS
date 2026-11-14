# Build from source

The checked-in GitHub Actions workflow is the reproducible build entry point.
It checks out exact runtime/installer/JIT/dylibify revisions, applies the tracked
adaptations, compiles device-only FFI and packages one unsigned SideOS IPA.

1. Fork/checkout the desired source revision. Read the licence restrictions first.
2. Run **SideOS3 Checks** for inexpensive core, source, browser and workflow checks.
3. For host-only code validation without packaging, run **SideOS Native Source Check**. It compiles the device host and enforces its warning budget without packaging or publishing an IPA.
4. Request **SideOS3 Device IPA** when an installable build is needed. The `xcode-27`
   runner selects an installed iOS SDK >=27.1 and rejects older linked SDKs in all
   four owned device binaries. There are no simulator or preview jobs.
5. Download the single IPA artifact and its manifests. Sign with your own tool.

No project-owner credentials or secrets should be needed. GitHub permissions are
limited to repository read/Actions read for builds. A public fork must have access
to the pinned public dependencies and the required runner. Retain exact recipe,
source and toolchain cache fingerprints; never use a partial cache to skip a
changed binary. Native UI edits require rebuilding the host. File-only update
mechanisms must not insert GitHub tokens into the shipped app.

## Publish an existing verified IPA

The **Publish verified SideOS release** workflow runs on Linux and reuses an
existing successful device artifact. It does not start Xcode or make another IPA.
Prepare `.github/release-request.json` on the fixed `release/publish` branch with
the build number, producer run/artifact IDs, exact source SHA and independently
verified archive/IPA SHA-256 values. Put user-facing notes and prominent upstream
credits in `.github/release-notes.md`, then push that branch. The workflow validates
provenance and hashes, uploads assets to a draft, verifies the uploaded bytes,
and finally publishes an experimental pre-release with its exact source tag.

Only that release job requests repository contents write access; ordinary build
jobs retain read-only access. Keep signing credentials and private data
out of the request, notes, release assets and public source.

The experimental independent browser/probe sources are not built by this workflow.
Their design does not establish isolation for SideOS's embedded browser.
