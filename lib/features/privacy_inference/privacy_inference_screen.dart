import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../analysis/analysis_result.dart';
import '../../app/app_controller.dart';
import 'reaction_camera_panel.dart';

enum _StudyStage { consent, preQuestionnaire, analysis, finalProfile }

String _limitWords(String value, int maximumWords) {
  final List<String> words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((String word) => word.isNotEmpty)
      .toList();
  if (words.length <= maximumWords) return words.join(' ');
  return '${words.take(maximumWords).join(' ')}...';
}

Future<void> _showFullAnalysisSheet({
  required BuildContext context,
  required String title,
  required Object? analysis,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.94,
        builder: (BuildContext context, ScrollController scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    const Text(
                      'This is the complete analysis generated locally on this phone.',
                    ),
                    const SizedBox(height: 16),
                    _ReadableAnalysisView(analysis: analysis),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ReadableAnalysisView extends StatelessWidget {
  const _ReadableAnalysisView({required this.analysis});

  final Object? analysis;

  @override
  Widget build(BuildContext context) {
    if (analysis is! Map) {
      return SelectableText(_readableValue(analysis));
    }
    final Map<Object?, Object?> fields =
        (analysis! as Map).cast<Object?, Object?>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final MapEntry<Object?, Object?> entry in fields.entries)
          if (entry.key is String)
            _ReadableAnalysisField(
              label: _analysisFieldLabel(entry.key! as String),
              value: entry.value,
            ),
      ],
    );
  }
}

class _ReadableAnalysisField extends StatelessWidget {
  const _ReadableAnalysisField({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (value is List)
            _ReadableAnalysisList(items: value! as List)
          else if (value is Map)
            _ReadableAnalysisView(analysis: value)
          else
            SelectableText(_readableValue(value)),
        ],
      ),
    );
  }
}

class _ReadableAnalysisList extends StatelessWidget {
  const _ReadableAnalysisList({required this.items});

  final List items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'No additional information.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final Object? item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: item is Map
                ? _ReadableAnalysisView(analysis: item)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Icon(Icons.circle, size: 6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: SelectableText(_readableValue(item))),
                    ],
                  ),
          ),
      ],
    );
  }
}

String _analysisFieldLabel(String key) {
  return switch (key) {
    'content_summary' => 'What the file contains',
    'evidence' => 'What the AI noticed',
    'owner_inferences' => 'What this may suggest about you',
    'private_signals' => 'Personal information this may reveal',
    'profiling_uses' => 'How this information could be used',
    'cross_file_value' => 'What combining this with other files could reveal',
    'sensitivity' => 'Estimated sensitivity',
    'participant_headline' => 'Main inference',
    'participant_message' => 'Explanation',
    'headline' => 'Profile headline',
    'profile' => 'Combined personal profile',
    'key_inferences' => 'Key inferences',
    'privacy_implication' => 'Why this matters for privacy',
    'evidence_summary' => 'Evidence used for this profile',
    'uncertainty_note' => 'Limits and uncertainty',
    'parser_fallback' => 'Used recovery processing',
    'raw_model_output' => 'Original model response',
    _ => key
        .split('_')
        .where((String part) => part.isNotEmpty)
        .map((String part) => part[0].toUpperCase() + part.substring(1))
        .join(' '),
  };
}

String _readableValue(Object? value) {
  if (value == null) return 'Not available';
  if (value is bool) return value ? 'Yes' : 'No';
  final String text = value.toString().trim();
  return text.isEmpty ? 'Not available' : text;
}

class PrivacyInferenceScreen extends StatefulWidget {
  const PrivacyInferenceScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<PrivacyInferenceScreen> createState() => _PrivacyInferenceScreenState();
}

class _PrivacyInferenceScreenState extends State<PrivacyInferenceScreen> {
  final Map<String, Map<String, int>> _ratings = <String, Map<String, int>>{};
  final Map<String, Object?> _baselineAnswers = <String, Object?>{};
  final Map<String, Object?> _finalAnswers = <String, Object?>{};
  final ScrollController _scrollController = ScrollController();
  _StudyStage _stage = _StudyStage.consent;
  bool _consentStudyInfo = false;
  bool _consentLocalAnalysis = false;
  bool _consentProcessedExport = false;
  bool _consentCameraEmotion = false;
  bool _consentVoluntary = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _moveToStage(_StudyStage nextStage) {
    setState(() => _stage = nextStage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _pickFiles() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      allowMultiple: true,
      withData: false,
    );
    if (result != null) {
      await widget.controller.selectPrivacyFilesFromPickerResult(result);
    }
  }

