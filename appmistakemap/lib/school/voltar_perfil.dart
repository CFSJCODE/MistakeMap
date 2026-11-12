import 'package:flutter/widgets.dart';

/// Liga o "voltar" das telas de cada perfil à escolha de perfil.
///
/// A porta de perfil (porta_perfil.dart) publica este escopo. O app do
/// estudante lê para saber o que fazer quando o voltar chega à raiz (Início):
/// em vez de fechar o app, abre a escolha de perfil. Sem o escopo (app da
/// equipe e testes antigos), o voltar segue como antes.
class EscopoVoltarPerfil extends InheritedWidget {
  const EscopoVoltarPerfil({
    super.key,
    required this.voltar,
    required this.estudanteAtivo,
    required super.child,
  });

  /// Abre a escolha de perfil.
  final VoidCallback voltar;

  /// O app do estudante é o que está na tela. Quando outro perfil está aberto,
  /// o app do estudante fica vivo por baixo e não deve tratar o voltar.
  final bool estudanteAtivo;

  static EscopoVoltarPerfil? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EscopoVoltarPerfil>();

  @override
  bool updateShouldNotify(EscopoVoltarPerfil oldWidget) =>
      estudanteAtivo != oldWidget.estudanteAtivo || voltar != oldWidget.voltar;
}
