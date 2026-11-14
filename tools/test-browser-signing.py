from datetime import datetime, timedelta, timezone
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('browser_signing', Path(__file__).with_name('browser-signing-entitlements.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class Signing(unittest.TestCase):
    def setUp(self):
        self.profile = {'TeamIdentifier': ['ABCDE12345'], 'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=1),
            'Entitlements': {'application-identifier': 'ABCDE12345.' + m.BASE_ID,
                'com.apple.developer.team-identifier': 'ABCDE12345', 'get-task-allow': True,
                'com.apple.security.application-groups': ['group.unwanted'], 'keychain-access-groups': ['ABCDE12345.*']}}
    def test_removes_debug_and_groups_from_broad_profile(self):
        bundle, requests = m.requests(self.profile)
        self.assertEqual(bundle, m.BASE_ID)
        self.assertFalse(requests['get-task-allow'])
        self.assertNotIn('com.apple.security.application-groups', requests)
        self.assertEqual(requests['keychain-access-groups'], ['ABCDE12345.' + m.BASE_ID])
    def test_rejects_wrong_app_team_keychain_and_expired_profile(self):
        for key, value in [('application-identifier', 'ABCDE12345.com.other.app'),
                           ('com.apple.developer.team-identifier', 'WRONG'), ('keychain-access-groups', ['WRONG.*'])]:
            profile = {**self.profile, 'Entitlements': {**self.profile['Entitlements'], key: value}}
            with self.assertRaises(ValueError): m.requests(profile)
        with self.assertRaises(ValueError): m.requests({**self.profile, 'ExpirationDate': datetime(2020,1,1,tzinfo=timezone.utc)})

if __name__ == '__main__': unittest.main()
