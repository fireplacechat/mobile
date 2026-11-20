import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// One face in the stack: a person, or a group whose name is still hidden.
@immutable
class RequestFace {
  const RequestFace(this.name, {this.color, this.group = false});
  final String name;
  final Color? color;
  final bool group;
}

/// Who is waiting in Message requests, drawn in the space of one chat-list
/// avatar (issue 248). One person fills it; two or three overlap in a small
/// cluster; past three, the last place says how many more ("+3").
class RequestAvatarStack extends StatelessWidget {
  const RequestAvatarStack({
    super.key,
    required this.faces,
    required this.size,
  });
  final List<RequestFace> faces;

  /// The square the stack fills: a chat-list avatar's size.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    if (faces.isEmpty) return SizedBox.square(dimension: size);
    if (faces.length == 1) {
      return SizedBox.square(
        dimension: size,
        child: _Face(face: faces.single, size: size),
      );
    }
    // A cluster in the square, each face ringed in the page colour: two
    // corner to corner; three (or two and a count) in a triangle, so every
    // initial shows.
    final shown = faces.length > 3 ? faces.take(2).toList() : faces;
    final more = faces.length - shown.length;
    final count = shown.length + (more > 0 ? 1 : 0);
    final small = count == 2 ? size * .68 : size * .58;
    final far = size - small;
    final places = count == 2
        ? [Offset.zero, Offset(far, far)]
        : [Offset(far / 2, 0), Offset(0, far), Offset(far, far)];
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: places[i].dx,
              top: places[i].dy,
              child: Container(
                key: i < shown.length ? null : const Key('requestsMore'),
                width: small,
                height: small,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: t.page,
                  shape: BoxShape.circle,
                ),
                child: i < shown.length
                    ? _Face(face: shown[i], size: small - 4)
                    // How many more are waiting.
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.selectedRow,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Text(
                                '+$more',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One person, or a group still unnamed.
class _Face extends StatelessWidget {
  const _Face({required this.face, required this.size});
  final RequestFace face;
  final double size;

  @override
  Widget build(BuildContext context) => face.group
      ? GroupAvatar(name: '', size: size)
      : PersonAvatar(name: face.name, size: size, color: face.color);
}
