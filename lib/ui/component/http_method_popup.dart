// Add MethodPopupMenu widget for compact colored method display
import 'package:flutter/material.dart';

import '../../network/http/http.dart';

class MethodPopupMenu extends StatelessWidget {
  final HttpMethod? value;
  final ValueChanged<HttpMethod?> onChanged;
  final bool showSeparator; // whether to display the vertical separator to the right

  const MethodPopupMenu({super.key, required this.value, required this.onChanged, this.showSeparator = true});

  Color _methodColor(HttpMethod? m, BuildContext context) {
    // colors chosen similar to Postman style
    switch (m) {
      case HttpMethod.get:
        return Colors.green.shade700;
      case HttpMethod.post:
        return Colors.orange.shade700;
      case HttpMethod.put:
        return Colors.blue.shade700;
      case HttpMethod.patch:
        return Colors.purple.shade700;
      case HttpMethod.delete:
        return Colors.red.shade700;
      case HttpMethod.options:
        return Colors.teal.shade700; // OPTIONS colored teal
      case HttpMethod.head:
        return Colors.indigo.shade700; // HEAD colored indigo
      case HttpMethod.trace:
      case HttpMethod.connect:
      case HttpMethod.propfind:
      case HttpMethod.report:
        return Colors.grey.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    var items = <DropdownMenuItem<HttpMethod?>>[];
    items.add(DropdownMenuItem<HttpMethod?>(value: null, child: _buildMenuItem(null, context)));
    for (var m in HttpMethod.methods()) {
      if (m == HttpMethod.connect || m == HttpMethod.options) continue;
      items.add(DropdownMenuItem<HttpMethod?>(value: m, child: _buildMenuItem(m, context)));
    }

    final dropdown = DropdownButton<HttpMethod?>(
      padding: const EdgeInsets.only(),
      alignment: AlignmentDirectional.center,
      isDense: true,
      focusColor: Colors.transparent,
      underline: const SizedBox(),
      value: value,
      onChanged: onChanged,
      items: items,
    );

    // render dropdown and optional separator together so caller doesn't need to add one
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dropdown,
        if (showSeparator) ...[
          const SizedBox(width: 3),
          Container(width: 1, height: 22, color: Colors.grey.shade300),
          const SizedBox(width: 3),
        ]
      ],
    );
  }

  Widget _buildMenuItem(HttpMethod? m, BuildContext context) {
    final name = m == null ? 'ANY' : m.name;
    final color = _methodColor(m, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(name, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
