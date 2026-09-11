import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';

class ReactionCameraPanel extends StatefulWidget {
  const ReactionCameraPanel({
    super.key,
    required this.controller,
    required this.stage,
  });

  final AppController controller;
  final String stage;

  @override
  State<ReactionCameraPanel> createState() => _ReactionCameraPanelState();
}

class _ReactionCameraPanelState extends State<ReactionCameraPanel> {
  CameraController? _cameraController;
  Timer? _timer;
  bool _enabled = false;
  bool _capturing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didUpdateWidget(covariant ReactionCameraPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage && _enabled) {
      _capture(event: 'stage_entered');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_enabled || !mounted) return;
    setState(() {
      _enabled = true;
      _message = 'Starting front-camera emotion analysis for this stage.';
    });

    try {
      final List<CameraDescription> cameras = await availableCameras();
      final CameraDescription frontCamera = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _cameraController = controller;
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!_enabled || !mounted) return;
      await _capture(event: 'stage_entered');
      _timer = Timer.periodic(const Duration(seconds: 12), (_) {
        _capture(event: 'stage_periodic_sample');
      });
      if (mounted) {
        setState(() {
          _message =
              'Front-camera emotion analysis is active. Images are processed locally and not stored.';
        });
      }
    } catch (error) {
      widget.controller.recordReactionCameraUnavailable(
        stage: widget.stage,
        event: 'camera_unavailable',
        reason: error.toString(),
      );
      if (mounted) {
        setState(() {
          _enabled = false;
          _message = 'Camera unavailable or permission denied.';
        });
      }
    }
  }

  Future<void> _capture({required String event}) async {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    _capturing = true;
    try {
      final XFile snapshot = await controller.takePicture();
      final List<int> bytes = await snapshot.readAsBytes();
      await widget.controller.recordReactionSnapshot(
        imageBytes: bytes,
        stage: widget.stage,
        event: event,
      );
    } catch (error) {
      widget.controller.recordReactionCameraUnavailable(
        stage: widget.stage,
        event: 'snapshot_failed',
        reason: error.toString(),
      );
      if (mounted) {
        setState(() => _message = 'Reaction snapshot failed.');
      }
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ReactionEmotionSample> stageSamples = widget
        .controller.reactionSamples
        .where((ReactionEmotionSample sample) => sample.stage == widget.stage)
        .toList(growable: false);
    final int successfulCount = stageSamples
        .where((ReactionEmotionSample sample) => sample.label != null)
        .length;
    final int failedCount = stageSamples
        .where((ReactionEmotionSample sample) => sample.failureReason != null)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _enabled ? Icons.visibility : Icons.visibility_off,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Front-camera emotion analysis'),
              subtitle: Text(_message ?? 'Preparing camera analysis.'),
            ),
            Text('Stage: ${_readableStage(widget.stage)}'),
            const SizedBox(height: 4),
            Text(
              'Samples in this stage: $successfulCount'
              '${failedCount > 0 ? ' · camera failures: $failedCount' : ''}',
            ),
            if (successfulCount > 0) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: stageSamples
                    .where((ReactionEmotionSample sample) =>
                        sample.label != null && sample.confidence != null)
                    .take(8)
                    .map(
                      (ReactionEmotionSample sample) => Chip(
                        label: Text(
                          '${sample.label} ${(sample.confidence! * 100).toStringAsFixed(0)}%',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _readableStage(String stage) {
    switch (stage) {
      case 'before_analysis':
        return 'Before analysis';
      case 'file_analysis':
        return 'File analysis';
      case 'final_analysis':
        return 'Final analysis';
      default:
        return stage;
    }
  }
}
