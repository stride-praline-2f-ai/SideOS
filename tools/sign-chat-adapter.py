#!/usr/bin/env python3
"""Create owner-signed ChatGPT resource updates; never uploads anything.

Requires OpenSSL with Ed25519 support. Keep the private key outside the repo.
Native code changes still need an IPA. Configure the printed public key and an
HTTPS URL serving the resulting JSON in SideOS Browser Settings.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key', type=Path, required=True)
    parser.add_argument('--generate-key', action='store_true')
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--version', type=int, required=True)
    parser.add_argument('--minimum-host', default='3.1.0')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.version < 1 or not re.fullmatch(r'\d+\.\d+\.\d+', args.minimum_host):
        parser.error('A positive version and three-part minimum host version are required.')
    if args.generate_key:
        args.key.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(args.key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as stream:
            subprocess.run(['openssl', 'genpkey', '-algorithm', 'Ed25519'], stdout=stream, check=True)
    script = args.source.read_text()
    if args.source.suffix == '.swift':
        match = re.search(r'static let source = #"""([\s\S]*?)"""#', script)
        if not match:
            parser.error('Swift source does not contain the adapter raw string.')
        script = match[1].strip('\n')
    if not script or len(script.encode()) > 262144:
        parser.error('Adapter source is empty or too large.')
    payload = dict(version=args.version, minimumHost=args.minimum_host, origin='https://chatgpt.com', script=script)
    canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()
    with tempfile.TemporaryDirectory(prefix='sideos-sign-') as temporary:
        data = Path(temporary) / 'payload'; data.write_bytes(canonical)
        signature = subprocess.check_output(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(args.key), '-in', str(data)])
    public_der = subprocess.check_output(['openssl', 'pkey', '-in', str(args.key), '-pubout', '-outform', 'DER'])
    if len(public_der) != 44 or public_der[:12].hex() != '302a300506032b6570032100':
        raise ValueError('The key must be Ed25519.')
    envelope = dict(payload=payload, signature=base64.b64encode(signature).decode())
    args.output.write_text(json.dumps(envelope, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'publicKey': base64.b64encode(public_der[-32:]).decode(), 'version': args.version, 'output': str(args.output)}))


if __name__ == '__main__':
    main()
