import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';

///缓存时间菜单
/// @author wanghongen
class HistoryCacheTime extends StatefulWidget {
  final Configuration configuration;
  final Function(int) onSelected;

  const HistoryCacheTime(this.configuration, {super.key, required this.onSelected});

  @override
  State<StatefulWidget> createState() => _HistoryCacheTimeState();
}

class _HistoryCacheTimeState extends State<HistoryCacheTime> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
        tooltip: localizations.historyCacheTime,
        offset: const Offset(0, 35),
        icon: const Icon(Icons.av_timer, size: 19),
        initialValue: widget.configuration.historyCacheTime,
        onSelected: (val) {
          widget.configuration.historyCacheTime = val;
          widget.configuration.flushConfig();
          setState(() {
            widget.onSelected.call(val);
          });
        },
        itemBuilder: (BuildContext context) {
          return [
            PopupMenuItem(value: 0, height: 35, child: Text(localizations.historyManualSave)),
            PopupMenuItem(value: 7, height: 35, child: Text(localizations.historyDay(7))),
            PopupMenuItem(value: 30, height: 35, child: Text(localizations.historyDay(30))),
            PopupMenuItem(value: 99999, height: 35, child: Text(localizations.historyForever)),
          ];
        });
  }
}
