"""The project guard must reject regressions that would affect the extension."""
from pathlib import Path
import re
import tempfile
import unittest

from check_ios_preview import check
from ios_project import parse_project


class ProjectTests(unittest.TestCase):
    def test_reads_comments_quoted_values_and_nested_lists(self):
        self.assertEqual(parse_project('// comment\n{a = (one, "two words",); b = {c = "x\\ny";};}'),
                         {'a': ['one', 'two words'], 'b': {'c': 'x\ny'}})

    def test_rejects_duplicate_keys(self):
        with self.assertRaises(ValueError):
            parse_project('{a = one; a = two;}')

    def test_runner_archives_preserve_global_ffi_symbols(self):
        root = Path(__file__).resolve().parent.parent
        source = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        objects = parse_project(source)['objects']
        runner = next(v for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'Runner')
        for config in objects[runner['buildConfigurationList']]['buildConfigurations']:
            self.assertEqual(objects[config]['buildSettings'].get('STRIP_STYLE'), 'non-global')
        # Removing any one configuration's protection must fail the real guard.
        for occurrence in range(3):
            start = [m.start() for m in re.finditer('STRIP_STYLE = "non-global";', source)][occurrence]
            changed = source[:start] + source[start:].replace('STRIP_STYLE = "non-global";', 'STRIP_STYLE = all;', 1)
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / 'ios/Runner.xcodeproj/project.pbxproj'
                path.parent.mkdir(parents=True)
                path.write_text(changed, encoding='utf-8')
                with self.assertRaisesRegex(ValueError, 'preserve global FFI'):
                    check(Path(temporary))

    def test_real_project_is_isolated_and_rejects_an_app_dependency(self):
        root = Path(__file__).resolve().parent.parent
        check(root)
        source = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        target = next(k for k, v in parse_project(source)['objects'].items()
                      if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'NotificationService')
        # A direct dependency is refused before the checker reads source files.
        start = source.index(target + ' /* NotificationService */ = {')
        source = source[:start] + source[start:].replace('dependencies = ();', 'dependencies = (unapproved,);', 1)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'ios/Runner.xcodeproj/project.pbxproj'
            path.parent.mkdir(parents=True)
            path.write_text(source, encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'must not depend'):
                check(Path(temporary))

    def test_rejects_a_second_xcframework_copy_phase(self):
        root = Path(__file__).resolve().parent.parent
        source = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        objects = parse_project(source)['objects']
        target = next(v for v in objects.values()
                      if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'NotificationService')
        phase = next(p for p in target['buildPhases']
                     if objects[p]['isa'] == 'PBXFrameworksBuildPhase')
        start = source.index(phase + ' /* NotificationService Frameworks */ = {')
        source = source[:start] + source[start:].replace(
            'files = ();', 'files = (77813903931081F59ED7B37E, );', 1)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'ios/Runner.xcodeproj/project.pbxproj'
            path.parent.mkdir(parents=True)
            path.write_text(source, encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'another XCFramework copy phase'):
                check(Path(temporary))

    def test_rejects_duplicate_clang_module_search_paths(self):
        root = Path(__file__).resolve().parent.parent
        source = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        source = source.replace('APPLICATION_EXTENSION_API_ONLY = YES;',
                                'APPLICATION_EXTENSION_API_ONLY = YES; SWIFT_INCLUDE_PATHS = duplicate;', 1)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'ios/Runner.xcodeproj/project.pbxproj'
            path.parent.mkdir(parents=True)
            path.write_text(source, encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'duplicate module paths'):
                check(Path(temporary))


if __name__ == '__main__':
    unittest.main()
