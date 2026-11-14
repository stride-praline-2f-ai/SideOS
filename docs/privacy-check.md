# Privacy review of source and developer artifact

The current tree was reviewed for credentials, personal account references,
signing/provisioning files, pairing records, private user stores and image metadata.
Gitleaks v8.30.1 (official release checksum verified) reported no credential matches
in the current source tree, all 12 reachable commits in the public repository at
the time of review, or the existing Build 9 IPA. The project-specific release
scanner also passed. These checks cannot prove absence of every possible secret.

## Current-tree cleanup

- Removed account-specific job/billing exports and nonessential old development
  account references. Historical audit reports keep technical findings with
  sanitized relative source references rather than misleading replacement links.
- Updated runtime/repository fallback provenance to the current project and
  pinned runtime revision supplied at build time.
- Removed nonessential EXIF/XMP metadata from the supplied wallpaper and official
  LiveContainer icon assets. Decoded pixels were verified unchanged; no GPS tags
  were found. The custom host icon was already metadata-free.
- No private signing/provisioning or pairing files were found in the current tree
  or Build 9 bundle. No user account database/cookie-store candidates were found
  in that bundle. Runtime source files implementing those features are not user data.
- Existing Git bundle identifiers and required upstream licences/attribution are
  retained; changing an app identity can strand users' existing data.

## Historical metadata remains

Public commit history contains a commit-author/committer email address and older
non-secret development-account/usage metadata. Current-tree cleanup does not erase
history or copies already downloaded. No history rewrite was performed. Review
GitHub email privacy/no-reply authorship and plan any agreed history migration
before treating the repository as free of personal metadata. Do not equate
“no credential matches” with “no personal information anywhere in Git history”.

## Runtime boundary

The embedded browser is not isolated from malicious hosted LiveContainer apps.
The README, first-use app notice and persistent browser warning make this clear.
Use a trusted separately sandboxed browser for sensitive details. This review does
not constitute runtime isolation testing, device acceptance or security certification.
