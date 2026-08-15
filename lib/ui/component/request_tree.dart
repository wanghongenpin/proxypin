/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/platform.dart';

/// How the captured requests of a domain are laid out.
///
/// [list] is the default and the original layout: domain -> requests.
/// [tree] is the optional one, grouping requests by path segment:
/// domain -> segment -> segment -> request.
enum RequestViewMode {
  list,
  tree;

  /// Only a value that explicitly says tree selects the tree. A missing or
  /// unreadable value keeps the flat list, so nothing changes on its own.
  static RequestViewMode of(String? name) {
    return RequestViewMode.values.firstWhere((mode) => mode.name == name, orElse: () => RequestViewMode.list);
  }
}

/// A node of the path tree built for one domain.
///
/// A node can be a folder (it has children), a leaf holder (it has requests
/// whose path ends exactly here), or both. When it is both, the folder renders
/// its own requests after its children, so a URL that is at the same time a
/// directory and a resource still shows up under its own path.
class RequestTreeNode {
  /// Path segment this node stands for. The root node holds the domain.
  final String name;

  /// Stable identity of the node, used as widget key so that the expanded
  /// state survives rebuilds while traffic keeps coming in.
  final String key;

  /// Distance from the root node. The root itself is 0.
  final int depth;

  final LinkedHashMap<String, RequestTreeNode> _children = LinkedHashMap<String, RequestTreeNode>();

  /// Requests whose path terminates exactly at this node.
  final List<HttpRequest> requests = [];

  RequestTreeNode({required this.name, required this.key, required this.depth});

  Iterable<RequestTreeNode> get children => _children.values;

  bool get hasChildren => _children.isNotEmpty;

  bool get isEmpty => _children.isEmpty && requests.isEmpty;

  /// Total number of requests held by this node and the whole subtree below it.
  int get requestCount {
    var count = requests.length;
    for (var child in _children.values) {
      count += child.requestCount;
    }
    return count;
  }

  /// Requests in the order they are displayed: children first, in insertion
  /// order, then the requests owned by this node. Used for range selection.
  List<HttpRequest> orderedRequests() {
    var result = <HttpRequest>[];
    _collect(result);
    return result;
  }

  void _collect(List<HttpRequest> out) {
    for (var child in _children.values) {
      child._collect(out);
    }
    out.addAll(requests);
  }

  RequestTreeNode _childOf(String segment) {
    return _children.putIfAbsent(segment, () => RequestTreeNode(name: segment, key: '$key/$segment', depth: depth + 1));
  }
}

/// Builds the path tree of a domain.
class RequestTree {
  /// Builds the tree of [requests] under [domain].
  ///
  /// The insertion order of [requests] is preserved, so the caller stays in
  /// control of the sort direction.
  static RequestTreeNode build(String domain, Iterable<HttpRequest> requests) {
    var root = RequestTreeNode(name: domain, key: domain, depth: 0);
    for (var request in requests) {
      var node = root;
      for (var segment in pathSegments(request)) {
        node = node._childOf(segment);
      }
      node.requests.add(request);
    }
    return root;
  }

  /// Path of [request] split into segments, empty ones dropped.
  ///
  /// The query string never creates a node; it belongs to the leaf. Two
  /// requests on the same path with different queries are two leaves sitting
  /// side by side.
  static List<String> pathSegments(HttpRequest request) {
    var path = request.path;
    if (path.isEmpty) {
      return const [];
    }
    return path.split('/').where((segment) => segment.isNotEmpty).toList();
  }

  /// Lines of [root] that are currently on screen, top to bottom.
  ///
  /// Everything emitted for a folder sits one level deeper than that folder:
  /// its child folders, the requests of a child that has no folder of its own,
  /// and finally the requests owned by the folder itself.
  static List<RequestTreeRow> visibleRows(RequestTreeNode root, RequestTreeExpansion expansion) {
    var rows = <RequestTreeRow>[];
    _collectRows(root, expansion, rows);
    return rows;
  }

