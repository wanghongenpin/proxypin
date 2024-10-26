import 'package:flutter/material.dart';
import 'package:proxypin/network/components/rewrite/request_rewrite_manager.dart';
import 'package:proxypin/network/components/rewrite/rewrite_rule.dart';
import 'package:proxypin/network/http/http.dart';

import 'toolbar/setting/request_rewrite.dart';

/// 显示请求重写对话框
showRequestRewriteDialog(BuildContext context, HttpRequest request) async {
  bool isRequest = request.response == null;
  var requestRewrites = await RequestRewriteManager.instance;

  var ruleType = isRequest ? RuleType.requestReplace : RuleType.responseReplace;
  var rule = requestRewrites.getRequestRewriteRule(request, ruleType);
  var rewriteItems = await requestRewrites.getRewriteItems(rule);
  if (!context.mounted) return;

  showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RewriteRuleEdit(rule: rule, items: rewriteItems, request: request));
}
