import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/api_service.dart';
class HealthyApi extends ApiService {
 @override Future<Map<String,dynamic>> getHealth() async => {'status':'ok'};
}
void main(){
 testWidgets('escritorio navega por los cuatro apartados', (tester) async {
  tester.view.physicalSize=const Size(1200,900);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home:DashboardScreen(api:HealthyApi())));
  await tester.pump(const Duration(milliseconds:300));
  for(final name in ['Bosques','Hundimiento','Desplazamiento','Dashboard']){
   await tester.tap(find.widgetWithText(ListTile,name));
   await tester.pump(const Duration(milliseconds:300));
   expect(tester.widget<ListTile>(find.widgetWithText(ListTile,name)).selected,isTrue);
   expect(tester.takeException(),isNull);
  }
 });
 testWidgets('movil abre menu y selecciona modulo sin desbordamiento', (tester) async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home:DashboardScreen(api:HealthyApi())));
  await tester.pump(const Duration(milliseconds:300));
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pump(const Duration(milliseconds:400));
  await tester.tap(find.widgetWithText(ListTile,'Hundimiento'));
  await tester.pump(const Duration(milliseconds:400));
  expect(find.text('Hundimiento'),findsWidgets);
  expect(tester.takeException(),isNull);
 });
}

