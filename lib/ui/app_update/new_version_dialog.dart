import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';

class NewVersionDialog extends StatelessWidget {
  NewVersionDialog(
    this.currentVersion,
    this.newVersion, {
    this.canIgnore = true,
  }) : super(key: _dialogKey);

  final String currentVersion;
  final RemoteVersionEntity newVersion;
  final bool canIgnore;

  static final _dialogKey = GlobalKey(debugLabel: 'new version dialog');

  Future<void> show(BuildContext context) async {
    if (_dialogKey.currentContext == null) {
      return showDialog(
        context: context,
        useRootNavigator: true,
        builder: (context) => this,
      );
    } else {
      logger.d("new version dialog is already open");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.appUpdateDialogTitle),
      // scrollable: true,
      content: Container(
          constraints: BoxConstraints(maxHeight: 230, maxWidth: 500),
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.appUpdateUpdateMsg),
              const SizedBox(height: 5),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: "${localizations.appUpdateCurrentVersionLbl}: ", style: theme.textTheme.bodySmall),
                    TextSpan(text: currentVersion, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: "${localizations.appUpdateNewVersionLbl}: ", style: theme.textTheme.bodySmall),
                    TextSpan(text: newVersion.version, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
              Text(newVersion.content ?? '', style: theme.textTheme.labelMedium),
            ],
          ))),
      actions: [
        if (canIgnore)
          TextButton(
            onPressed: () async {
              SharedPreferencesAsync().setString(Constants.ignoreReleaseVersionKey, newVersion.version);
              logger.i("ignored release [${newVersion.version}]");
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(localizations.appUpdateIgnoreBtnTxt),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.appUpdateLaterBtnTxt),
        ),
        TextButton(
          onPressed: () async {
            await launchUrl(Uri.parse(newVersion.url), mode: LaunchMode.externalApplication);
          },
          child: Text(localizations.appUpdateUpdateNowBtnTxt),
        ),
      ],
    );
  }
}
