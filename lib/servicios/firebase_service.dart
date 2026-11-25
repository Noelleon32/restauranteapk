import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_database/firebase_database.dart';

typedef Registro = Map<String, dynamic>;

enum ResultadoCancelacion {
  cancelado,
  tiempoExcedido,
  noPendiente,
  noEncontrado,
}

class FirebaseService {
  FirebaseService._();

  static final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// Minutos que tiene el cliente para cancelar un pedido Pendiente.
  static const int minutosCancelacion = 5;

  // -------------------------------------------------------------------------
  // AYUDAS INTERNAS
  // -------------------------------------------------------------------------
  static dynamic _limpiar(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _limpiar(val)));
    }
    if (v is List) return v.map(_limpiar).toList();
    return v;
  }

  static List<Registro> _lista(Object? valor) {
    if (valor == null) return [];
    final mapa = valor as Map;
    return mapa.entries.map((e) {
      final datos = _limpiar(e.value) as Map<String, dynamic>;
      return <String, dynamic>{...datos, 'id': e.key.toString()};
    }).toList();
  }

  // El correo no puede tener "." en una clave de Realtime Database.
  static String _clave(String email) =>
      email.trim().toLowerCase().replaceAll('.', ',');

  static String _hash(String p) => sha256.convert(utf8.encode(p)).toString();

  // -------------------------------------------------------------------------
  // DATOS BASE
  // -------------------------------------------------------------------------
  static Future<void> inicializarDatosBase() async {
    final snap = await _db.child('categorias').get();
    if (!snap.exists) {
      const base = [
        {'nombre': 'Especiales', 'imagen': 'imagenes/Especiales.png'},
        {'nombre': 'Comidas', 'imagen': 'imagenes/Comidas.png'},
        {'nombre': 'Bebidas', 'imagen': 'imagenes/Bebidas.png'},
        {'nombre': 'Postres', 'imagen': 'imagenes/Postres.png'},
      ];
      for (var i = 0; i < base.length; i++) {
        await _db.child('categorias').push().set({...base[i], 'orden': i});
      }
    }

    final usuariosBase = {
      'admin@admin,com': {
        'email': 'admin@admin.com',
        'password': _hash('123'),
        'rol': 'admin',
      },
      'cocina@cocina,com': {
        'email': 'cocina@cocina.com',
        'password': _hash('123'),
        'rol': 'cocina',
      },
    };

    for (final entry in usuariosBase.entries) {
      final ref = _db.child('usuarios/${entry.key}');
      if (!(await ref.get()).exists) {
        await ref.set(entry.value);
      }
    }
  }

  // -------------------------------------------------------------------------
  // USUARIOS
  // -------------------------------------------------------------------------
  static Future<Registro?> iniciarSesion(String email, String password) async {
    final clave = _clave(email);
    if (clave.isEmpty || clave.contains('/')) return null;

    final snap = await _db.child('usuarios/$clave').get();
    if (!snap.exists) return null;
    final data = _limpiar(snap.value) as Map<String, dynamic>;
    if (data['password'] != _hash(password)) return null;

    return {
      'id': clave,
      'email': data['email'],
      'rol': data['rol'] ?? 'cliente',
    };
  }

  static Future<bool> registrarUsuario(String email, String password) async {
    final clave = _clave(email);
    if (clave.isEmpty || clave.contains('/')) return false;

    final ref = _db.child('usuarios/$clave');
    if ((await ref.get()).exists) return false;

    await ref.set({
      'email': email.trim().toLowerCase(),
      'password': _hash(password),
      'rol': 'cliente',
    });
    return true;
  }

  // -------------------------------------------------------------------------
  // CATEGORÍAS Y PLATOS
  // -------------------------------------------------------------------------
  static Future<List<Registro>> obtenerCategorias() async {
    final snap = await _db.child('categorias').get();
    final lista = _lista(snap.value);
    lista.sort(
      (a, b) => ((a['orden'] ?? 0) as num).compareTo((b['orden'] ?? 0) as num),
    );
    return lista;
  }

  static Future<List<Registro>> obtenerPlatos({String? categoriaId}) async {
    final snap = await _db.child('platos').get();
    var lista = _lista(snap.value);
    if (categoriaId != null) {
      lista = lista.where((p) => p['categoria_id'] == categoriaId).toList();
    }
    lista.sort(
      (a, b) => (a['nombre'] as String).toLowerCase().compareTo(
        (b['nombre'] as String).toLowerCase(),
      ),
    );
    return lista;
  }

  static Future<void> insertarPlato(Registro plato) async {
    await _db.child('platos').push().set(plato);
  }

  static Future<void> eliminarPlato(String id) async {
    await _db.child('platos/$id').remove();
  }

  // -------------------------------------------------------------------------
  // PEDIDOS
  // -------------------------------------------------------------------------
  static Future<int> _siguienteNumero(String contador) async {
    final res = await _db.child('contadores/$contador').runTransaction((valor) {
      final actual = (valor as int?) ?? 0;
      return Transaction.success(actual + 1);
    });
    return res.snapshot.value as int;
  }

  static Future<void> crearPedido({
    required String usuarioId,
    required String emailUsuario,
    required List<Registro> items,
    int? mesa,
  }) async {
    final total = items.fold<double>(
      0.0,
      (s, i) => s + (i['precio'] as num) * (i['cantidad'] as num),
    );
    final numero = await _siguienteNumero('pedidos');

    await _db.child('pedidos').push().set({
      'numero': numero,
      'usuario_id': usuarioId,
      'email': emailUsuario,
      'items': items,
      'mesa': mesa,
      'total': total,
      'estado': 'Pendiente',
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  static Stream<List<Registro>> streamPedidosUsuario(String usuarioId) {
    return _db.child('pedidos').onValue.map((evento) {
      final lista = _lista(evento.snapshot.value)
          .where((p) => p['usuario_id'] == usuarioId)
          .toList();
      lista.sort(
        (a, b) => (b['fecha'] as String).compareTo(a['fecha'] as String),
      );
      return lista;
    });
  }

  static Stream<List<Registro>> streamPedidosPorEstados(
    List<String> estados, {
    bool masAntiguosPrimero = true,
  }) {
    return _db.child('pedidos').onValue.map((evento) {
      final lista = _lista(evento.snapshot.value)
          .where((p) => estados.contains(p['estado']))
          .toList();
      lista.sort((a, b) {
        final c = (a['fecha'] as String).compareTo(b['fecha'] as String);
        return masAntiguosPrimero ? c : -c;
      });
      return lista;
    });
  }

  static Future<void> actualizarEstadoPedido(
    String pedidoId,
    String nuevoEstado,
  ) async {
    await _db.child('pedidos/$pedidoId/estado').set(nuevoEstado);
  }

  static Future<ResultadoCancelacion> cancelarPedido(
    String pedidoId,
    String usuarioId,
  ) async {
    final ref = _db.child('pedidos/$pedidoId');
    final snap = await ref.get();
    if (!snap.exists) return ResultadoCancelacion.noEncontrado;

    final data = _limpiar(snap.value) as Map<String, dynamic>;
    if (data['usuario_id'] != usuarioId) {
      return ResultadoCancelacion.noEncontrado;
    }
    if (data['estado'] != 'Pendiente') {
      return ResultadoCancelacion.noPendiente;
    }
    final creado = DateTime.tryParse(data['fecha'] as String);
    if (creado == null ||
        DateTime.now().difference(creado) >
            const Duration(minutes: minutosCancelacion)) {
      return ResultadoCancelacion.tiempoExcedido;
    }

    await ref.child('estado').set('Cancelado');
    return ResultadoCancelacion.cancelado;
  }

  // -------------------------------------------------------------------------
  // FACTURACIÓN
  // -------------------------------------------------------------------------
  static Future<Registro?> facturarPedido(String pedidoId) async {
    final ref = _db.child('pedidos/$pedidoId');
    final snap = await ref.get();
    if (!snap.exists) return null;

    final data = _limpiar(snap.value) as Map<String, dynamic>;
    if (data['estado'] == 'Facturado') return null;

    final numero = await _siguienteNumero('facturas');
    final fecha = DateTime.now().toIso8601String();

    await ref.update({
      'estado': 'Facturado',
      'factura_numero': numero,
      'factura_fecha': fecha,
    });
    return {'factura_numero': numero, 'factura_fecha': fecha};
  }
}