  static void _collectRows(RequestTreeNode node, RequestTreeExpansion expansion, List<RequestTreeRow> rows) {
    var depth = node.depth + 1;

    for (var child in node.children) {
      if (child.hasChildren) {
        rows.add(
            RequestTreeRow(key: child.key, parentKey: node.key, depth: child.depth, label: child.name, node: child));
        if (expansion.isExpanded(child.key)) {
          _collectRows(child, expansion, rows);
        }
        continue;
      }
      for (var request in child.requests) {
        rows.add(_leafRow(request, child, depth, node.key));
      }
    }

    for (var request in node.requests) {
      rows.add(_leafRow(request, node, depth, node.key));
    }
  }

  static RequestTreeRow _leafRow(HttpRequest request, RequestTreeNode holder, int depth, String parentKey) {
    return RequestTreeRow(
        key: '${holder.key}#${request.requestId}',
        parentKey: parentKey,
        depth: depth,
        label: leafLabel(request),
        node: holder,
        request: request);
  }

  /// Label of the leaf row of [request]: its last path segment plus the query
  /// string when there is one. A request on the domain root shows `/`.
  static String leafLabel(HttpRequest request) {
    var segments = pathSegments(request);
    var name = segments.isEmpty ? '/' : segments.last;
    var uri = request.requestUri;
    if (uri != null && uri.hasQuery && uri.query.isNotEmpty) {
      return '$name?${uri.query}';
    }
    return name;
  }
}

/// One rendered line of the tree: either a folder or a single request.
///
/// The same list drives the rendering and the keyboard navigation, so what the
/// arrow keys walk through is exactly what is on screen.
class RequestTreeRow {
  /// Unique identity of the line.
  final String key;

  /// Line holding the folder this one sits in, null for a top level line.
  /// Used by the left arrow to jump back to the parent.
  final String? parentKey;

  final int depth;
  final String label;

  /// Folder of this line, or the folder the request belongs to.
  final RequestTreeNode node;

  /// Request of this line; null means the line is a folder.
  final HttpRequest? request;

  const RequestTreeRow({
    required this.key,
    required this.parentKey,
    required this.depth,
    required this.label,
    required this.node,
    this.request,
  });

  bool get isFolder => request == null;
}

/// Expanded state of the tree folders, kept outside the widgets so that it
/// survives rebuilds while traffic keeps coming in, and so that "expand all" /
/// "collapse all" can drive every folder at once without walking the tree.
///
/// [_defaultExpanded] is the state a folder has when the user never touched it;
/// [_toggled] holds the folders that were flipped away from that default.
class RequestTreeExpansion extends ChangeNotifier {
  bool _defaultExpanded;
  final Set<String> _toggled = {};

  RequestTreeExpansion({bool expandedByDefault = false}) : _defaultExpanded = expandedByDefault;

  void setExpanded(String key, bool expanded) {
    if (isExpanded(key) == expanded) {
      return;
    }
    toggle(key);
  }

  bool isExpanded(String key) {
    return _toggled.contains(key) ? !_defaultExpanded : _defaultExpanded;
  }

  void toggle(String key) {
    if (!_toggled.remove(key)) {
      _toggled.add(key);
    }
    notifyListeners();
  }

  void expandAll() {
    _defaultExpanded = true;
    _toggled.clear();
    notifyListeners();
  }

  void collapseAll() {
    _defaultExpanded = false;
    _toggled.clear();
    notifyListeners();
  }
}

/// Presentation applied to a request row while the domain list renders as a
/// tree. It is null in list mode, where the row keeps its original layout.
class RequestTreeStyle {
  /// Horizontal space added per depth level.
  static const double indentStep = 14;

  /// Height of one line in tree mode. A line carries a single path segment,
  /// so it is kept tight to fit more of the tree on screen. Mobile stays
  /// taller than desktop to keep the row comfortable to tap.
  static double get rowHeight => Platforms.isDesktop() ? 26 : 36;

  /// Text shown instead of the full path.
  final String label;

  /// Indent depth of the row, root domain being 0.
  final int depth;

  /// Identity of the line in the tree, used to tell whether the keyboard
  /// cursor is on this row.
  final String rowKey;

  const RequestTreeStyle({required this.label, required this.depth, this.rowKey = ''});

  bool sameAs(RequestTreeStyle? other) {
    return other != null && other.label == label && other.depth == depth && other.rowKey == rowKey;
  }
}
