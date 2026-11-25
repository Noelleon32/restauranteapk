import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificacionService {
  NotificacionService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> inicializar() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> mostrarCambioEstado({
    required int idNotificacion,
    required Object numeroPedido,
    required String nuevoEstado,
  }) async {
    String mensaje;
    switch (nuevoEstado) {
      case 'En preparación':
        mensaje = 'Tu pedido #$numeroPedido ya está en cocina preparándose.';
        break;
      case 'Listo':
        mensaje = '¡Tu pedido #$numeroPedido está listo para recoger/entregar!';
        break;
      case 'Entregado':
        mensaje = 'Tu pedido #$numeroPedido fue entregado. ¡Buen provecho!';
        break;
      case 'Cancelado':
        mensaje = 'Tu pedido #$numeroPedido ha sido cancelado.';
        break;
      default:
        mensaje = 'Tu pedido #$numeroPedido cambió a: $nuevoEstado';
    }

    const androidDetails = AndroidNotificationDetails(
      'canal_pedidos',
      'Estado de Pedidos',
      channelDescription: 'Avisos cuando un pedido avanza en cocina',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    await _plugin.show(
      idNotificacion,
      'Actualización de tu pedido',
      mensaje,
      const NotificationDetails(android: androidDetails),
    );
  }
}
