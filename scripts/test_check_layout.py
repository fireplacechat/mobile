#!/usr/bin/env python3
"""Exercise the layout guard without Flutter or real application data."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CHECKER = Path(__file__).with_name('check_layout.py')


class LayoutTests(unittest.TestCase):
    def check(self, sources, ok):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, source in sources.items():
                target = root / 'lib' / 'src' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(source)
            result = subprocess.run(
                [sys.executable, str(CHECKER), directory],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
            return result.stdout + result.stderr

    def test_missing_tree_fails(self):
        self.assertIn('Missing source tree', self.check({}, False))

    def test_model_can_import_database(self):
        self.check({'model/chat/send.dart': "import 'package:fireplace/src/db/messages.dart';"}, True)

    def test_model_cannot_import_view_or_widgets(self):
        for target in ('package:fireplace/src/view/chat/screen.dart', 'package:flutter/material.dart'):
            with self.subTest(target=target):
                self.check({'model/chat/send.dart': f"import '{target}';"}, False)

    def test_crypto_cannot_import_firebase_or_other_app_layers(self):
        for target in ('package:cloud_firestore/cloud_firestore.dart', 'package:fireplace/src/utils/helper.dart'):
            with self.subTest(target=target):
                self.check({'crypto/session.dart': f"import '{target}';"}, False)

    def test_relative_app_import_fails(self):
        self.check({'model/chat/send.dart': "import '../../view/chat/screen.dart';"}, False)

    def test_cross_feature_nested_import_fails(self):
        self.check({'view/chat/screen.dart': "import 'package:fireplace/src/view/settings/widgets/tile.dart';"}, False)

    def test_cross_feature_public_file_allowed(self):
        self.check({'view/chat/screen.dart': "import 'package:fireplace/src/view/settings/settings.dart';"}, True)

    def test_long_file_warns_without_failing(self):
        self.assertIn('WARN', self.check({'crypto/session.dart': '// preserved\n' * 501}, True))

    def test_legacy_composite_is_explicitly_transitional(self):
        self.check({'ui/chat_screen.dart': "import 'package:fireplace/src/model/chat/send.dart';"}, True)


if __name__ == '__main__':
    unittest.main()
