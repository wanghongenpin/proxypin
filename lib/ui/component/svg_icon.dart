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
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 设计稿单色线条图标（assets/icons/ 下的 stroke SVG），用 [color] 整体着色
class SvgIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color color;

  const SvgIcon(this.name, {super.key, this.size = 17, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/$name.svg',
        width: size, height: size, colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
  }
}
