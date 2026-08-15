import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/request_tree.dart';
import 'package:proxypin/ui/component/request_tree_view.dart';

HttpRequest _request(String url) => HttpRequest(HttpMethod.get, url);

/// Hosts the tree in a minimal app. Leaves render as plain Text so that the
/// assertions can address them by label and depth.
Widget _host(RequestTreeNode root, RequestTreeExpansion expansion) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: SingleChildScrollView(
        child: RequestTreeView(
          root: root,
          expansion: expansion,
          leafBuilder: (request, style) => Padding(
            padding: EdgeInsets.only(left: style.depth * RequestTreeStyle.indentStep),
            child: Text('leaf:${style.label}@${style.depth}'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('folders start collapsed and only show the first level', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion()));
    await tester.pumpAndSettle();

    expect(find.text('hominhtuong'), findsOneWidget);
    expect(find.text('proxypin'), findsNothing);
    expect(find.text('leaf:latest-commit@3'), findsNothing);
  });

  testWidgets('tapping a folder opens the level below it', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hominhtuong'));
    await tester.pumpAndSettle();
    expect(find.text('proxypin'), findsOneWidget);
    expect(find.text('leaf:latest-commit@3'), findsNothing);

    await tester.tap(find.text('proxypin'));
    await tester.pumpAndSettle();
    expect(find.text('leaf:latest-commit@3'), findsOneWidget);
  });

  testWidgets('forceExpanded shows the whole tree without any tap', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
      _request('https://github.com/hominhtuong/proxypin/_sidebar'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion(expandedByDefault: true)));
    await tester.pumpAndSettle();

    expect(find.text('hominhtuong'), findsOneWidget);
    expect(find.text('proxypin'), findsOneWidget);
    expect(find.text('leaf:latest-commit@3'), findsOneWidget);
    expect(find.text('leaf:_sidebar@3'), findsOneWidget);
  });

  testWidgets('a request on a folder renders one level deeper than that folder', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin'),
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion(expandedByDefault: true)));
    await tester.pumpAndSettle();

    // the proxypin folder sits at depth 2, so the request on it renders at depth 3
    expect(find.text('leaf:proxypin@3'), findsOneWidget);
    expect(find.text('leaf:latest-commit@3'), findsOneWidget);
  });

  testWidgets('a request on the domain root sits at depth 1 and is labelled /', (tester) async {
    final root = RequestTree.build('https://example.com', [_request('https://example.com/')]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion(expandedByDefault: true)));
    await tester.pumpAndSettle();

    expect(find.text('leaf:/@1'), findsOneWidget);
  });

  testWidgets('a folder shows how many requests its subtree holds', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
      _request('https://github.com/hominhtuong/proxypin/_sidebar'),
      _request('https://github.com/hominhtuong/other'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion()));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('3 requests'), findsOneWidget);
  });

  testWidgets('the request count of a folder is singular when there is only one', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('1 request'), findsOneWidget);
    expect(find.byTooltip('1 requests'), findsNothing);
  });

  testWidgets('expandAll then collapseAll drives every folder at once', (tester) async {
    final expansion = RequestTreeExpansion();
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
    ]);

    await tester.pumpWidget(_host(root, expansion));
    await tester.pumpAndSettle();

    expansion.expandAll();
    await tester.pumpAndSettle();
    expect(find.text('leaf:latest-commit@3'), findsOneWidget);

    expansion.collapseAll();
    await tester.pumpAndSettle();
    expect(find.text('proxypin'), findsNothing);
    expect(find.text('leaf:latest-commit@3'), findsNothing);
  });
  testWidgets('tapping an expanded folder collapses it again', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hominhtuong'));
    await tester.pumpAndSettle();
    expect(find.text('proxypin'), findsOneWidget, reason: 'first level opened');

    await tester.tap(find.text('proxypin'));
    await tester.pumpAndSettle();
    expect(find.text('leaf:latest-commit@3'), findsOneWidget, reason: 'second level opened');

    await tester.tap(find.text('proxypin'));
    await tester.pumpAndSettle();
    expect(find.text('leaf:latest-commit@3'), findsNothing, reason: 'second level collapsed again');

    await tester.tap(find.text('hominhtuong'));
    await tester.pumpAndSettle();
    expect(find.text('proxypin'), findsNothing, reason: 'first level collapsed again');
  });

  testWidgets('a folder line is no taller than one tree row', (tester) async {
    final root = RequestTree.build('https://github.com', [
      _request('https://github.com/hominhtuong/proxypin/latest-commit'),
      _request('https://github.com/hominhtuong/proxypin/_sidebar'),
    ]);

    await tester.pumpWidget(_host(root, RequestTreeExpansion(expandedByDefault: true)));
    await tester.pumpAndSettle();

    // A line carries one path segment; if the row height drifts, the tree quietly
    // fits fewer lines on screen.
    for (var folder in ['hominhtuong', 'proxypin']) {
      var tile = find.ancestor(of: find.text(folder), matching: find.byType(ListTile)).first;
      expect(tester.getSize(tile).height, RequestTreeStyle.rowHeight, reason: 'folder $folder');
    }
  });
}
