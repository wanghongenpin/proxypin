import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/desktop/request/request_editor.dart';

class BreakpointExecutor extends StatefulWidget {
  final int? windowId;
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
    this.windowId,
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

    return RequestEditor(
      request: request,
      source: RequestEditorSource.breakpointRequest,
      onExecuteRequest: (newRequest) async {
        await DesktopMultiWindow.invokeMethod(0, 'resumeRequest', {
          'requestId': widget.requestId,
          'request': newRequest?.toJson(),
        });
        if (widget.windowId != null) {
          WindowController.fromWindowId(widget.windowId!).close();
        }
      },
    );
  }

  Widget _buildResponseBody() {
    return RequestEditor(
      request: request,
      response: response,
      source: RequestEditorSource.breakpointResponse,
      onExecuteResponse: (newResponse) async {
        await DesktopMultiWindow.invokeMethod(0, 'resumeResponse', {
          'requestId': widget.requestId,
          'response': newResponse?.toJson(),
        });
        if (widget.windowId != null) {
          WindowController.fromWindowId(widget.windowId!).close();
        }
      },
    );
  }

}
