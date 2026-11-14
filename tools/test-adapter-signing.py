#!/usr/bin/env python3
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AdapterSigning(unittest.TestCase):
    def test_generated_update_has_valid_owner_signature(self):
        with tempfile.TemporaryDirectory(prefix='sideos-adapter-test-') as temporary:
            folder = Path(temporary)
            key, source, update = folder/'private.pem', folder/'adapter.js', folder/'update.json'
            source.write_text('/* ⋯ */\nvoid 0;')
            result = subprocess.run([sys.executable, str(ROOT/'tools/sign-chat-adapter.py'), '--key', str(key), '--generate-key', '--source', str(source), '--version', '1', '--output', str(update)], check=True, text=True, capture_output=True)
            metadata = json.loads(result.stdout)
            self.assertEqual(len(base64.b64decode(metadata['publicKey'])), 32)
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            envelope = json.loads(update.read_text())
            canonical = json.dumps(envelope['payload'], sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()
            self.assertEqual(canonical.decode(), '{"minimumHost":"3.1.0","origin":"https://chatgpt.com","script":"/* ⋯ */\\nvoid 0;","version":1}')
            payload, signature, public = folder/'payload', folder/'signature', folder/'public.pem'
            payload.write_bytes(canonical); signature.write_bytes(base64.b64decode(envelope['signature']))
            subprocess.run(['openssl','pkey','-in',str(key),'-pubout','-out',str(public)],check=True,capture_output=True)
            command=['openssl','pkeyutl','-verify','-rawin','-pubin','-inkey',str(public),'-sigfile',str(signature),'-in',str(payload)]
            self.assertEqual(subprocess.run(command,capture_output=True).returncode,0)
            payload.write_bytes(canonical+b'tamper')
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)

    def test_invalid_version_is_rejected_before_signing(self):
        result=subprocess.run([sys.executable,str(ROOT/'tools/sign-chat-adapter.py'),'--key','unused.pem','--source','unused.js','--version','0','--output','unused.json'],capture_output=True)
        self.assertNotEqual(result.returncode,0)


if __name__=='__main__':
    unittest.main()
