# Installer security integration

Upstream SideInstaller remains credited to FrizzleM. Its original license and
all component notices are retained. `hardening.patch` applies after the pinned
2.0.1 integration patch; `Cargo.lock` records the exact reviewed dependency set.

The integration updates archive, TLS, trust-store and cryptographic dependencies,
including RSA/CMS/X.509 API migration. Pairing certificates keep the existing
local certificate profile. The SRP compatibility change compares proof byte
slices with the existing constant-time equality implementation; the original
MIT/Apache notices and protocol tests are retained in `vendor/srp`.

IPA extraction uses a private, unique staging directory. It validates all member
paths, duplicates, declared sizes, types and confined link targets before writing.
Links are created last; file writes do not follow them and no privileged Unix
permission bits are restored. Expanded bytes and entry counts are bounded. Failed
imports/signing discard staging; successful native installs use the existing
temporary-directory cleanup path.

Linux fixtures independently verify a generated CMS signature using OpenSSL,
reject changed content, retain the original signer/CodeDirectory tests, exercise
SRP authentication vectors and reject hostile IPA paths/links/sizes. Device
builds still regenerate FFI headers and compile the actual iOS library. Offline
minimum-version policy and a current RustSec check run before an IPA build.

These changes do not isolate malicious hosted apps from browser data, signing
credentials, pairing records or host-granted permissions. Use trusted IPAs only.
Do not publish private correspondence or account/signing/pairing data in this
directory. Public attribution and original license text must remain intact.
