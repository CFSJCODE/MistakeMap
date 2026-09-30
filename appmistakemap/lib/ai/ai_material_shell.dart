import 'package:flutter/material.dart';

import 'analysis_repository.dart';
import 'exercise_submission_view.dart';
import 'insights_view.dart';

/// Hosts the new analysis flow within the existing Fluent navigation.
class AiMaterialShell extends StatelessWidget {
  final String userId;
  final AnalysisRepository repository;
  final bool showMap;
  final VoidCallback onClose;

  const AiMaterialShell({
    super.key,
    required this.userId,
    required this.repository,
    required this.showMap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color.fromARGB(255, 30, 92, 167),
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F6F4),
    ),
    home: showMap
        ? ErrorMapView(userId: userId, repository: repository, onClose: onClose)
        : ExerciseSubmissionView(
            userId: userId,
            repository: repository,
            onClose: onClose,
          ),
  );
}
