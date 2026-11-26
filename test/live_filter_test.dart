import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/model/search_model.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/mobile/request/request_sequence.dart';
import 'package:proxypin/utils/listenable_list.dart';

HttpRequest request(String url) => HttpRequest(HttpMethod.get, url)..hostAndPort = HostAndPort.of(url);

HttpResponse respond(HttpRequest r, String type) {
  final res = HttpResponse(HttpStatus.ok)
    ..headers.set('Content-Type', type)
    ..request = r;
  r.response = res;
  return res;
}

void main() {
  testWidgets('live capture: -type:image drops image once its response arrives', (tester) async {
    final key = GlobalKey<RequestSequenceState>();
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: RequestSequence(
                key: key,
                container: ListenableList<HttpRequest>(),
                proxyServer: ProxyServer(Configuration.fromJson({})),
                selectionController: MultiSelectController()))));
    await tester.pumpAndSettle(); // 等本地化资源加载完
    final state = key.currentState!;
    state.search(SearchModel('-type:image'));

    final img = request('https://pica.zhimg.com/a.jpg');
    final api = request('https://www.zhihu.com/api/v4/x');
    // 实时抓包：先到请求（此时无响应，-type:image 无法判断而放行）
    state.add(img);
    state.add(api);
    expect(state.view, containsAll([img, api]));

    state.addResponse(respond(img, 'image/jpeg'));
    state.addResponse(respond(api, 'application/json'));
    await tester.pump(const Duration(seconds: 1));
    expect(state.view.contains(img), isFalse);
    expect(state.view.contains(api), isTrue);
  });
}
