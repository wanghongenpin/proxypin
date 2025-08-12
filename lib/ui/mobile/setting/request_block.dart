import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/utils/lang.dart';

class MobileRequestBlock extends StatefulWidget {
  final RequestBlockManager requestBlockManager;

  const MobileRequestBlock({super.key, required this.requestBlockManager});

  @override
  State<MobileRequestBlock> createState() => _RequestBlockState();
}

class _RequestBlockState extends State<MobileRequestBlock> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(title: Text(localizations.requestBlock, style: const TextStyle(fontSize: 16))),
        body: Container(
            padding: const EdgeInsets.all(10),
            child: Wrap(children: [
              Row(children: [
                const SizedBox(width: 8),
                Text(localizations.enable),
                const SizedBox(width: 10),
                SwitchWidget(
                    scale: 0.8,
                    value: widget.requestBlockManager.enabled,
                    onChanged: (value) {
                      widget.requestBlockManager.enabled = value;
                      widget.requestBlockManager.flushConfig();
                    }),
                const Expanded(child: SizedBox()),
                TextButton.icon(
                    icon: const Icon(Icons.add, size: 20), onPressed: showEdit, label: Text(localizations.add)),
                const SizedBox(width: 5),
              ]),
              const SizedBox(height: 10),
              Container(
                  height: 600,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
                  child: Column(children: [
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(width: 15),
                        const Expanded(child: Text('URL', style: TextStyle(fontSize: 14))),
                        SizedBox(width: 60, child: Text(localizations.enable, style: const TextStyle(fontSize: 14))),
                        SizedBox(width: 75, child: Text(localizations.action, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                    const Divider(thickness: 0.5),
                    Expanded(
                        child: ListView.builder(
                            itemCount: widget.requestBlockManager.list.length, itemBuilder: (_, index) => row(index)))
                  ]))
            ])));
  }

  Widget row(int index) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    bool isCN = localizations.localeName == 'zh';
    var list = widget.requestBlockManager.list;

    return InkWell(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: primaryColor.withOpacity(0.3),
        onLongPress: () => showMenus(index),
        onTap: () => showEdit(index),
        child: Container(
            color: index.isEven ? Colors.grey.withOpacity(0.1) : null,
            height: 38,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(child: Text(list[index].url.fixAutoLines(), style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 5),
                SwitchWidget(
                    scale: 0.65,
                    value: list[index].enabled,
                    onChanged: (val) {
                      list[index].enabled = val;
                      setState(() {
                        widget.requestBlockManager.flushConfig();
                      });
                    }),
                const SizedBox(width: 5),
                SizedBox(
                    width: 85,
                    child: Text(isCN ? list[index].type.label : list[index].type.name,
                        style: const TextStyle(fontSize: 13)))
              ],
            )));
  }

  //点击菜单
  showMenus(int index) {
    var list = widget.requestBlockManager.list;

    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        context: context,
        isScrollControlled: true,
        enableDrag: true,
        builder: (ctx) {
          return Wrap(children: [
            BottomSheetItem(text: localizations.edit, onPressed: () => showEdit(index)),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: list[index].enabled ? localizations.disabled : localizations.enable,
                onPressed: () {
                  list[index].enabled = !list[index].enabled;
                  setState(() {
                    widget.requestBlockManager.flushConfig();
                  });
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: localizations.delete,
                onPressed: () async {
                  await widget.requestBlockManager.removeBlockRequest(index);
                  setState(() {});
                }),
            Container(color: Theme.of(context).hoverColor, height: 8),
            TextButton(
                child: Container(
                    height: 50,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(localizations.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(context).pop();
                }),
          ]);
        });
  }

  showEdit([int? index]) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return RequestBlockAddDialog(requestBlockManager: widget.requestBlockManager, index: index);
        }).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }
}

class RequestBlockAddDialog extends StatelessWidget {
  final RequestBlockManager requestBlockManager;
  final int? index;

  const RequestBlockAddDialog({super.key, required this.requestBlockManager, this.index});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = localizations.localeName == 'zh';

    GlobalKey formKey = GlobalKey<FormState>();
    RequestBlockItem item =
        index == null ? RequestBlockItem(true, '', BlockType.values.first) : requestBlockManager.list.elementAt(index!);
    bool enabled = item.enabled;
    return AlertDialog(
        scrollable: true,
        content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Form(
                key: formKey,
                child: Column(children: <Widget>[
                  SwitchWidget(title: localizations.enable, value: item.enabled, onChanged: (val) => enabled = val),
                  const SizedBox(height: 10),
                  TextFormField(
                      initialValue: item.url,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'URL',
                          hintText: 'https://example.com/*',
                          border: OutlineInputBorder()),
                      validator: (val) => val == null || val.trim().isEmpty ? localizations.cannotBeEmpty : null,
                      onSaved: (val) => item.url = val!.trim()),
                  const SizedBox(height: 15),
                  DropdownButtonFormField(
                      value: item.type,
                      decoration: InputDecoration(
                          isDense: true, labelText: localizations.type, border: const OutlineInputBorder()),
                      items: BlockType.values
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(isCN ? e.label : e.name, style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onSaved: (val) => item.type = val!,
                      onChanged: (val) {}),
                ]))),
        actions: [
          TextButton(child: Text(localizations.cancel), onPressed: () => Navigator.of(context).pop()),
          TextButton(
              child: Text(localizations.save),
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  return;
                }
                (formKey.currentState as FormState).save();

                item.enabled = enabled;
                item.urlReg = null;
                if (index != null) {
                  requestBlockManager.list[index!] = item;
                } else {
                  requestBlockManager.addBlockRequest(item);
                }
                requestBlockManager.flushConfig();
                Navigator.of(context).pop(item);
              }),
        ]);
  }
}
