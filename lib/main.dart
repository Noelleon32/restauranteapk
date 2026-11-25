import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;

import 'servicios/notificacion_service.dart';
import 'servicios/firebase_service.dart';

const Color vino = Color(0xFF7B1E2B);
const Color fondoCrema = Color(0xFFFAF6F0);

void mostrarError(BuildContext context, String titulo, String mensaje) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

bool emailValido(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

String dinero(num valor) => '\$${valor.toStringAsFixed(2)}';

const int totalMesas = 20;

String descripcionMesa(Object? mesa) =>
    mesa == null ? 'Para llevar' : 'Mesa $mesa';

int minutosRestantesCancelar(Registro p) {
  if (p['estado'] != 'Pendiente') return 0;
  final creado = DateTime.tryParse(p['fecha'] as String);
  if (creado == null) return 0;
  final restante =
      Duration(minutes: FirebaseService.minutosCancelacion) -
      DateTime.now().difference(creado);
  if (restante.inSeconds <= 0) return 0;
  return (restante.inSeconds / 60).ceil();
}

String formatoFecha(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
}

// ---------------------------------------------------------------------------
// BARRA DE ESTADO DEL PEDIDO
// ---------------------------------------------------------------------------

class BarraEstadoPedido extends StatelessWidget {
  final String estado;

  const BarraEstadoPedido({super.key, required this.estado});

  static const List<Registro> _pasos = [
    {'estado': 'Pendiente', 'label': 'Recibido', 'icon': Icons.receipt_long},
    {'estado': 'En preparación', 'label': 'Cocina', 'icon': Icons.soup_kitchen},
    {'estado': 'Listo', 'label': 'Listo', 'icon': Icons.notifications_active},
    {'estado': 'Entregado', 'label': 'Entregado', 'icon': Icons.check_circle},
  ];

  int _indiceActual() {
    if (estado == 'Facturado') return 3;
    final idx = _pasos.indexWhere((p) => p['estado'] == estado);
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    if (estado == 'Cancelado') {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red, size: 18),
            SizedBox(width: 8),
            Text(
              'Pedido cancelado',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final actual = _indiceActual();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      child: Row(
        children: List.generate(_pasos.length * 2 - 1, (i) {
          if (i.isEven) {
            final pasoIdx = i ~/ 2;
            final paso = _pasos[pasoIdx];
            final completado = pasoIdx <= actual;
            final esElActual = pasoIdx == actual;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: completado ? vino : Colors.grey.shade300,
                    shape: BoxShape.circle,
                    boxShadow: esElActual
                        ? [
                            BoxShadow(
                              color: vino.withValues(alpha: 0.35),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    paso['icon'] as IconData,
                    size: 16,
                    color: completado ? Colors.white : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  paso['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: esElActual
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: completado ? vino : Colors.grey.shade600,
                  ),
                ),
              ],
            );
          }

          final lineaIdx = i ~/ 2;
          final lineaActiva = lineaIdx < actual;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.only(bottom: 16),
              color: lineaActiva ? vino : Colors.grey.shade300,
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SESIÓN Y CARRITO
// ---------------------------------------------------------------------------

class Sesion {
  static String? usuarioId;
  static String email = '';
  static String rol = 'cliente';

  static bool get esAdmin => rol == 'admin';
  static bool get esCocina => rol == 'cocina';

  static void cerrar() {
    usuarioId = null;
    email = '';
    rol = 'cliente';
  }
}

final ValueNotifier<int> pedidosRefresh = ValueNotifier<int>(0);

class ItemCarrito {
  final String platoId;
  final String nombre;
  final double precio;
  int cantidad;

  ItemCarrito({
    required this.platoId,
    required this.nombre,
    required this.precio,
    this.cantidad = 1,
  });
}

class Carrito extends ChangeNotifier {
  Carrito._();
  static final Carrito instancia = Carrito._();

  final Map<String, ItemCarrito> _items = {};

  List<ItemCarrito> get items => _items.values.toList();
  bool get vacio => _items.isEmpty;
  int get cantidadTotal => _items.values.fold(0, (s, i) => s + i.cantidad);
  double get total =>
      _items.values.fold(0.0, (s, i) => s + i.precio * i.cantidad);

  void agregar(String platoId, String nombre, double precio) {
    final existente = _items[platoId];
    if (existente != null) {
      existente.cantidad++;
    } else {
      _items[platoId] = ItemCarrito(
        platoId: platoId,
        nombre: nombre,
        precio: precio,
      );
    }
    notifyListeners();
  }

  void quitarUno(String platoId) {
    final existente = _items[platoId];
    if (existente == null) return;
    if (existente.cantidad > 1) {
      existente.cantidad--;
    } else {
      _items.remove(platoId);
    }
    notifyListeners();
  }

  void eliminar(String platoId) {
    _items.remove(platoId);
    notifyListeners();
  }

  void limpiar() {
    _items.clear();
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseService.inicializarDatosBase();
  await NotificacionService.inicializar();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Restaurante',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: vino),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => AuthScreen(),
        '/register': (context) => RegisterScreen(),
        '/admin': (context) => Sesion.esAdmin
            ? AdminPlatosScreen()
            : Scaffold(
                appBar: AppBar(title: Text('Acceso restringido')),
                body: Center(
                  child: Text('Solo el administrador puede entrar aquí.'),
                ),
              ),
        '/admin-pedidos': (context) =>
            Sesion.esAdmin ? AdminPedidosScreen() : accesoRestringido(),
        '/cocina': (context) => (Sesion.esCocina || Sesion.esAdmin)
            ? const CocinaPedidosScreen()
            : accesoRestringido(),
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool isLoggedIn = false;

  void register() async {
    final result = await Navigator.pushNamed(context, '/register');
    if (!mounted) return;
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cuenta creada. Ya puedes iniciar sesión.')),
      );
    }
  }

  void login() async {
    final enteredEmail = emailController.text;
    final enteredPassword = passwordController.text;

    final usuario = await FirebaseService.iniciarSesion(
      enteredEmail,
      enteredPassword,
    );
    if (!mounted) return;

    if (usuario != null) {
      Sesion.usuarioId = usuario['id'] as String?;
      Sesion.email = (usuario['email'] as String?) ?? enteredEmail.trim();
      Sesion.rol = (usuario['rol'] as String?) ?? 'cliente';
      setState(() {
        isLoggedIn = true;
      });
    } else {
      mostrarError(
        context,
        'Error de inicio de sesión',
        'Credenciales incorrectas. Verifica tu correo y contraseña.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn) {
      if (Sesion.esCocina) {
        return const CocinaPedidosScreen();
      }
      return HomeShell();
    } else {
      return Scaffold(
        appBar: AppBar(title: const Text('Inicio de Sesión o Registro')),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Image.asset(
                      'imagenes/logo.png',
                      height: 120,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.restaurant, size: 100, color: vino),
                    ),
                    SizedBox(height: 20),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vino,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: login,
                        child: Text('Iniciar Sesión'),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: register,
                      child: Text('¿No tienes una cuenta? Regístrate aquí.'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
}

class RegisterScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextEditingController registerEmailController = TextEditingController();
    TextEditingController registerPasswordController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: Text('Registro'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 20.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextField(
                    controller: registerEmailController,
                    decoration: InputDecoration(
                      labelText: 'Correo Electrónico',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  TextField(
                    controller: registerPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    obscureText: true,
                  ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vino,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final registerEmail = registerEmailController.text
                            .trim();
                        final registerPassword =
                            registerPasswordController.text;

                        if (!emailValido(registerEmail)) {
                          mostrarError(
                            context,
                            'Correo inválido',
                            'Ingresa un correo válido.',
                          );
                          return;
                        }
                        if (registerPassword.length < 6) {
                          mostrarError(
                            context,
                            'Contraseña débil',
                            'La contraseña debe tener al menos 6 caracteres.',
                          );
                          return;
                        }

                        final creado = await FirebaseService.registrarUsuario(
                          registerEmail,
                          registerPassword,
                        );
                        if (!context.mounted) return;

                        if (creado) {
                          Navigator.pop(context, true);
                        } else {
                          mostrarError(
                            context,
                            'Correo ya registrado',
                            'Ya existe una cuenta con ese correo.',
                          );
                        }
                      },
                      child: Text('Registrarse'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  @override
  _HomeShellState createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int indice = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: indice,
        children: [
          InicioScreen(onVerMenu: () => setState(() => indice = 1)),
          MenuScreen(),
          PedidosScreen(),
          PerfilScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indice,
        onDestinationSelected: (i) => setState(() => indice = i),
        backgroundColor: Colors.white,
        indicatorColor: Color(0x1F7B1E2B),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: vino),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu, color: vino),
            label: 'Menú',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: vino),
            label: 'Pedidos',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: vino),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class InicioScreen extends StatelessWidget {
  final VoidCallback onVerMenu;
  InicioScreen({required this.onVerMenu});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant, size: 120, color: vino),
              SizedBox(height: 20),
              Text(
                'RESTAURANTE',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: vino,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Disfruta nuestros mejores platos',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 30),
              SizedBox(
                width: 240,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vino,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onVerMenu,
                  child: Text('Ver menú'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PEDIDOS: historial del usuario
// ---------------------------------------------------------------------------
class PedidosScreen extends StatefulWidget {
  @override
  _PedidosScreenState createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  Future<void> _cancelar(Registro p) async {
    final usuarioId = Sesion.usuarioId;
    if (usuarioId == null) return;
    final numero = p['numero'] ?? p['id'];

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar pedido'),
        content: Text('¿Seguro que quieres cancelar el pedido #$numero?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final resultado = await FirebaseService.cancelarPedido(
      p['id'] as String,
      usuarioId,
    );
    if (!mounted) return;

    switch (resultado) {
      case ResultadoCancelacion.cancelado:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pedido #$numero cancelado.')));
      case ResultadoCancelacion.tiempoExcedido:
        mostrarError(
          context,
          'No se puede cancelar',
          'Ya pasaron ${FirebaseService.minutosCancelacion} minutos desde que hiciste el pedido.',
        );
      case ResultadoCancelacion.noPendiente:
        mostrarError(
          context,
          'No se puede cancelar',
          'El pedido ya fue procesado por el restaurante.',
        );
      case ResultadoCancelacion.noEncontrado:
        mostrarError(context, 'Error', 'No se encontró el pedido.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarioId = Sesion.usuarioId;
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: Text('Mis Pedidos'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
      ),
      body: usuarioId == null
          ? Center(
              child: Text(
                'Aún no has hecho pedidos.',
                style: TextStyle(fontSize: 18),
              ),
            )
          : StreamBuilder<List<Registro>>(
              stream: FirebaseService.streamPedidosUsuario(usuarioId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final pedidos = snapshot.data ?? [];
                if (pedidos.isEmpty) {
                  return Center(
                    child: Text(
                      'Aún no has hecho pedidos.',
                      style: TextStyle(fontSize: 18),
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: pedidos.length,
                  itemBuilder: (context, index) {
                    final p = pedidos[index];
                    final items = p['items'] as List;
                    final minutosRestantes = minutosRestantesCancelar(p);
                    final numero = p['numero'] ?? p['id'];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: BarraEstadoPedido(
                              estado: p['estado'] as String,
                            ),
                          ),
                          ExpansionTile(
                            title: Text(
                              'Pedido #$numero',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${formatoFecha(p['fecha'] as String)} · ${descripcionMesa(p['mesa'])} · ${p['estado']}',
                            ),
                            trailing: Text(
                              dinero(p['total'] as num),
                              style: TextStyle(
                                color: vino,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            children: [
                              ...items.map<Widget>((it) {
                                final item = it as Map;
                                final subtotal =
                                    (item['precio'] as num) *
                                    (item['cantidad'] as num);
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    '${item['cantidad']} x ${item['nombre']}',
                                  ),
                                  trailing: Text(dinero(subtotal)),
                                );
                              }),
                              if (minutosRestantes > 0)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      icon: Icon(Icons.cancel_outlined),
                                      label: Text(
                                        'Cancelar pedido (quedan $minutosRestantes min)',
                                      ),
                                      onPressed: () => _cancelar(p),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// COCINA / DESPACHO: PROCESAR ESTADOS DE LOS PEDIDOS
// ---------------------------------------------------------------------------
class CocinaPedidosScreen extends StatefulWidget {
  const CocinaPedidosScreen({super.key});

  @override
  State<CocinaPedidosScreen> createState() => _CocinaPedidosScreenState();
}

class _CocinaPedidosScreenState extends State<CocinaPedidosScreen> {
  Registro? _siguienteAccion(String estadoActual) {
    switch (estadoActual) {
      case 'Pendiente':
        return {
          'nuevoEstado': 'En preparación',
          'texto': 'Iniciar preparación',
          'icono': Icons.soup_kitchen,
          'color': Colors.orange.shade800,
        };
      case 'En preparación':
        return {
          'nuevoEstado': 'Listo',
          'texto': 'Marcar como Listo',
          'icono': Icons.notifications_active,
          'color': Colors.blue.shade700,
        };
      case 'Listo':
        return {
          'nuevoEstado': 'Entregado',
          'texto': 'Confirmar Entrega',
          'icono': Icons.check_circle,
          'color': Colors.green.shade700,
        };
      default:
        return null;
    }
  }

  Future<void> _cambiarEstado(
    String pedidoId,
    Object? numero,
    String nuevoEstado,
  ) async {
    await FirebaseService.actualizarEstadoPedido(pedidoId, nuevoEstado);
    if (!mounted) return;
    pedidosRefresh.value++;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pedido #$numero actualizado a "$nuevoEstado"'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: const Text('Cocina y Despacho'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Sesion.cerrar();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => AuthScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Registro>>(
        stream: FirebaseService.streamPedidosPorEstados(const [
          'Pendiente',
          'En preparación',
          'Listo',
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final pedidos = snapshot.data ?? [];
          if (pedidos.isEmpty) {
            return const Center(
              child: Text(
                'No hay pedidos pendientes en cocina.',
                style: TextStyle(fontSize: 18),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              final p = pedidos[index];
              final items = p['items'] as List;
              final estado = p['estado'] as String;
              final accion = _siguienteAccion(estado);
              final numero = p['numero'] ?? p['id'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pedido #$numero · ${descripcionMesa(p['mesa'])}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: vino,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              estado,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(formatoFecha(p['fecha'] as String)),
                      BarraEstadoPedido(estado: estado),
                      const Divider(height: 20),
                      ...items.map<Widget>((it) {
                        final item = it as Map;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${item['cantidad']} x ${item['nombre']}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }),
                      if (accion != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accion['color'] as Color,
                              foregroundColor: Colors.white,
                            ),
                            icon: Icon(accion['icono'] as IconData),
                            label: Text(accion['texto'] as String),
                            onPressed: () => _cambiarEstado(
                              p['id'] as String,
                              numero,
                              accion['nuevoEstado'] as String,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PERFIL
// ---------------------------------------------------------------------------
class PerfilScreen extends StatefulWidget {
  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle, size: 100, color: vino),

              const SizedBox(height: 20),

              if (Sesion.esAdmin) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vino,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Administrar Platos'),
                  onPressed: () {
                    Navigator.pushNamed(context, '/admin');
                  },
                ),

                const SizedBox(height: 15),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vino,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Pedidos y facturación'),
                  onPressed: () {
                    Navigator.pushNamed(context, '/admin-pedidos');
                  },
                ),

                const SizedBox(height: 15),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vino,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.soup_kitchen),
                  label: const Text('Panel de Cocina'),
                  onPressed: () {
                    Navigator.pushNamed(context, '/cocina');
                  },
                ),
              ],

              const SizedBox(height: 25),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
                onPressed: () {
                  Sesion.cerrar();
                  Carrito.instancia.limpiar();

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => AuthScreen()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CARRITO
// ---------------------------------------------------------------------------

class BotonCarrito extends StatelessWidget {
  const BotonCarrito({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Carrito.instancia,
      builder: (context, _) {
        final n = Carrito.instancia.cantidadTotal;
        return IconButton(
          tooltip: 'Ver pedido',
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: const Icon(Icons.shopping_cart_outlined),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CarritoScreen()),
          ),
        );
      },
    );
  }
}

class CarritoScreen extends StatefulWidget {
  const CarritoScreen({super.key});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  bool _enviando = false;
  bool _paraLlevar = false;
  int? _mesa;

  Future<void> _confirmar() async {
    final carrito = Carrito.instancia;
    if (carrito.vacio) return;

    final usuarioId = Sesion.usuarioId;
    if (usuarioId == null) {
      mostrarError(
        context,
        'Sesión no válida',
        'Vuelve a iniciar sesión para hacer un pedido.',
      );
      return;
    }

    if (!_paraLlevar && _mesa == null) {
      mostrarError(
        context,
        'Falta la mesa',
        'Selecciona el número de mesa o elige "Para llevar".',
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _enviando = true);

    try {
      final itemsJson = carrito.items
          .map(
            (i) => {
              'plato_id': i.platoId,
              'nombre': i.nombre,
              'precio': i.precio,
              'cantidad': i.cantidad,
            },
          )
          .toList();

      await FirebaseService.crearPedido(
        usuarioId: usuarioId,
        emailUsuario: Sesion.email,
        items: itemsJson,
        mesa: _paraLlevar ? null : _mesa,
      );

      carrito.limpiar();
      pedidosRefresh.value++;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pedido realizado. Míralo en la pestaña Pedidos.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      mostrarError(
        context,
        'Error',
        'No se pudo registrar el pedido. Inténtalo de nuevo.',
      );
    }
  }

  Future<void> _vaciar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar pedido'),
        content: const Text('¿Quitar todos los platos del pedido?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (confirmar == true) Carrito.instancia.limpiar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: const Text('Mi Pedido'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
        actions: [
          ListenableBuilder(
            listenable: Carrito.instancia,
            builder: (context, _) => Carrito.instancia.vacio
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Vaciar pedido',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: _vaciar,
                  ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Carrito.instancia,
        builder: (context, _) {
          final carrito = Carrito.instancia;
          if (carrito.vacio) {
            return const Center(
              child: Text(
                'Tu pedido está vacío.',
                style: TextStyle(fontSize: 18),
              ),
            );
          }
          final items = carrito.items;
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(
                          item.nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${dinero(item.precio)} c/u  ·  ${dinero(item.precio * item.cantidad)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              color: vino,
                              onPressed: () => carrito.quitarUno(item.platoId),
                            ),
                            Text(
                              '${item.cantidad}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              color: vino,
                              onPressed: () => carrito.agregar(
                                item.platoId,
                                item.nombre,
                                item.precio,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: vino,
                          selectedForegroundColor: Colors.white,
                        ),
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.table_restaurant),
                            label: Text('En mesa'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.takeout_dining),
                            label: Text('Para llevar'),
                          ),
                        ],
                        selected: {_paraLlevar},
                        onSelectionChanged: (s) =>
                            setState(() => _paraLlevar = s.first),
                      ),
                      if (!_paraLlevar) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _mesa,
                          decoration: const InputDecoration(
                            labelText: 'Número de mesa',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: List.generate(
                            totalMesas,
                            (i) => DropdownMenuItem<int>(
                              value: i + 1,
                              child: Text('Mesa ${i + 1}'),
                            ),
                          ),
                          onChanged: (v) => setState(() => _mesa = v),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            dinero(carrito.total),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: vino,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: vino,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _enviando ? null : _confirmar,
                          child: _enviando
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Confirmar pedido'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: const Text('Menú - Restaurante'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
        actions: const [BotonCarrito()],
      ),
      body: FutureBuilder<List<Registro>>(
        future: FirebaseService.obtenerCategorias(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categorias = snapshot.data!;
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
            ),
            itemCount: categorias.length,
            itemBuilder: (context, index) {
              final cat = categorias[index];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlatosCategoriaScreen(
                      categoriaId: cat['id'] as String,
                      nombre: cat['nombre'] as String,
                    ),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      (cat['imagen'] as String?) != null
                          ? Image.asset(
                              cat['imagen'] as String,
                              height: 100,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.fastfood,
                                size: 50,
                                color: vino,
                              ),
                            )
                          : const Icon(Icons.fastfood, size: 50, color: vino),
                      const SizedBox(height: 10),
                      Text(
                        cat['nombre'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: vino,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PlatosCategoriaScreen extends StatelessWidget {
  final String categoriaId;
  final String nombre;
  const PlatosCategoriaScreen({
    super.key,
    required this.categoriaId,
    required this.nombre,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: Text(nombre),
        backgroundColor: vino,
        foregroundColor: Colors.white,
        actions: const [BotonCarrito()],
      ),
      body: FutureBuilder<List<Registro>>(
        future: FirebaseService.obtenerPlatos(categoriaId: categoriaId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text('No hay platos registrados en esta categoría.'),
            );
          }
          final platos = snapshot.data!;
          return ListView.builder(
            itemCount: platos.length,
            itemBuilder: (context, index) {
              final plato = platos[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(
                    plato['nombre'],
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plato['descripcion']),
                      SizedBox(height: 4),
                      Text(
                        '\$${(plato['precio'] as num).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: vino,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Agregar al pedido',
                    icon: Icon(Icons.add_circle, color: vino, size: 32),
                    onPressed: () {
                      Carrito.instancia.agregar(
                        plato['id'] as String,
                        plato['nombre'] as String,
                        (plato['precio'] as num).toDouble(),
                      );
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${plato['nombre']} agregado al pedido',
                          ),
                          duration: Duration(seconds: 2),
                          action: SnackBarAction(
                            label: 'Ver',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CarritoScreen(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PANTALLA DE ADMINISTRADOR: CREAR Y VER PLATOS
// ---------------------------------------------------------------------------
class AdminPlatosScreen extends StatefulWidget {
  @override
  _AdminPlatosScreenState createState() => _AdminPlatosScreenState();
}

class _AdminPlatosScreenState extends State<AdminPlatosScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _descripcionController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();

  List<Registro> _categorias = [];
  String? _categoriaId;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    final cats = await FirebaseService.obtenerCategorias();
    if (!mounted) return;
    setState(() {
      _categorias = cats;
      _categoriaId = cats.isNotEmpty ? cats.first['id'] as String : null;
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  void _guardarPlato() async {
    if (!_formKey.currentState!.validate() || _categoriaId == null) return;

    final catNombre =
        _categorias.firstWhere((c) => c['id'] == _categoriaId)['nombre']
            as String;

    final nuevoPlato = {
      'nombre': _nombreController.text.trim(),
      'descripcion': _descripcionController.text.trim(),
      'precio': double.parse(_precioController.text.replaceAll(',', '.')),
      'categoria_id': _categoriaId,
      'categoria': catNombre,
      'imagen': 'default.png',
    };

    await FirebaseService.insertarPlato(nuevoPlato);
    if (!mounted) return;

    _nombreController.clear();
    _descripcionController.clear();
    _precioController.clear();
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plato agregado exitosamente')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: Text('Administrar Platos'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    Text(
                      'Agregar Nuevo Plato',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: vino,
                      ),
                    ),
                    SizedBox(height: 10),
                    TextFormField(
                      controller: _nombreController,
                      decoration: InputDecoration(
                        labelText: 'Nombre del Plato',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Ingresa el nombre' : null,
                    ),
                    SizedBox(height: 10),
                    TextFormField(
                      controller: _descripcionController,
                      decoration: InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Ingresa la descripción' : null,
                    ),
                    SizedBox(height: 10),
                    TextFormField(
                      controller: _precioController,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Precio',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Ingresa un precio válido' : null,
                    ),
                    SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _categoriaId,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: _categorias
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c['id'] as String,
                              child: Text(c['nombre'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _categoriaId = val),
                      validator: (v) =>
                          v == null ? 'Selecciona una categoría' : null,
                    ),
                    SizedBox(height: 15),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vino,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _guardarPlato,
                      child: Text('Guardar Plato'),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 30, thickness: 2),
            Text(
              'Platos en Base de Datos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: vino,
              ),
            ),
            Expanded(
              flex: 2,
              child: FutureBuilder<List<Registro>>(
                future: FirebaseService.obtenerPlatos(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text('No hay platos guardados.'));
                  }
                  final platos = snapshot.data!;
                  return ListView.builder(
                    itemCount: platos.length,
                    itemBuilder: (context, index) {
                      final plato = platos[index];
                      return ListTile(
                        title: Text(plato['nombre']),
                        subtitle: Text(
                          '${plato['categoria'] ?? ''} - \$${(plato['precio'] as num).toStringAsFixed(2)}',
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await FirebaseService.eliminarPlato(
                              plato['id'] as String,
                            );
                            setState(() {});
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ADMIN: PROCESAR PEDIDOS A FACTURACIÓN
// ---------------------------------------------------------------------------

String numeroFactura(int id) => 'F-${id.toString().padLeft(4, '0')}';

Widget accesoRestringido() => Scaffold(
  appBar: AppBar(title: Text('Acceso restringido')),
  body: Center(child: Text('Solo el administrador puede entrar aquí.')),
);

class AdminPedidosScreen extends StatefulWidget {
  @override
  _AdminPedidosScreenState createState() => _AdminPedidosScreenState();
}

class _AdminPedidosScreenState extends State<AdminPedidosScreen> {
  bool _verFacturados = false;

  Future<void> _procesar(Registro p) async {
    final numero = p['numero'] ?? p['id'];
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Procesar a facturación'),
        content: Text(
          '¿Generar la factura del pedido #$numero (${descripcionMesa(p['mesa'])}) por ${dinero(p['total'] as num)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Procesar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final factura = await FirebaseService.facturarPedido(p['id'] as String);
    if (!mounted) return;
    pedidosRefresh.value++;

    if (factura == null) {
      mostrarError(
        context,
        'Pedido ya facturado',
        'Este pedido ya había sido procesado.',
      );
      return;
    }
    _mostrarFactura({
      ...p,
      'factura_numero': factura['factura_numero'],
      'factura_fecha': factura['factura_fecha'],
    });
  }

  void _mostrarFactura(Registro p) {
    final items = p['items'] as List;
    final numero = p['numero'] ?? p['id'];
    final factNum = (p['factura_numero'] as int?) ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Factura ${numeroFactura(factNum)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fecha: ${formatoFecha(p['factura_fecha'] as String)}'),
              Text('Pedido #$numero · ${descripcionMesa(p['mesa'])}'),
              Text('Cliente: ${p['email']}'),
              Divider(),
              ...items.map<Widget>((it) {
                final item = it as Map;
                final sub = (item['precio'] as num) * (item['cantidad'] as num);
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${item['cantidad']} x ${item['nombre']}  ·  ${dinero(sub)}',
                  ),
                );
              }),
              Divider(),
              Text(
                'TOTAL: ${dinero(p['total'] as num)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: vino,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Registro p) {
    final items = p['items'] as List;
    final facturado = p['estado'] == 'Facturado';
    final numero = p['numero'] ?? p['id'];
    final factNum = (p['factura_numero'] as int?) ?? 0;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pedido #$numero · ${descripcionMesa(p['mesa'])}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  dinero(p['total'] as num),
                  style: TextStyle(
                    color: vino,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text('${p['email']}'),
            Text(formatoFecha(p['fecha'] as String)),
            Divider(height: 20),
            ...items.map<Widget>((it) {
              final item = it as Map;
              final sub = (item['precio'] as num) * (item['cantidad'] as num);
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${item['cantidad']} x ${item['nombre']}  ·  ${dinero(sub)}',
                ),
              );
            }),
            SizedBox(height: 12),
            if (!facturado)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vino,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(Icons.receipt_long),
                  label: Text('Procesar a facturación'),
                  onPressed: () => _procesar(p),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.description_outlined),
                  label: Text('Ver factura ${numeroFactura(factNum)}'),
                  onPressed: () => _mostrarFactura(p),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoCrema,
      appBar: AppBar(
        title: Text('Pedidos y facturación'),
        backgroundColor: vino,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: vino,
                  selectedForegroundColor: Colors.white,
                ),
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('Pendientes')),
                  ButtonSegment<bool>(value: true, label: Text('Facturados')),
                ],
                selected: {_verFacturados},
                onSelectionChanged: (s) {
                  setState(() => _verFacturados = s.first);
                },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Registro>>(
              stream: _verFacturados
                  ? FirebaseService.streamPedidosPorEstados([
                      'Facturado',
                    ], masAntiguosPrimero: false)
                  : FirebaseService.streamPedidosPorEstados([
                      'Pendiente',
                      'En preparación',
                      'Listo',
                      'Entregado',
                    ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final pedidos = snapshot.data ?? [];
                if (pedidos.isEmpty) {
                  return Center(
                    child: Text(
                      _verFacturados
                          ? 'Aún no hay pedidos facturados.'
                          : 'No hay pedidos pendientes.',
                      style: TextStyle(fontSize: 18),
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: pedidos.length,
                  itemBuilder: (context, i) => _tarjeta(pedidos[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
