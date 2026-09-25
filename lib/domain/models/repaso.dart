/// Puerto de `src/app/repaso/acciones.ts`.
///
/// Todo lo de aquí cruza códigos que devuelve Postgres contra el banco local.
/// Es a propósito, y en el móvil el motivo pesa aún más que en la web: los RPC
/// nunca devuelven el enunciado ni —sobre todo— la clave, solo el
/// `codigo_externo`, así que ni por accidente pueden filtrar la respuesta
/// correcta. El enunciado lo pone el APK; la clave, nadie hasta que respondes.
///
/// Un código puede no encontrarse (pregunta retirada del banco después de que
/// el alumno la respondiera). `Banco.porCodigos` lo descarta en silencio en
/// vez de romper la pantalla.
class ResumenRepasos {
  final int pendientesHoy;
  final DateTime? proximaFecha;
  final int totalProgramados;

  const ResumenRepasos({
    required this.pendientesHoy,
    required this.proximaFecha,
    required this.totalProgramados,
  });

  /// Sin nada programado, el alumno todavía no ha respondido lo suficiente
  /// como para que la repetición espaciada tenga algo que decir.
  bool get sinHistorial => totalProgramados == 0;
}
