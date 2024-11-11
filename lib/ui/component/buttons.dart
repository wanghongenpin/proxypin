import 'package:flutter/material.dart';

class Buttons {
  static ButtonStyle get buttonStyle => ButtonStyle(
      padding: MaterialStateProperty.all<EdgeInsets>(EdgeInsets.symmetric(horizontal: 15, vertical: 8)),
      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
}
