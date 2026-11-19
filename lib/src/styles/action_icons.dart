import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// One icon per action wherever it appears (issue 212): the ones the held
/// message menu shows. A screen that copies or deletes uses these, so the
/// same action never looks different from one page to the next.
abstract final class ActionIcons {
  static const IconData copy = CupertinoIcons.doc_on_doc;
  static const IconData delete = CupertinoIcons.trash;
}
