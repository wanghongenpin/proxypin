/// 热重载预览应用并刷新详情面板：dart run test/hot_reload.dart <wsUri>
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  var service = await vmServiceConnectUri(args[0]);
  var vm = await service.getVM();
  var isolateId = vm.isolates!.firstWhere((i) => i.name == 'main').id!;
  var report = await service.reloadSources(isolateId);
  print('reload: ${report.success}');
  var isolate = await service.getIsolate(isolateId);
  var panelLib = isolate.libraries!.firstWhere((l) => l.uri!.endsWith('ui/content/panel.dart'));
  await service.evaluate(isolateId, panelLib.id!, 'NetworkTabController.currentKey?.currentState?.changeState()');
  print('refreshed');
  await service.dispose();
}
