import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'perfil_modelos.dart';

typedef DadosEscola = Map<String, dynamic>;

DadosEscola mapaEscola(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<DadosEscola> linhasEscola(Object? v) =>
    v is List ? [for (final item in v) mapaEscola(item)] : <DadosEscola>[];

class FalhaEscola implements Exception {
  const FalhaEscola(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Cadastro por perfil e escola. Leitura pelas tabelas com RLS; toda escrita
/// pela Edge Function school-admin, que confere convite e papel.
abstract class RepositorioEscola {
  Future<ContextoPerfil> contexto();
  Future<DadosEscola> executar(String acao, [DadosEscola dados = const {}]);
}

class RepositorioEscolaSupabase implements RepositorioEscola {
  RepositorioEscolaSupabase(this.cliente);
  final SupabaseClient cliente;

  @override
  Future<ContextoPerfil> contexto() async {
    final uid = cliente.auth.currentUser?.id;
    if (uid == null) throw const FalhaEscola('Entre na sua conta.');
    final resultados = await Future.wait<Object?>([
      cliente
          .from('user_signups')
          .select('persona,birth_date')
          .eq('user_id', uid)
          .limit(1),
      cliente
          .from('school_members')
          .select('school_id,role,status,schools(name,plan,status)')
          .eq('user_id', uid),
      cliente
          .from('school_team_members')
          .select('team_role,school_teams(id,name,competition,school_id)')
          .eq('user_id', uid),
      cliente.rpc('my_guardian_consent_pending'),
      cliente
          .from('guardian_links')
          .select('student_id')
          .eq('guardian_id', uid)
          .isFilter('revoked_at', null)
          .limit(1),
    ]).timeout(const Duration(seconds: 12));
    final signup = linhasEscola(resultados[0]);
    return ContextoPerfil.deJson({
      'signup': signup.isEmpty ? null : signup.first,
      'roles': resultados[1],
      'teams': resultados[2],
      'guardian_consent_pending': resultados[3] == true,
      'has_children': linhasEscola(resultados[4]).isNotEmpty,
    });
  }

  @override
  Future<DadosEscola> executar(
    String acao, [
    DadosEscola dados = const {},
  ]) async {
    try {
      final resposta = await cliente.functions.invoke(
        'school-admin',
        body: {...dados, 'action': acao},
      );
      final corpo = mapaEscola(resposta.data);
      if (resposta.status >= 400 || corpo.containsKey('error')) {
        throw FalhaEscola(
          corpo['message'] as String? ?? 'Não foi possível concluir agora.',
        );
      }
      return corpo;
    } on FunctionException catch (erro) {
      throw FalhaEscola(
        mapaEscola(erro.details)['message'] as String? ??
            'Não foi possível falar com o servidor. Confira a conexão.',
      );
    } on FalhaEscola {
      rethrow;
    } catch (_) {
      throw const FalhaEscola(
        'Não foi possível falar com o servidor. Confira a conexão.',
      );
    }
  }
}

/// Último contexto e perfil escolhido, por conta e por aparelho. Serve para
/// abrir o app sem rede no perfil certo; o servidor confirma em seguida.
class PreferenciasPerfil {
  const PreferenciasPerfil();

  static String _ctx(String uid) => 'perfil_contexto_$uid';
  static String _ativo(String uid) => 'perfil_ativo_$uid';

  Future<ContextoPerfil?> contexto(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_ctx(uid));
      if (texto == null) return null;
      return ContextoPerfil.deJson(mapaEscola(jsonDecode(texto)));
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarContexto(String uid, ContextoPerfil ctx) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ctx(uid), jsonEncode(ctx.paraJson()));
    } catch (_) {
      // Sem armazenamento local, o contexto vem do servidor a cada abertura.
    }
  }

  Future<String?> perfilAtivo(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_ativo(uid));
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarPerfilAtivo(String uid, String chave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ativo(uid), chave);
    } catch (_) {}
  }
}
