/// 通过 VM Service 切换详情面板 Tab：dart run test/select_tab.dart <wsUri> <index>
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  var wsUri = args[0];
  var index = args[1];
  var service = await vmServiceConnectUri(wsUri);
  var vm = await service.getVM();
  var isolateId = vm.isolates!.firstWhere((i) => i.name == 'main').id!;
  var isolate = await service.getIsolate(isolateId);
  var panelLib = isolate.libraries!.firstWhere((l) => l.uri!.endsWith('ui/content/panel.dart'));
  var result = await service.evaluate(
      isolateId, panelLib.id!, 'NetworkTabController.currentKey?.currentState?._tabController.animateTo($index)');
  print(result.json);
  await service.dispose();
}
