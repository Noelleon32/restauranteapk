import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notificacion_service.dart';

const String tareaRevisarPedidos = 'revisar_estado_pedidos';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == tareaRevisarPedidos) {
      await Firebase.initializeApp();
      await NotificacionService.inicializar();

      final prefs = await SharedPreferences.getInstance();
      final usuarioId = prefs.getString('sesion_usuario_id');
      final rol = prefs.getString('sesion_rol') ?? 'cliente';

      if (usuarioId == null || rol != 'cliente') return true;

      final snap = await FirebaseDatabase.instance.ref('pedidos').get();
      if (!snap.exists || snap.value == null) return true;

      final mapa = Map<String, dynamic>.from(snap.value as Map);
      for (final entry in mapa.entries) {
        final id = entry.key;
        final data = Map<String, dynamic>.from(entry.value as Map);

        if (data['usuario_id'] != usuarioId) continue;

        final estadoActual = (data['estado'] ?? '') as String;
        final clavePref = 'estado_pedido_$id';
        final estadoGuardado = prefs.getString(clavePref);

        if (estadoGuardado != null && estadoGuardado != estadoActual) {
          await NotificacionService.mostrarCambioEstado(
            idNotificacion: id.hashCode,
            numeroPedido: data['numero'] ?? id,
            nuevoEstado: estadoActual,
          );
        }
        await prefs.setString(clavePref, estadoActual);
      }
    }
    return true;
  });
}

class BackgroundPedidosService {
  BackgroundPedidosService._();

  static Future<void> iniciar() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'monitor_pedidos_unico',
      tareaRevisarPedidos,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> guardarSesion(String usuarioId, String rol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sesion_usuario_id', usuarioId);
    await prefs.setString('sesion_rol', rol);
  }

  static Future<void> limpiarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sesion_usuario_id');
    await prefs.remove('sesion_rol');
  }
}
