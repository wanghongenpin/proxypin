import 'package:flutter/material.dart';

class Buttons {
  static ButtonStyle get buttonStyle => ButtonStyle(
      padding: WidgetStateProperty.all<EdgeInsets>(EdgeInsets.symmetric(horizontal: 15, vertical: 8)),
      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
}
