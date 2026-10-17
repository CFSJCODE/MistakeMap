import 'package:shared_preferences/shared_preferences.dart';

/// Preferências simples do caderno de erros (shared_preferences): valores
/// pequenos de chave/valor que sobrevivem ao fechar e reabrir o app.
class PreferenciasCaderno {
  const PreferenciasCaderno();

  static const String chaveOcultarRevisados = 'caderno_ocultar_revisados';

  Future<bool> ocultarRevisados() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(chaveOcultarRevisados) ?? false;
  }

  Future<void> salvarOcultarRevisados(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(chaveOcultarRevisados, valor);
  }

  Future<void> limpar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(chaveOcultarRevisados);
  }
}
