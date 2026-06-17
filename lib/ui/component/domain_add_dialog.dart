import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/url_pattern.dart';

/// Shared dialog for adding/editing a domain filter entry.
///
/// Used by both desktop and mobile filter pages — previously each
/// had its own identical copy.
class DomainAddDialog extends StatelessWidget {
  final HostList hostList;
  final int? index;

  const DomainAddDialog({super.key, required this.hostList, this.index});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    GlobalKey formKey = GlobalKey<FormState>();
    String? host = index == null ? null : hostList.list.elementAt(index!).pattern.replaceAll(".*", "*");
    return AlertDialog(
        scrollable: true,
        content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Form(
                key: formKey,
                child: Column(children: <Widget>[
                  TextFormField(
                      initialValue: host,
                      decoration: const InputDecoration(labelText: 'Host', hintText: '*.example.com'),
                      validator: (val) => val == null || val.trim().isEmpty ? localizations.cannotBeEmpty : null,
                      onChanged: (val) => host = val)
                ]))),
        actions: [
          TextButton(child: Text(localizations.cancel), onPressed: () => Navigator.of(context).pop()),
          TextButton(
              child: Text(localizations.save),
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  return;
                }
                try {
                  if (index != null) {
                    hostList.list[index!] = UrlPattern.toHostRegExp(host!.trim());
                  } else {
                    hostList.add(host!.trim());
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
                Navigator.of(context).pop(host);
              }),
        ]);
  }
}
