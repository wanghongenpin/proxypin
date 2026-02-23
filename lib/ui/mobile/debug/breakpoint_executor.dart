import 'package:flutter/material.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/mobile/request/request_editor_source.dart';

class BreakpointExecutor extends StatefulWidget {
  final HttpRequest request;
  final HttpResponse? response;
  final String requestId;

  // false: intercept request, true: intercept response
  final bool isResponse;

  const BreakpointExecutor({
    super.key,
    required this.request,
    this.response,
    required this.requestId,
    required this.isResponse,
  });

  @override
  State<BreakpointExecutor> createState() => _BreakpointExecutorState();
}

class _BreakpointExecutorState extends State<BreakpointExecutor> {
  late HttpRequest request;
  late HttpResponse? response;

  @override
  void initState() {
    super.initState();
    request = widget.request;
    response = widget.response;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isResponse) {
      return _buildResponseBody();
    }

    return MobileRequestEditor(
      request: request,
      proxyServer: ProxyServer.current,
      source: RequestEditorSource.breakpointRequest,
      onExecuteRequest: (newRequest) async {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, newRequest);
        }
      },
    );
  }

  Widget _buildResponseBody() {
    return MobileRequestEditor(
      request: request,
      response: response,
      proxyServer: ProxyServer.current,
      source: RequestEditorSource.breakpointResponse,
      onExecuteResponse: (newResponse) async {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, newResponse);
        }
      },
    );
  }
}
