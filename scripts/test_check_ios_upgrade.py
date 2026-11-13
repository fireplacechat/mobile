"""Reject the packaging failures that can masquerade as missing device keys."""
import copy
import unittest

from check_ios_upgrade import APP, EXTENSION, GROUP, validate_exports, validate_groups


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        # The App ID prefix need not equal the team identifier.
        prefix = 'OLDPREFIX1.'
        legacy = prefix + APP
        shared = legacy + '.shared'
        self.app = {'CFBundleIdentifier': APP, 'FPAppGroup': GROUP,
                    'FPLegacyKeychainGroup': legacy, 'FPSharedKeychainGroup': shared}
        self.extension = {'CFBundleIdentifier': EXTENSION, 'FPAppGroup': GROUP,
                          'FPSharedKeychainGroup': shared}
        self.app_entitlements = {'application-identifier': legacy,
                                 'com.apple.developer.team-identifier': 'NEWTEAM001',
                                 'keychain-access-groups': [legacy, shared],
                                 'com.apple.security.application-groups': [GROUP]}
        self.extension_entitlements = {'application-identifier': prefix + EXTENSION,
                                       'keychain-access-groups': [shared],
                                       'com.apple.security.application-groups': [GROUP]}

    def check_groups(self):
        validate_groups(self.app, self.extension, self.app_entitlements, self.extension_entitlements)

    def test_preserves_the_actual_app_identifier_prefix(self):
        self.check_groups()

    def test_rejects_an_unexpanded_or_missing_runtime_prefix(self):
        for value in (APP + '.shared', '$(AppIdentifierPrefix)' + APP + '.shared', 'NEWTEAM001.' + APP + '.shared'):
            with self.subTest(value=value):
                original = self.app['FPSharedKeychainGroup']
                self.app['FPSharedKeychainGroup'] = value
                with self.assertRaisesRegex(ValueError, 'shared keychain group'):
                    self.check_groups()
                self.app['FPSharedKeychainGroup'] = original

    def test_rejects_a_changed_default_group(self):
        self.app_entitlements['keychain-access-groups'].reverse()
        with self.assertRaisesRegex(ValueError, 'original default'):
            self.check_groups()

    def test_rejects_extension_prefix_or_group_mismatch(self):
        original = copy.deepcopy(self.extension_entitlements)
        self.extension_entitlements['application-identifier'] = 'NEWTEAM001.' + EXTENSION
        with self.assertRaisesRegex(ValueError, 'prefixes disagree'):
            self.check_groups()
        self.extension_entitlements = original
        self.extension['FPSharedKeychainGroup'] = APP + '.shared'
        with self.assertRaisesRegex(ValueError, 'shared keychain group'):
            self.check_groups()

    def test_requires_real_dynamic_exports_for_existing_device_validation(self):
        header = 'void fp_free(); int fp_identity_consistent(); int fp_device_consistent(); int fp_session_load();'
        exports = ' -exports:\n 0x123 _fp_free\n 0x456 _fp_identity_consistent\n 0x789 _fp_device_consistent\n 0xabc _fp_session_load\n'
        self.assertEqual(validate_exports(header, exports), 4)
        with self.assertRaisesRegex(ValueError, 'fp_device_consistent'):
            validate_exports(header, exports.replace('_fp_device_consistent', '_unrelated'))
        with self.assertRaisesRegex(ValueError, 'test random stream'):
            validate_exports(header, exports + '\n 0xdef _fp_set_test_rng\n')


if __name__ == '__main__':
    unittest.main()
