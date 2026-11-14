# Contributing

Read AGENTS.md, SECURITY.md and LICENSING.md. Send a focused change with its reason
and validation. Preserve existing user data, signing identity, source guards and
exact cache fingerprints. Do not start a Mac IPA build for every editing commit.

Run the core checks with Swift 6.2+, the Python checks listed in
`.github/workflows/checks.yml`, and the browser fixtures when the adapter changes.
Native hosted-app UI requires a device test; compilation is not runtime proof.
Never commit credentials, pairing files, signing material, personal screenshots
or unlicensed artwork. Do not remove a third-party licence or claim authority to
relicense upstream work. Public release blockers remain binding until resolved.
