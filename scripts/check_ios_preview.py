"""Guard extension embedding, isolation, entitlements and release diagnostics."""
from pathlib import Path
import plistlib
import re
import sys

from ios_project import parse_project

LIBRARY = '../packages/fireplace_native/ios/fireplace_native/Frameworks/FireplaceCrypto.xcframework'
IMPORTS = {'Foundation', 'CoreFoundation', 'Darwin', 'Security', 'UserNotifications', 'CryptoKit', 'FireplaceCrypto'}


def check(root):
    ios = root / 'ios'
    objects = parse_project((ios / 'Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))['objects']
    targets = {o['name']: (key, o) for key, o in objects.items() if o.get('isa') == 'PBXNativeTarget'}
    identifier, target = targets['NotificationService']
    if target['productType'] != 'com.apple.product-type.app-extension' or target.get('dependencies') or target.get('packageProductDependencies'):
        raise ValueError('Extension must not depend on the app or Flutter packages')
    runner = targets['Runner'][1]
    if not any(objects[d].get('target') == identifier for d in runner['dependencies']):
        raise ValueError('App does not build its extension')
    phases = [objects[p] for p in runner['buildPhases']]
    if not any(p['isa'] == 'PBXCopyFilesBuildPhase' and p.get('dstSubfolderSpec') == '13' and
               any(objects[f].get('fileRef') == target['productReference'] for f in p['files']) for p in phases):
        raise ValueError('App does not embed its extension')
    phases = [objects[p] for p in target['buildPhases']]
    libraries = [objects[objects[f]['fileRef']]['path'] for p in phases if p['isa'] == 'PBXFrameworksBuildPhase' for f in p['files']]
    if libraries != [LIBRARY]:
        raise ValueError('Extension may link only the static core and imported system frameworks')
    paths = [objects[objects[f]['fileRef']]['path'] for p in phases if p['isa'] == 'PBXSourcesBuildPhase' for f in p['files']]
    for path in paths:
        file = (ios / path).resolve()
        if not file.is_relative_to((ios / 'NotificationService').resolve()):
            raise ValueError('Extension source escapes its own directory')
        source = file.read_text(encoding='utf-8')
        if set(re.findall(r'^import\s+(\w+)', source, re.M)) - IMPORTS:
            raise ValueError('Extension imports an unapproved framework')
        if re.search(r'\b(?:SecItemAdd|SecItemUpdate|SecItemDelete|fp_session_save|fp_session_encrypt|fp_prekey_generate)\s*\(', source):
            raise ValueError('Extension has a forbidden mutation API')
        if file.name == 'PreviewDiagnostics.swift' and not source.startswith('#if PREVIEW_DIAGNOSTICS\n'):
            raise ValueError('Diagnostics writer is not compiled out of release builds')
    for config in objects[target['buildConfigurationList']]['buildConfigurations']:
        config = objects[config]
        settings = config['buildSettings']
        if settings['APPLICATION_EXTENSION_API_ONLY'] != 'YES' or settings['IPHONEOS_DEPLOYMENT_TARGET'] != '15.0':
            raise ValueError('Extension target settings are unsafe')
        if config['name'] != 'Debug' and 'PREVIEW_DIAGNOSTICS' in settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', ''):
            raise ValueError('Release diagnostics must default off')
    app = plistlib.loads((ios / 'Runner/Runner.entitlements').read_bytes())
    extension = plistlib.loads((ios / 'NotificationService/NotificationService.entitlements').read_bytes())
    if app['com.apple.security.application-groups'] != ['group.com.fireplacechat.app'] or extension['com.apple.security.application-groups'] != app['com.apple.security.application-groups']:
        raise ValueError('App Group mismatch')
    if app['keychain-access-groups'] != ['$(AppIdentifierPrefix)com.fireplacechat.app', '$(AppIdentifierPrefix)com.fireplacechat.app.shared'] or extension['keychain-access-groups'] != app['keychain-access-groups'][1:]:
        raise ValueError('Keychain group mismatch or changed default')
    print('iOS preview isolation, embedding, groups and release defaults OK')


if __name__ == '__main__':
    check(Path(sys.argv[1] if len(sys.argv) > 1 else '.'))
