import 'package:fireplace/src/model/settings/licence_catalog.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LicencesScreen extends ConsumerStatefulWidget {
  const LicencesScreen({super.key});

  @override
  ConsumerState<LicencesScreen> createState() => _LicencesScreenState();
}

class _LicencesScreenState extends ConsumerState<LicencesScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _opening = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String query) => setState(() => _query = query);

  Future<void> _open(LicenceGroup group) async {
    if (_opening) return;
    _opening = true;
    FocusScope.of(context).unfocus();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => LicenceDetailScreen(group: group)),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(
      context: context,
      title: const Text('Open-source licences'),
    ),
    body: UiBodyViewport(
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: TextField(
                    key: const Key('licenceSearch'),
                    controller: _search,
                    onChanged: _searchChanged,
                    autocorrect: false,
                    inputFormatters: [LengthLimitingTextInputFormatter(256)],
                    decoration: InputDecoration(
                      labelText: 'Search packages',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('clearLicenceSearch'),
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                _searchChanged('');
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: ref
                      .watch(licenceCatalogProvider)
                      .when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => UiEmptyState(
                          title: 'Could not load licences',
                          message: 'Try again to read the open-source notices.',
                          icon: Icons.description_outlined,
                          action: TextButton(
                            onPressed: () =>
                                ref.invalidate(licenceCatalogProvider),
                            child: const Text('Try again'),
                          ),
                        ),
                        data: (groups) {
                          final shown = groups
                              .where((group) => group.matchesPackage(_query))
                              .toList();
                          if (shown.isEmpty) {
                            return UiEmptyState(
                              title: groups.isEmpty
                                  ? 'No licences available'
                                  : 'No packages found',
                              message: groups.isEmpty
                                  ? 'No open-source notices were supplied.'
                                  : 'Try another package name.',
                              icon: Icons.description_outlined,
                            );
                          }
                          return ListView.separated(
                            key: const Key('licenceGroups'),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: shown.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final group = shown[index];
                              return Card(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _open(group),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                group.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                            ),
                                            const Icon(Icons.chevron_right),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          group.packages.join(', '),
                                          style: TextStyle(
                                            color: FireplaceUiTokens.of(context)
                                                .accentText,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          group.displayText,
                                          maxLines: 5,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class LicenceDetailScreen extends StatelessWidget {
  const LicenceDetailScreen({super.key, required this.group});
  final LicenceGroup group;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: Text(group.name)),
    body: UiPageScroll(
      children: [
        SelectableText(
          group.packages.join(', '),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 20),
        SelectableText(group.displayText, key: const Key('fullLicenceText')),
      ],
    ),
  );
}
