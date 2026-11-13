"""Check the runtime interface and signed keychain configuration of a built app."""
from pathlib import Path
import argparse
import plistlib
import re
import subprocess

APP = 'com.fireplacechat.app'
EXTENSION = APP + '.NotificationService'
GROUP = 'group.' + APP


def validate_exports(header, exports):
    expected = set(re.findall(r'\b(fp_[a-z0-9_]+)\s*\(', header)) - {'fp_set_test_rng', 'fp_clear_test_rng'}
    if not {'fp_free', 'fp_identity_consistent', 'fp_device_consistent', 'fp_session_load'} <= expected:
        raise ValueError('Could not identify the published core ABI')
    actual = set(re.findall(r'\b_(fp_[a-z0-9_]+)\b', exports))
    missing = expected - actual
    if missing:
        raise ValueError('Runner has no dynamic export for: ' + ', '.join(sorted(missing)))
    if actual & {'fp_set_test_rng', 'fp_clear_test_rng'}:
        raise ValueError('Runner exports the test random stream')
    return len(expected)


def validate_groups(app_info, extension_info, app_entitlements, extension_entitlements):
    identifier = app_entitlements.get('application-identifier', '')
    if not isinstance(identifier, str) or not identifier.endswith('.' + APP):
        raise ValueError('Signed app identifier is invalid')
    prefix = identifier[:-len(APP)]
    if not re.fullmatch(r'[A-Z0-9]{10}\.', prefix):
        raise ValueError('Signed app identifier prefix is invalid')
    legacy = prefix + APP
    shared = legacy + '.shared'
    for info, entitlements, bundle in (
            (app_info, app_entitlements, APP),
            (extension_info, extension_entitlements, EXTENSION)):
        if info.get('CFBundleIdentifier') != bundle or entitlements.get('application-identifier') != prefix + bundle:
            raise ValueError('Signed app and extension identifiers or prefixes disagree')
        if info.get('FPSharedKeychainGroup') != shared:
            raise ValueError('Info.plist shared keychain group does not match the signed prefix')
        if info.get('FPAppGroup') != GROUP or entitlements.get('com.apple.security.application-groups') != [GROUP]:
            raise ValueError('Signed App Group configuration disagrees')
    if app_info.get('FPLegacyKeychainGroup') != legacy:
        raise ValueError('Info.plist legacy keychain group does not match the signed prefix')
    if app_entitlements.get('keychain-access-groups') != [legacy, shared]:
        raise ValueError('Signed app no longer preserves its original default keychain group')
    if extension_entitlements.get('keychain-access-groups') != [shared]:
        raise ValueError('Signed extension keychain access is incorrect')


def entitlements(bundle):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)],
                            capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def check(app, signed=False):
    root = Path(__file__).resolve().parent.parent
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    binary = app / info['CFBundleExecutable']
    header = root / 'ios/NotificationService/Memory/.generated/fireplace_crypto.h'
    exports = subprocess.run(['xcrun', 'dyld_info', '-exports', str(binary)],
                             capture_output=True, text=True, check=True).stdout
    count = validate_exports(header.read_text(encoding='utf-8'), exports)
    print(f'Runner dynamic C ABI exports checked: {count}')
    if signed:
        extension = app / 'PlugIns/NotificationService.appex'
        extension_info = plistlib.loads((extension / 'Info.plist').read_bytes())
        validate_groups(info, extension_info, entitlements(app), entitlements(extension))
        print('Signed runtime keychain groups, preserved default group and App Group checked')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--signed', action='store_true')
    args = parser.parse_args()
    try:
        check(args.app, args.signed)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Never echo entitlements, signing material or arbitrary process output.
        message = str(error) if isinstance(error, ValueError) else 'Could not inspect the built app'
        raise SystemExit(message)
