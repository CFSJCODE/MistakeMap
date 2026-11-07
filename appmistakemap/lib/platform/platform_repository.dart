import 'package:supabase_flutter/supabase_flutter.dart';

typedef PlatformData = Map<String, dynamic>;

PlatformData platformMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<PlatformData> platformRows(dynamic value) =>
    value is List ? value.map(platformMap).toList() : <PlatformData>[];

class PlatformFailure implements Exception {
  const PlatformFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class PlatformRepository {
  Future<PlatformData> execute(String action, [PlatformData input = const {}]);
}

class SupabasePlatformRepository implements PlatformRepository {
  SupabasePlatformRepository(this.client);
  final SupabaseClient client;

  @override
  Future<PlatformData> execute(
    String action, [
    PlatformData input = const {},
  ]) async {
    try {
      final response = await client.functions.invoke(
        const {'weekly_summary', 'freeze_streak'}.contains(action)
            ? 'review-queue'
            : 'study-platform',
        body: {...input, 'action': action},
      );
      final data = platformMap(response.data);
      if (response.status >= 400 || data.containsKey('error')) {
        throw PlatformFailure(
          data['message'] as String? ?? 'Não foi possível concluir a operação.',
        );
      }
      return data;
    } on FunctionException catch (error) {
      final details = platformMap(error.details);
      throw PlatformFailure(
        details['message'] as String? ?? 'Não foi possível acessar a plataforma. Verifique sua conexão e tente novamente.',
      );
    } on PlatformFailure {
      rethrow;
    } catch (_) {
      throw const PlatformFailure(
        'Não foi possível acessar a plataforma. Verifique sua conexão e tente novamente.',
      );
    }
  }
}
