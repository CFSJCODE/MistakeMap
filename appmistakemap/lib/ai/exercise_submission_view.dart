import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'analysis_models.dart';
import 'analysis_repository.dart';
import 'material_control_styles.dart';
import 'insights_view.dart';
import '../theme/design_tokens.dart';
import '../theme/motion.dart';

const mapTitleBlue = MistakeMapDesign.primary;
const mapContentBlue = MistakeMapDesign.content;
const mapBackground = MistakeMapDesign.background;
const mapSurface = MistakeMapDesign.surface;

class ExerciseSubmissionView extends StatefulWidget {
  final String userId;
  final AnalysisRepository repository;
  final PracticeExercise? practice;
  final VoidCallback? onClose;
  const ExerciseSubmissionView({
    super.key,
    required this.userId,
    required this.repository,
    this.practice,
    this.onClose,
  });

  @override
  State<ExerciseSubmissionView> createState() => _ExerciseSubmissionViewState();
}

class _ExerciseSubmissionViewState extends State<ExerciseSubmissionView> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _prompt = TextEditingController();
  final _answer = TextEditingController();
  final _difficulty = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  String? _attemptId;
  String? _error;
  bool _busy = false;
  bool _uploaded = false;
  String _stage = 'Salvando exercício…';

  @override
  void initState() {
    super.initState();
    _subject.text = widget.practice?.subjectName ?? '';
    _prompt.text = widget.practice?.prompt ?? '';
  }

  @override
  void dispose() {
    for (final controller in [_subject, _prompt, _answer, _difficulty]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: MenuItemButton(
                leadingIcon: const Icon(Icons.photo_camera_outlined),
                onPressed: () => Navigator.pop(ctx, ImageSource.camera),
                child: const Text('Tirar uma foto'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: MenuItemButton(
                leadingIcon: const Icon(Icons.photo_library_outlined),
                onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
                child: const Text('Escolher da galeria'),
              ),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (image == null) return;
      imageContentType(image.name);
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
        throw const AnalysisFailure(
          'Use uma imagem JPG, PNG ou WebP de até 8 MB.',
        );
      }
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = image.name;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Salvando exercício…';
    });
    try {
      _attemptId ??= await widget.repository.createAttempt(
        userId: widget.userId,
        subject: _subject.text.trim(),
        prompt: _prompt.text.trim(),
        answer: _answer.text.trim(),
        difficulty: _difficulty.text.trim(),
        hasImage: _imageBytes != null,
        practice: widget.practice,
      );
      if (_imageBytes != null && !_uploaded) {
        if (mounted) setState(() => _stage = 'Enviando imagem…');
        await widget.repository.uploadImage(
          _attemptId!,
          _imageName!,
          _imageBytes!,
        );
        _uploaded = true;
      }
      // Once saved, keep the ID on retries instead of creating a duplicate attempt.
      if (mounted) setState(() => _stage = 'IA analisando sua resposta…');
      try {
        await widget.repository.analyze(_attemptId!);
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = friendlyFailure(error));
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MistakeMapPageRoute<void>(
          context: context,
          builder: (_) => AttemptDetailView(
            userId: widget.userId,
            attemptId: _attemptId!,
            repository: widget.repository,
          ),
        ),
      );
      if (!mounted) return;
      if (widget.practice != null) {
        Navigator.pop(context);
      } else {
        _reset();
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
    for (final controller in [_subject, _prompt, _answer, _difficulty]) {
      controller.clear();
    }
    _attemptId = null;
    _imageBytes = null;
    _imageName = null;
    _uploaded = false;
    _error = null;
  });

  InputDecoration _decoration(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: const OutlineInputBorder(),
    filled: true,
    fillColor: Colors.white,
    alignLabelWithHint: true,
  );

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _attemptId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.practice == null
              ? 'Adicionar exercício'
              : 'Resolver exercício',
        ),
        backgroundColor: mapSurface,
        foregroundColor: mapTitleBlue,
        leading: widget.onClose != null
            ? IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
              )
            : null,
      ),
      backgroundColor: mapBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Registre uma tentativa para compreender seus erros.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, color: mapContentBlue),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('exercise-subject'),
                  controller: _subject,
                  readOnly: locked || widget.practice != null,
                  decoration: _decoration(
                    'Assunto',
                    'Ex.: Equações de segundo grau',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Informe o assunto'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('exercise-prompt'),
                  controller: _prompt,
                  readOnly: locked || widget.practice != null,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 16000,
                  decoration: _decoration(
                    'Enunciado do exercício',
                    'Digite o enunciado; a foto pode complementar.',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) && _imageBytes == null
                      ? 'Informe o enunciado ou anexe uma foto legível'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('exercise-answer'),
                  controller: _answer,
                  readOnly: locked,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 12000,
                  decoration: _decoration(
                    'Sua resposta',
                    'Escreva sua resposta e os passos que tentou.',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) && _imageBytes == null
                      ? 'Informe sua resposta ou anexe a foto da resolução'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('exercise-difficulty'),
                  controller: _difficulty,
                  readOnly: locked,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: _decoration(
                    'Sua dificuldade (opcional)',
                    'Em qual passo você teve dúvida?',
                  ),
                ),
                const SizedBox(height: 24),
                if (_imageBytes == null)
                  OutlinedButton.icon(
                    onPressed: locked ? null : _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Adicionar foto do exercício'),
                    style:
                        MistakeMapMaterialControls.button(
                          context,
                          radius: 10,
                          border: const BorderSide(color: mapContentBlue),
                        ).copyWith(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _imageBytes!,
                      height: 220,
                      fit: BoxFit.contain,
                      semanticLabel: 'Foto anexada ao exercício',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: locked
                        ? null
                        : () => setState(() {
                            _imageBytes = null;
                            _imageName = null;
                          }),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover imagem'),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'A IA sugere uma correção e identifica padrões. Confira a explicação antes de estudar por ela.',
                  style: TextStyle(fontSize: 14, color: mapContentBlue),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                  if (_attemptId != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'A tentativa já está salva. Tentar novamente usa a mesma tentativa.',
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  key: const Key('submit-exercise'),
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _busy
                        ? _stage
                        : _attemptId == null
                        ? 'Registrar e analisar'
                        : 'Tentar novamente',
                  ),
                  style:
                      MistakeMapMaterialControls.button(
                        context,
                        background: mapContentBlue,
                        foreground: Colors.white,
                        radius: 10,
                      ).copyWith(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                ),
                if (_attemptId != null && !_busy && widget.practice == null)
                  TextButton(
                    onPressed: _reset,
                    child: const Text('Registrar outro exercício'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
