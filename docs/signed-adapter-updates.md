# Optional signed ChatGPT resource updates

Default behavior uses the bundled adapter. Native Swift, entitlements and runtime
changes always need a new IPA. Resource updates replace only the origin-scoped
ChatGPT JavaScript adapter; they do not update the app binary or guest runtime.

An owner can create an Ed25519 key outside the checkout and sign a JavaScript file:

```sh
python3 tools/sign-chat-adapter.py --generate-key --key /secure/sideos-adapter.pem --source adapter.js --version 1 --minimum-host 3.1.0 --output adapter.json
```

Keep the private key off GitHub. Host the JSON at an owner-controlled public HTTPS
URL, then enter that URL and the printed public key in Browser settings. The app
sends no GitHub token or browser cookies. Feed URLs with credentials or query
parameters are rejected. Imported workspace backups cannot change update trust.
The signed payload fixes version, minimum host, origin and script size. Invalid
signatures/old versions are rejected; the previous verified or bundled adapter is
available for rollback. Only install a key whose owner you trust to modify your
ChatGPT page. The adapter must not export conversation or draft text.

The signer tests use OpenSSL; the native workflow also verifies canonical payloads
and tampering with CryptoKit. No production feed/key is configured by this change.
