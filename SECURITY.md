# Security and privacy

SideOS is a sideloaded desktop host, not a hardened operating system. Hosted apps
and the embedded browser must not be treated as mutually isolated against a
malicious guest. WebKit profile stores do not create a separate app sandbox.
For sensitive logins, use the system browser or a separately signed trusted app.
Run only hosted IPAs you trust. No 100% security claim or security certification
is made by this release.

This boundary also covers SideInstaller's signing credentials and pairing
records, the host's granted permissions and other hosted apps. Keychain storage,
private folders and scoped signing groups do not establish isolation from
malicious hosted code. Do not treat the combined app as a secure signing vault.
The packaged `scopedSigningEntitlementsPreserved` check verifies packaging only;
`maliciousGuestIsolationVerified` remains false.

Passwords, Apple signing material, provisioning and pairing data belong to each
user. They must not be committed, added to bug reports or shipped in releases.
Repository builds do not require the developer's certificate or Apple password.
Unsigned artifacts still need each recipient's own signing/setup.

Browsers, websites, Apple services and configured JIT/signing providers make their
own network requests. Optional remote search suggestions send typed queries to
the configured provider; disable them if undesired. Report diagnostics only after
reviewing and redacting personal data. Private browser tabs are not restored.

Report vulnerabilities through GitHub private vulnerability reporting if enabled.
If unavailable, do not post exploit details, secrets or other users' data in a
public issue; use an available private maintainer channel. Public issues are for
redacted reproducible functional bugs. No secret-handling support is offered via
this document, and no email/contact address is invented.

Release scanning catches known credential patterns and sensitive files; it does
not prove the absence of all secrets or runtime vulnerabilities. Historical
commits, dependencies and device behaviour require separate review.

The README, first-use in-app notice and persistent browser banner explicitly warn
that hosted apps may access browser data. The banner links to the in-app safety
guide. Acknowledging a warning does not create a sandbox or make Private mode safe
against a malicious hosted app.
