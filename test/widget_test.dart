import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login/main.dart';

void main() {
  testWidgets('AuthScreen smoke test', (WidgetTester tester) async {
    // Carga tu aplicación
    await tester.pumpWidget(MyApp());

    // Verifica que aparezca el botón o texto de inicio de sesión
    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('Correo Electrónico'), findsOneWidget);
  });
}