  Future<void> _exportStudyRun() async {
    final List<PrivacyStudyResult> results = widget.controller.privacyResults;
    final Map<String, Object?> payload = <String, Object?>{
      'schema': 'local_trait_lab_privacy_study_run_v2',
      'created_at': DateTime.now().toIso8601String(),
      'target_minimum_analyses': 20,
      'completed_analyses': results.length,
      'consent_answers': <String, Object?>{
        'study_information_understood': _consentStudyInfo,
        'local_file_analysis_allowed': _consentLocalAnalysis,
        'processed_result_export_allowed': _consentProcessedExport,
        'front_camera_emotion_inference_understood': _consentCameraEmotion,
        'voluntary_participation_understood': _consentVoluntary,
      },
      'baseline_answers': _baselineAnswers,
      'final_answers': _finalAnswers,
      'reaction_emotion_samples': widget.controller.reactionSamples
          .map((ReactionEmotionSample sample) => sample.toJson())
          .toList(),
      'questionnaire_blocks': <String>[
        'sociodemographic questions',
        'IUIPC-8 privacy concern block',
        'ATI affinity for technology interaction block',
        'custom local AI expectation and final perception questions',
      ],
      'aggregate_profile_fallback':
          widget.controller.aggregatePrivacyProfile.toJson(),
      'per_file_inferences': results.map((PrivacyStudyResult entry) {
        final String key = entry.file.id;
        return <String, Object?>{
          'file': <String, Object?>{
            'original_name': entry.file.originalName,
            'original_mime_type': entry.file.originalMimeType,
            'analysis_input': entry.file.analysisAsset.toJson(),
            'note': entry.file.note,
          },
          'post_inference_ratings': _ratings[key] ?? const <String, int>{},
          'inference': entry.result.toJson(),
        };
      }).toList(),
      'synthesized_profile':
          widget.controller.synthesizedPrivacyProfile?.toJson(),
    };
    final Directory directory = await getApplicationDocumentsDirectory();
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final File file =
        File('${directory.path}/privacy_study_run_$timestamp.json');
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path)],
        subject: 'Local Trait Lab privacy study run',
        text: 'Local Trait Lab privacy study run export',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_stageTitle)),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, Widget? child) {
          final AppController controller = widget.controller;
          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (_stage == _StudyStage.consent) ...<Widget>[
                _ConsentCard(
                  studyInfo: _consentStudyInfo,
                  localAnalysis: _consentLocalAnalysis,
                  processedExport: _consentProcessedExport,
                  cameraEmotion: _consentCameraEmotion,
                  voluntary: _consentVoluntary,
                  onStudyInfoChanged: (bool value) {
                    setState(() => _consentStudyInfo = value);
                  },
                  onLocalAnalysisChanged: (bool value) {
                    setState(() => _consentLocalAnalysis = value);
                  },
                  onProcessedExportChanged: (bool value) {
                    setState(() => _consentProcessedExport = value);
                  },
                  onCameraEmotionChanged: (bool value) {
                    setState(() => _consentCameraEmotion = value);
                  },
                  onVoluntaryChanged: (bool value) {
                    setState(() => _consentVoluntary = value);
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _canContinueFromConsent
                      ? () {
                          _moveToStage(_StudyStage.preQuestionnaire);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue'),
                ),
              ] else if (_stage == _StudyStage.preQuestionnaire) ...<Widget>[
                _StudyModelDownloadCard(controller: controller),
                const SizedBox(height: 12),
                ReactionCameraPanel(
                  controller: controller,
                  stage: 'before_analysis',
                ),
                const SizedBox(height: 12),
                Text(
                  controller.isGemmaDownloading ||
                          controller.isGemmaDownloadPaused
                      ? 'Please answer the study questions while Gemma downloads. File analysis starts after both are ready.'
                      : 'First, answer these study questions. File analysis starts on the next page.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _BaselineQuestionnaireCard(
                  answers: _baselineAnswers,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: controller.gemmaModelReady &&
                          !controller.isGemmaDownloading
                      ? () {
                          _moveToStage(_StudyStage.analysis);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(controller.gemmaModelReady
                      ? 'Continue to file analysis'
                      : 'Install Gemma before continuing'),
                ),
              ] else if (_stage == _StudyStage.analysis) ...<Widget>[
                Text(
                  'Select images or PDFs. Each file can take up to about 30 seconds on this phone. Completed results appear below immediately, so you can evaluate them while the remaining files are still being analyzed.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ReactionCameraPanel(
                  controller: controller,
                  stage: 'file_analysis',
                ),
                const SizedBox(height: 16),
                _StudyPlanCard(
                  selectedCount: controller.privacyFiles.length,
                  pendingCount: controller.pendingPrivacyFileCount,
                  completedCount: controller.privacyResults.length,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : _pickFiles,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Select images or PDFs'),
                ),
                const SizedBox(height: 8),
                if (controller.privacyFiles.isNotEmpty) ...<Widget>[
                  Text(
                    'Selected files: ${controller.privacyFiles.length} · pending: ${controller.pendingPrivacyFileCount}',
                  ),
                  const SizedBox(height: 8),
                  for (final PrivacyStudyFile file
                      in controller.privacyFiles.take(5))
                    Text('• ${file.originalName}'),
                  if (controller.privacyFiles.length > 5)
                    Text('• ${controller.privacyFiles.length - 5} more'),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: controller.isBusy ||
                          controller.pendingPrivacyFileCount == 0
                      ? null
                      : controller.runPrivacyInferenceBatch,
                  icon: controller.isBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.psychology),
                  label: Text(controller.pendingPrivacyFileCount == 0
                      ? 'No new files to analyze'
                      : 'Analyze ${controller.pendingPrivacyFileCount} new file(s)'),
                ),
                if (controller.isBusy &&
                    controller.privacyFiles.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: controller.privacyFiles.isEmpty
                        ? null
                        : (controller.privacyProgress /
                                controller.privacyFiles.length)
                            .clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.privacyStatusMessage ??
                        'Working on this phone. Loading Gemma can take about a minute.',
                  ),
                  Text(
                    'Completed: ${controller.privacyProgress}/${controller.privacyFiles.length} · pending: ${controller.pendingPrivacyFileCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: controller.cancelPrivacyInference,
                    child: const Text('Cancel'),
                  ),
                ],
                if (controller.privacyFiles.isNotEmpty ||
                    controller.privacyResults.isNotEmpty)
                  TextButton.icon(
                    onPressed:
                        controller.isBusy ? null : controller.clearPrivacyStudy,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear local study run'),
                  ),
                if (controller.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    controller.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                for (final PrivacyStudyResult studyResult
                    in controller.privacyResults)
                  _PrivacyResultCard(
                    studyResult: studyResult,
                    ratings: _ratings,
                    onChanged: () => setState(() {}),
                  ),
                if (controller.privacyResults.isNotEmpty &&
                    controller.pendingPrivacyFileCount == 0) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () async {
                            final bool profileCreated =
                                await controller.synthesizePrivacyProfile();
                            if (!mounted) return;
                            if (profileCreated) {
                              _moveToStage(_StudyStage.finalProfile);
                            }
                          },
                    icon: controller.isBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Create profile and final questions'),
                  ),
                ],
              ] else ...<Widget>[
                Text(
                  'This page combines the current session and asks final study questions.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ReactionCameraPanel(
                  controller: controller,
                  stage: 'final_analysis',
                ),
                const SizedBox(height: 12),
                _AggregateProfileCard(
                  profile: controller.aggregatePrivacyProfile,
                  synthesizedProfile: controller.synthesizedPrivacyProfile,
                ),
                const SizedBox(height: 12),
                _FinalQuestionnaireCard(
                  answers: _finalAnswers,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    _moveToStage(_StudyStage.analysis);
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to file analysis'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: controller.privacyResults.isEmpty
                      ? null
                      : _exportStudyRun,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export study run JSON'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  bool get _canContinueFromConsent =>
      _consentStudyInfo &&
      _consentLocalAnalysis &&
      _consentProcessedExport &&
      _consentCameraEmotion &&
      _consentVoluntary;

  String get _stageTitle {
    switch (_stage) {
      case _StudyStage.consent:
        return 'Study consent';
      case _StudyStage.preQuestionnaire:
        return 'Before analysis';
      case _StudyStage.analysis:
        return 'File analysis';
      case _StudyStage.finalProfile:
        return 'Profile and final questions';
    }
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.studyInfo,
    required this.localAnalysis,
    required this.processedExport,
    required this.cameraEmotion,
    required this.voluntary,
    required this.onStudyInfoChanged,
    required this.onLocalAnalysisChanged,
    required this.onProcessedExportChanged,
    required this.onCameraEmotionChanged,
    required this.onVoluntaryChanged,
  });

  final bool studyInfo;
  final bool localAnalysis;
  final bool processedExport;
  final bool cameraEmotion;
  final bool voluntary;
  final ValueChanged<bool> onStudyInfoChanged;
  final ValueChanged<bool> onLocalAnalysisChanged;
  final ValueChanged<bool> onProcessedExportChanged;
  final ValueChanged<bool> onCameraEmotionChanged;
  final ValueChanged<bool> onVoluntaryChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          color: colors.tertiaryContainer.withValues(alpha: 0.38),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Information Sheet and Privacy Statement',
                    style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Please read this information carefully before taking part in the study. The study is conducted online in the context of a bachelor thesis at TU Darmstadt.',
                ),
                const SizedBox(height: 12),
                Text('Subject of the study', style: textTheme.titleSmall),
                const Text(
                  'This study investigates how people perceive privacy implications of local AI analysis on smartphones. The app analyzes selected images or PDF files locally on this Android phone and shows possible personal inferences derived from these files.',
                ),
                const SizedBox(height: 12),
                Text('Process', style: textTheme.titleSmall),
                const Text(
                  'First, you answer short questionnaires about privacy concerns, technology affinity, and demographic information. The app downloads a local Gemma AI model of about 2 GB to private app storage; Wi-Fi is recommended. Afterwards, you select around 20 of your own images or PDF files for local analysis, rate the shown inferences, and answer final questions about the resulting profile.',
                ),
                const SizedBox(height: 12),
                Text('Camera emotion inference', style: textTheme.titleSmall),
                const Text(
                  'During the study, the app derives front-camera emotion labels while you interact with the study screens. Camera images are processed locally and are not stored.',
                ),
                const SizedBox(height: 12),
                Text('Data and storage', style: textTheme.titleSmall),
                const Text(
                  'The study export can contain questionnaire answers, consent decisions, model outputs, summarized inferences, the combined profile, ratings, and front-camera emotion labels with confidence values. Raw selected files and camera images are not stored by the study team. The collected study data are analyzed anonymously and published only in aggregated form.',
                ),
                const SizedBox(height: 12),
                Text('Voluntariness and rights', style: textTheme.titleSmall),
                const Text(
                  'Participation is voluntary. You can stop participation at any time. If you stop before submitting the final study data, no data from your participation will be used.',
                ),
                const SizedBox(height: 12),
                Text('Contact', style: textTheme.titleSmall),
                const Text(
                  'Head of study: Prof. Dr. Dr. Christian Reuter, PEASEC, reuter@peasec.tu-darmstadt.de. Data handling: Simon Althaus, althaus@peasec.tu-darmstadt.de.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Declaration of Consent', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('By ticking the boxes below, I confirm that:'),
                _ConsentCheck(
                  value: studyInfo,
                  label:
                      'I have read and understood the information about the study.',
                  onChanged: onStudyInfoChanged,
                ),
                _ConsentCheck(
                  value: localAnalysis,
                  label:
                      'I understand that the app downloads a local Gemma AI model of about 2 GB, Wi-Fi is recommended, and selected images or PDF files are analyzed locally on this Android phone.',
                  onChanged: onLocalAnalysisChanged,
                ),
                _ConsentCheck(
                  value: cameraEmotion,
                  label:
                      'I understand that front-camera emotion labels and confidence values are derived during participation.',
                  onChanged: onCameraEmotionChanged,
                ),
                _ConsentCheck(
                  value: processedExport,
                  label:
                      'I agree that questionnaire answers and processed inference results may be saved/exported for research evaluation.',
                  onChanged: onProcessedExportChanged,
                ),
                _ConsentCheck(
                  value: voluntary,
                  label:
                      'I understand that participation is voluntary and can be stopped at any time.',
                  onChanged: onVoluntaryChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (bool? next) => onChanged(next ?? false),
      title: Text(label),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _StudyModelDownloadCard extends StatelessWidget {
  const _StudyModelDownloadCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer.withValues(alpha: 0.32),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Prepare the local AI model',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'This study uses Gemma 4 E2B directly on this phone. The model download is about 2 GB, so Wi-Fi is recommended.',
            ),
            const SizedBox(height: 8),
            if (controller.gemmaModelReady) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.check_circle, color: colors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Gemma is already installed. No download is needed.',
                    ),
                  ),
                ],
              ),
            ] else if (controller.isGemmaDownloading ||
                controller.isGemmaDownloadPaused) ...<Widget>[
              LinearProgressIndicator(
                value: controller.gemmaDownloadProgress,
              ),
              const SizedBox(height: 8),
              Text(
                controller.gemmaDownloadStatus ?? 'Downloading Gemma...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (controller.isGemmaDownloadPaused) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: controller.downloadStudyGemmaModel,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Retry Gemma download'),
                ),
              ],
            ] else ...<Widget>[
              Text(controller.gemmaDownloadStatus ??
                  'Gemma is not installed yet.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: controller.downloadStudyGemmaModel,
                icon: const Icon(Icons.download),
                label: const Text('Download Gemma 4 E2B'),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'You can complete the questions below while the download continues. After installation, the model remains in the app\'s private storage for later sessions.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyPlanCard extends StatelessWidget {
  const _StudyPlanCard({
    required this.selectedCount,
    required this.pendingCount,
    required this.completedCount,
  });

  final int selectedCount;
  final int pendingCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Current session',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'Target for a complete session: about 20 file analyses. Please stay on this screen while analysis is running.'),
            Text(
                'Selected: $selectedCount · completed: $completedCount · pending: $pendingCount'),
            const Text(
                'Already analyzed files are kept and will not be rerun.'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (completedCount / 20).clamp(0.0, 1.0),
            ),
            const SizedBox(height: 4),
            Text('$completedCount/20 analyses completed in this run'),
          ],
        ),
      ),
    );
  }
}

