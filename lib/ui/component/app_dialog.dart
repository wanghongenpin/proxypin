import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.title,
    required this.message,
  });

  final String? title;
  final String message;

  factory AppAlertDialog.fromErr(({String type, String? message}) err) => AppAlertDialog(
        title: err.message == null ? null : err.type,
        message: err.message ?? err.type,
      );

  Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);

    return AlertDialog(
      title: title != null ? Text(title!) : null,
      content: SingleChildScrollView(
        child: SizedBox(
          width: 468,
          child: Text(message),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(localizations.okButtonLabel),
        ),
      ],
    );
  }
}

enum AlertType {
  info,
  error,
  success;

  ToastificationType get _toastificationType => switch (this) {
        success => ToastificationType.success,
        error => ToastificationType.error,
        info => ToastificationType.info,
      };
}

class CustomToast extends StatelessWidget {
  const CustomToast(
    this.message, {
    super.key,
    this.type = AlertType.info,
    this.icon,
    this.duration = const Duration(seconds: 3),
  });

  const CustomToast.error(
    this.message, {
    super.key,
    this.duration = const Duration(seconds: 5),
  })  : type = AlertType.error,
        icon = Icons.error;

  const CustomToast.success(
    this.message, {
    super.key,
    this.duration = const Duration(seconds: 3),
  })  : type = AlertType.success,
        icon = Icons.check_circle;

  final String message;
  final AlertType type;
  final IconData? icon;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(message)),
        ],
      ),
    );
  }

  void show(BuildContext context) {
    toastification.show(
      context: context,
      title: Text(message),
      icon: icon == null ? null : Icon(icon),
      type: type._toastificationType,
      alignment: Alignment.bottomLeft,
      autoCloseDuration: duration,
      style: ToastificationStyle.flat,
      pauseOnHover: true,
      showProgressBar: false,
      dragToClose: true,
      closeOnClick: true,
      closeButton: ToastCloseButton(showType: CloseButtonShowType.onHover),
    );
  }
}
