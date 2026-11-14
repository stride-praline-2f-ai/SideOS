**Built with [SideInstaller by FrizzleM](https://github.com/FrizzleM/SideInstaller), [LiveContainer by its contributors](https://github.com/LiveContainer/LiveContainer), and [StikJIT by the StikDebug contributors](https://github.com/StikDebug/StikJIT).**

Original authors retain their copyrights. SideOS provides the desktop and integration changes. See [full credits](https://github.com/{{REPOSITORY}}/blob/{{SOURCE_SHA}}/CREDITS.md) and the [retained component licenses](https://github.com/{{REPOSITORY}}/blob/{{SOURCE_SHA}}/LICENSING.md).

### SideOS · Build {{BUILD}}

This experimental pre-release contains one **unsigned SideOS IPA**. Sign it using your own trusted tool and credentials.

- Prominent linked author credits in SideOS About/Help, the SideInstaller Home header and its window title bar.
- Hardened IPA extraction: private staging, bounded sizes, confined links and no privileged permission restoration.
- Updated signing/network dependencies with current advisory checks and independent CMS signature/tamper tests.
- A six-step built-in JIT tutorial with real setup status, shortcuts and error-specific recovery instructions.
- Actual IPA scans cover embedded source notices and framework resources before publication.
- Unauthenticated pairing timeouts release their connection slot while keeping display hosting available.
- Wireless extended display capped at **60 fps**, with matching encoder timing and bounded frame queues. Display-only: no remote controller mode.
- OLED Black appearance, native Liquid Glass Dock options, rounded hosted-window title bars and content-tap window activation.
- Built-in JIT setup guide, host-owned IPA picker, SideInstaller Home dashboard and source-protected refresh.

### Install and update

Download `SideOS-Build-{{BUILD}}-unsigned.ipa` below, verify its checksum and sign it with your usual supported signer. Preserve its extensions and your existing app identity when updating. Read the [installation guide](https://github.com/{{REPOSITORY}}/blob/{{SOURCE_SHA}}/docs/install.md) and [troubleshooting](https://github.com/{{REPOSITORY}}/blob/{{SOURCE_SHA}}/docs/troubleshooting.md).

For Wi-Fi extended display, install the build on both devices and open **Settings → Wireless Display**. The host determines the frame-rate cap. See the [wireless display guide](https://github.com/{{REPOSITORY}}/blob/{{SOURCE_SHA}}/docs/wireless-display.md).

> [!WARNING]
> **Do not store sensitive information in the embedded browser.** It is not sandboxed away from malicious hosted LiveContainer apps, which may access browser cookies, signed-in sessions or saved data. Use a trusted, separately sandboxed browser for sensitive activity. [Security guidance](https://github.com/{{REPOSITORY}}/blob/{{SOURCE_SHA}}/SECURITY.md).
> **Use trusted hosted IPAs only.** Signing credentials, pairing records and host-granted permissions share this trust limitation. The embedded installer is not a secure vault isolated from malicious guests.

### Validation and known limits

The device workflow runs core/browser/layout checks, native hardware-codec and encrypted-pairing tests, iOS compilation and package/source guards. The four owned device components link against the actual iOS 27.2 SDK. These checks do not constitute physical device certification or runtime sandbox isolation.

Wireless hosted-scene capture and iPhone SideInstaller startup still require on-device acceptance. Protected/uncapturable content may be blank. The 60 fps value is a cap; sustained delivery depends on the host, receiver and network.

### Exact build

Source: [`{{SOURCE_SHA}}`](https://github.com/{{REPOSITORY}}/commit/{{SOURCE_SHA}}). The release tag and GitHub's source archives point to this revision. `release.json`, `verification.json` and `SHA256SUMS.txt` are attached alongside the IPA.

IPA SHA-256:

```text
{{IPA_SHA256}}
```
