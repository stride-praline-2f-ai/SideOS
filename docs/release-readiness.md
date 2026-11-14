# Release readiness

Status: **experimental pre-release**. The repository is public. Releases contain
one unsigned SideOS IPA, exact-source provenance, verification reports and
checksums. In-app and public release credits remain prominent. Physical device
acceptance and security review are ongoing.

The replacement build adds bounded IPA extraction, updated cryptographic/network
dependencies, independent signature/tamper tests, a current RustSec gate and an
actual-IPA privacy scan. Packaging checks are scoped by name; they do not certify
malicious-guest isolation. Sensitive signing/pairing operations share the host's
trust limitation, so public builds require trusted hosted apps.

## Remaining work before a stable release

1. Retain all component licences, visible author attribution and corresponding
   source. Review the applicable component terms before downstream redistribution.
2. Confirm publication rights for the user-supplied icon/wallpaper and review
   historical Apple image assets already present in older public commits. Do not
   rewrite public history without an agreed migration plan.
3. Complete on-device acceptance on the intended devices: signing/install/update,
   recovery and expiry, LiveContainer window/delegate setup, JIT, both resize
   corners, hover reveal, fullscreen touch actions, Files/iCloud IPA import,
   rotation/folding, keyboard, accessibility and background/foreground behaviour.
4. Complete a security review of the exact source and dependency revisions.
   Automated credential checks are useful but cannot certify isolation or safety.

## Prepared for users

Installation/update guide, standalone user guide, troubleshooting, security and
privacy notes, attribution/licences, changelog and redacted bug-report template
are included. Help → Getting Started explains the same core actions in the app.
The source/SDK/package guards and exact component-cache policy remain enforced.
Only an unsigned SideOS IPA is built; recipients provide their own signing material.

## Experimental release procedure

Use one consolidated commit, run checks, request the device workflow once, and
inspect the source-matching artifact. Verify its manifest, binary SDK records,
icon and source/refresh guards. Publish an honest compatibility/known-issues list,
install instructions and SHA-256 checksums, plus the exact corresponding source.
Use a stable release tag and attach the single unsigned IPA and source archive.
Publish an existing verified artifact through the release-only Linux workflow;
do not rebuild an unchanged IPA just to attach it to Releases. Mark the release
experimental/pre-release while physical acceptance remains incomplete. Do not
include test-user data or describe automated checks as device certification.