class _BaselineQuestionnaireCard extends StatelessWidget {
  const _BaselineQuestionnaireCard({
    required this.answers,
    required this.onChanged,
  });

  final Map<String, Object?> answers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Baseline questions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ChoiceQuestion(
              id: 'age_group',
              label: 'Age group',
              options: const <String>[
                '18-24',
                '25-34',
                '35-44',
                '45-54',
                '55+'
              ],
              answers: answers,
              onChanged: onChanged,
            ),
            _ChoiceQuestion(
              id: 'gender',
              label: 'Gender',
              options: const <String>[
                'woman',
                'man',
                'non-binary',
                'prefer not to say'
              ],
              answers: answers,
              onChanged: onChanged,
            ),
            _ChoiceQuestion(
              id: 'highest_education',
              label: 'Highest education level',
              options: const <String>[
                'school',
                'vocational training',
                'bachelor',
                'master or higher',
                'prefer not to say'
              ],
              answers: answers,
              onChanged: onChanged,
            ),
            const Divider(height: 28),
            Text('IUIPC-8 privacy concern block',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Seven-point agreement scale. IUIPC-8 measures control, awareness, and collection concerns.',
            ),
            for (final _QuestionItem item in _iuipc8Items)
              _WordScaleQuestion(
                id: item.id,
                label: item.label,
                answers: answers,
                options: _sevenPointAgreementLabels,
                onChanged: onChanged,
              ),
            const Divider(height: 28),
            Text('ATI technology affinity block',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Choose the response that best matches your level of agreement.',
            ),
            for (final _QuestionItem item in _atiItems)
              _WordScaleQuestion(
                id: item.id,
                label: item.label,
                answers: answers,
                options: _atiAgreementLabels,
                onChanged: onChanged,
              ),
            const Divider(height: 28),
            Text('Local AI expectations',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _LikertQuestion(
              id: 'expected_local_ai_capability',
              label:
                  'I expect a phone to infer sensitive information from selected local files.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'local_processing_reassurance_before',
              label:
                  '"Data stays on the phone" makes this feel privacy-friendly.',
              answers: answers,
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            _LikertQuestion(
              id: 'ati_like_tech_affinity',
              label: 'I usually enjoy trying new digital technologies.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'iuipc_like_privacy_concern',
              label:
                  'I am concerned about how apps can use information stored on my phone.',
              answers: answers,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyResultCard extends StatelessWidget {
  const _PrivacyResultCard({
    required this.studyResult,
    required this.ratings,
    required this.onChanged,
  });

  final PrivacyStudyResult studyResult;
  final Map<String, Map<String, int>> ratings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final result = studyResult.result;
    final String key = studyResult.file.id;
    final Object? raw = result.rawOutput;
    final Map<String, dynamic> json =
        raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _FileThumbnail(
                  file: studyResult.file,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _FilePreviewScreen(file: studyResult.file),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(studyResult.file.originalName,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(studyResult.file.note,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (result.failure != null)
              Text('Inference failed: ${result.failure!.message}',
                  style: const TextStyle(color: Colors.red))
            else ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _limitWords(
                  _stringValue(json['participant_headline']) ??
                      'Possible inference',
                  10,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _limitWords(
                  _stringValue(json['participant_message']) ??
                      'No reliable personal inference was returned.',
                  45,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This is a probabilistic inference, not a confirmed fact.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _showFullAnalysisSheet(
                    context: context,
                    title: 'Full file analysis',
                    analysis: json,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('Full analysis'),
                ),
              ),
              const Divider(height: 28),
              Text('Post-inference questions',
                  style: Theme.of(context).textTheme.titleSmall),
              _RatingQuestion(
                resultKey: key,
                ratings: ratings,
                id: 'unexpected_detail',
                label: 'How unexpected was this inference?',
                onChanged: onChanged,
              ),
              _RatingQuestion(
                resultKey: key,
                ratings: ratings,
                id: 'sensitivity',
                label: 'How sensitive does this inference feel?',
                onChanged: onChanged,
              ),
              _RatingQuestion(
                resultKey: key,
                ratings: ratings,
                id: 'accuracy',
                label: 'How accurate does this inference seem?',
                onChanged: onChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _stringValue(Object? value) => value is String ? value : null;
}

class _RatingQuestion extends StatelessWidget {
  const _RatingQuestion({
    required this.resultKey,
    required this.ratings,
    required this.id,
    required this.label,
    required this.onChanged,
  });

  final String resultKey;
  final Map<String, Map<String, int>> ratings;
  final String id;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final int current = ratings[resultKey]?[id] ?? 3;
    return _ScaleSlider(
      label: label,
      value: current,
      labels: _ratingLabels,
      onChanged: (int value) {
        ratings.putIfAbsent(resultKey, () => <String, int>{})[id] = value;
        onChanged();
      },
    );
  }
}

class _FileThumbnail extends StatelessWidget {
  const _FileThumbnail({required this.file, required this.onTap});

  final PrivacyStudyFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final List<int>? bytes = file.analysisAsset.bytes;
    final Widget child;
    if (bytes == null || bytes.isEmpty) {
      child = const SizedBox(
        width: 72,
        height: 72,
        child: ColoredBox(
          color: Color(0xFFE8EFEC),
          child: Icon(Icons.insert_drive_file),
        ),
      );
    } else {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          Uint8List.fromList(bytes),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      );
    }
    return InkWell(onTap: onTap, child: child);
  }
}

class _ChoiceQuestion extends StatelessWidget {
  const _ChoiceQuestion({
    required this.id,
    required this.label,
    required this.options,
    required this.answers,
    required this.onChanged,
  });

  final String id;
  final String label;
  final List<String> options;
  final Map<String, Object?> answers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final Object? current = answers[id];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final String option in options)
                ChoiceChip(
                  label: Text(option),
                  selected: current == option,
                  onSelected: (_) {
                    answers[id] = option;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LikertQuestion extends StatelessWidget {
  const _LikertQuestion({
    required this.id,
    required this.label,
    required this.answers,
    required this.onChanged,
  });

  final String id;
  final String label;
  final Map<String, Object?> answers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final Object? current = answers[id];
    final int score = current is int ? current : 3;
    return _ScaleSlider(
      label: label,
      value: score,
      labels: _fivePointAgreementLabels,
      onChanged: (int value) {
        answers[id] = value;
        onChanged();
      },
    );
  }
}

class _FilePreviewScreen extends StatelessWidget {
  const _FilePreviewScreen({required this.file});

  final PrivacyStudyFile file;

  @override
  Widget build(BuildContext context) {
    final List<int>? bytes = file.analysisAsset.bytes;
    return Scaffold(
      appBar: AppBar(title: Text(file.originalName)),
      backgroundColor: Colors.black,
      body: bytes == null || bytes.isEmpty
          ? const Center(
              child: Text(
                'No preview available.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Center(
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                ),
              ),
            ),
    );
  }
}

class _AggregateProfileCard extends StatelessWidget {
  const _AggregateProfileCard({
    required this.profile,
    required this.synthesizedProfile,
  });

  final AggregatePrivacyProfile profile;
  final AnalysisResult? synthesizedProfile;

  @override
  Widget build(BuildContext context) {
    final List<String> personalSignals = <String>{
      ...profile.ownerInferences,
      ...profile.privateSignals,
      ...profile.profilingUses,
    }.take(3).toList();
    final Map<String, Object?>? generatedProfile = _generatedProfileJson;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Possible personal profile',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Built from ${profile.analyzedFiles} analyzed file(s).'),
            const SizedBox(height: 12),
            const Text(
              'These are not confirmed facts. They are probabilistic guesses from the files selected in this session.',
            ),
            const SizedBox(height: 12),
            if (generatedProfile != null)
              _GeneratedProfileView(json: generatedProfile)
            else ...<Widget>[
              if (synthesizedProfile?.failure != null)
                Text(
                  'Generated profile unavailable: ${synthesizedProfile!.failure!.message}',
                  style: const TextStyle(color: Colors.red),
                ),
              _ProfileSignalSection(items: personalSignals),
            ],
            if (generatedProfile != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _showFullAnalysisSheet(
                    context: context,
                    title: 'Full profile analysis',
                    analysis: generatedProfile,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('Full analysis'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, Object?>? get _generatedProfileJson {
    final Object? raw = synthesizedProfile?.rawOutput;
    if (raw is! Map) return null;
    return <String, Object?>{
      for (final MapEntry entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}

class _GeneratedProfileView extends StatelessWidget {
  const _GeneratedProfileView({required this.json});

  final Map<String, Object?> json;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_stringValue(json['headline']) != null)
          Text(
            _limitWords(_stringValue(json['headline'])!, 12),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        if (_stringValue(json['profile']) != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_limitWords(_stringValue(json['profile'])!, 65)),
        ],
        if (json['key_inferences'] case final List<Object?> items)
          for (final Object? item in items.take(3))
            if (item is String && item.trim().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(_limitWords(item, 22)),
              ),
        if (_stringValue(json['privacy_implication']) != null &&
            _stringValue(json['privacy_implication'])!
                .trim()
                .isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _limitWords(_stringValue(json['privacy_implication'])!, 35),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ],
    );
  }

  String? _stringValue(Object? value) => value is String ? value : null;
}

class _ProfileSignalSection extends StatelessWidget {
  const _ProfileSignalSection({required this.items});

  final List<String> items;

  bool _isUsefulFallbackSignal(String item) {
    final String normalized = item.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != 'none' &&
        normalized != 'no clear profile signals were extracted yet.' &&
        normalized != 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return const Text('No clear profile signals were extracted yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Fallback extracted profile signals',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'This fallback is less coherent than the generated profile.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final String item in items.where(_isUsefulFallbackSignal))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(item),
          ),
      ],
    );
  }
}

class _FinalQuestionnaireCard extends StatelessWidget {
  const _FinalQuestionnaireCard({
    required this.answers,
    required this.onChanged,
  });

  final Map<String, Object?> answers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Final questions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Imagine a normal app performed this kind of local analysis regularly in the background and only sent inferred summaries or profile categories away.',
            ),
            _LikertQuestion(
              id: 'expected_phone_ai_power_after',
              label:
                  'Before this study, I expected my phone to be able to run this kind of AI analysis locally.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'concern_repeated_background_analysis',
              label:
                  'I would be concerned if an app repeated this analysis regularly on local photos, screenshots, or documents.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'data_stays_reassurance_after',
              label:
                  'The statement "the original files never leave the device" would still reassure me if inferred summaries or profile categories were sent to a server.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'comfortable_hidden_background_summary_upload',
              label:
                  'I would be comfortable if an app analyzed local files in the background and sent inferred summaries to a server without clearly notifying me each time.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'accept_commercial_profile_use',
              label:
                  'I would be comfortable if this inferred profile were used commercially, for example for advertisements, product offers, or sharing with another company.',
              answers: answers,
              onChanged: onChanged,
            ),
            _LikertQuestion(
              id: 'would_allow_photo_access_after',
              label:
                  'After seeing this profile, I would still allow broad photo or file access to an app.',
              answers: answers,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final int clamped = value.clamp(1, labels.length);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label),
          const SizedBox(height: 8),
          Text(
            labels[clamped - 1],
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: colors.primary),
          ),
          Slider(
            value: clamped.toDouble(),
            min: 1,
            max: labels.length.toDouble(),
            divisions: labels.length - 1,
            label: labels[clamped - 1],
            onChanged: (double next) => onChanged(next.round()),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  labels.first,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Text(
                  labels.last,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionItem {
  const _QuestionItem(this.id, this.label);

  final String id;
  final String label;
}

class _WordScaleQuestion extends StatelessWidget {
  const _WordScaleQuestion({
    required this.id,
    required this.label,
    required this.answers,
    required this.options,
    required this.onChanged,
  });

  final String id;
  final String label;
  final Map<String, Object?> answers;
  final List<String> options;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final Object? current = answers[id];
    final int score = current is Map && current['score'] is int
        ? current['score'] as int
        : ((options.length + 1) / 2).floor();
    return _ScaleSlider(
      label: label,
      value: score,
      labels: options,
      onChanged: (int value) {
        answers[id] = <String, Object?>{
          'score': value,
          'label': options[value - 1],
        };
        onChanged();
      },
    );
  }
}

const List<String> _fivePointAgreementLabels = <String>[
  'strongly disagree',
  'disagree',
  'neither',
  'agree',
  'strongly agree',
];

const List<String> _ratingLabels = <String>[
  'not at all',
  'slightly',
  'moderately',
  'strongly',
  'very strongly',
];

const List<String> _sevenPointAgreementLabels = <String>[
  'strongly disagree',
  'disagree',
  'somewhat disagree',
  'neither',
  'somewhat agree',
  'agree',
  'strongly agree',
];

const List<String> _atiAgreementLabels = <String>[
  'completely disagree',
  'largely disagree',
  'slightly disagree',
  'slightly agree',
  'largely agree',
  'completely agree',
];

const List<_QuestionItem> _iuipc8Items = <_QuestionItem>[
  _QuestionItem('iuipc_ctrl1',
      'Consumer online privacy is really a matter of the right to control how personal information is collected, used, and shared.'),
  _QuestionItem('iuipc_ctrl2',
      'Consumer control of personal information lies at the heart of consumer privacy.'),
  _QuestionItem('iuipc_awa1',
      'Companies seeking information online should disclose how the data are collected, processed, and used.'),
  _QuestionItem('iuipc_awa2',
      'A good online privacy policy should have a clear and conspicuous disclosure.'),
  _QuestionItem('iuipc_coll1',
      'It usually bothers me when online companies ask me for personal information.'),
  _QuestionItem('iuipc_coll2',
      'When online companies ask me for personal information, I sometimes think twice before providing it.'),
  _QuestionItem('iuipc_coll3',
      'It bothers me to give personal information to so many online companies.'),
  _QuestionItem('iuipc_coll4',
      'I am concerned that online companies are collecting too much personal information about me.'),
];

const List<_QuestionItem> _atiItems = <_QuestionItem>[
  _QuestionItem('ati_1',
      'I like to occupy myself in greater detail with technical systems.'),
  _QuestionItem(
      'ati_2', 'I like testing the functions of new technical systems.'),
  _QuestionItem('ati_3_reverse',
      'I predominantly deal with technical systems because I have to.'),
  _QuestionItem('ati_4',
      'When I have a new technical system in front of me, I try it out intensively.'),
  _QuestionItem('ati_5',
      'I enjoy spending time becoming acquainted with a new technical system.'),
  _QuestionItem('ati_6_reverse',
      'It is enough for me that a technical system works; I do not care how or why.'),
  _QuestionItem(
      'ati_7', 'I try to understand how a technical system exactly works.'),
  _QuestionItem('ati_8_reverse',
      'It is enough for me to know the basic functions of a technical system.'),
  _QuestionItem('ati_9',
      'I try to make full use of the capabilities of a technical system.'),
];
