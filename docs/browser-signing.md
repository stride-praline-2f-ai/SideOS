# Signing the independent browser

The independent browser needs a real installed app identity and a signature with
**no debug permission, no app group and only its own keychain group**. The
browser intentionally blocks sessions if a signer adds broader permissions.

For isolation from malicious hosted software that could steal SideInstaller's
signing authority, use a **different Apple ID/team**, kept on a trusted external
computer. Never store its private key, password or Apple ID credentials in SideOS.
Using another certificate on the same compromised team is insufficient.

## Why ordinary signing may be rejected

iLoader's inspected main revision `96ed0612` uses isideload 0.5.2. That library's
signing code begins with the provisioning profile's entitlements, and its
sideloader registers an app group. Consequently a default iLoader install may
retain `get-task-allow` or an app group even though our IPA requests neither.
Do not disable the browser's gate to accommodate that signature.

Use a signer that can **replace** the entitlement dictionary, such as zsign's
`-e` option. Have the independent browser's valid profile and P12 on the trusted
computer. The profile must cover this device and browser bundle ID. A free
development profile still expires and must be renewed externally; keeping those
credentials in SideInstaller would undo the update-authority separation.

`tools/browser-signing-entitlements.py` reads only public profile metadata and
writes minimal signing requests. It never reads a signing private key. Example:

```powershell
py tools\browser-signing-entitlements.py --profile C:\Private\Browser.mobileprovision --openssl "C:\Program Files\Git\usr\bin\openssl.exe" --output C:\Private\Browser.entitlements
```

It prints the bundle ID to use. With your locally built/trusted zsign executable,
replace the example paths and use that bundle ID when the profile has a team
suffix:

```text
zsign -f -k BrowserIdentity.p12 -m Browser.mobileprovision -e Browser.entitlements -b <printed-browser-bundle-id> -o SideOSBrowser-signed.ipa SideOSBrowser-unsigned.ipa
```

An encrypted P12 also needs zsign's local password option. Do not put private
keys or passwords in chat, GitHub or committed scripts. A local password prompt
avoids placing a literal password in shell history; CLI arguments/memory still
require a trusted computer. This repository supplies no certificates or profiles.

Install the resulting already-signed IPA **without re-signing it**. For example,
on a trusted computer with Python/pymobiledevice3 and the Apple USB drivers:

```text
python -m pymobiledevice3 apps install SideOSBrowser-signed.ipa
```

Do not send that IPA back through a signer that restores debug/sharing flags.
If you temporarily installed a debug-enabled version to obtain a profile, do not
enter real accounts into it. Remove that empty test install and start clean with
the hardened signature, then reboot before the adversarial baseline test.

CMS integrity decoding in the helper is not verification of an Apple trust chain;
iOS validates the actual profile and signature during installation. Confirm the
browser's live signature check passes, verify the shown app identity/team against
your external signer, and run [the canary procedure](browser-isolation-review.md)
before relying on the new boundary. Physical-device and signer-specific behavior
have not been verified by the CI compiler/package checks.

References: [iLoader signing call](https://github.com/nab138/iloader/blob/96ed06124d7a859692a5ec2864e1b47998d4904c/src-tauri/src/sideload.rs),
[isideload 0.5.2 source](https://crates.io/crates/isideload/0.5.2),
[zsign replacement-entitlements option](https://github.com/zhlynn/zsign#usage).
