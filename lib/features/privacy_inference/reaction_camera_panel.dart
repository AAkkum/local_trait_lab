import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';

class ReactionCameraPanel extends StatefulWidget {
  const ReactionCameraPanel({super.key, required this.controller});

  final AppController controller;

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
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    if (!value) {
      _timer?.cancel();
      await _cameraController?.dispose();
      if (mounted) {
        setState(() {
          _enabled = false;
          _cameraController = null;
          _message = 'Reaction tracking stopped.';
        });
      }
      return;
    }

    setState(() {
      _enabled = true;
      _message = 'Opening front camera. No photos are stored.';
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
      await _capture(event: 'reaction_tracking_started');
      _timer = Timer.periodic(const Duration(seconds: 12), (_) {
        _capture(event: 'privacy_study_screen_active');
      });
      if (mounted) {
        setState(() {
          _message =
              'Reaction tracking active. A snapshot is analyzed about every 12 seconds; frames are not saved.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _enabled = false;
          _message = 'Camera reaction tracking unavailable: $error';
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
        event: event,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Reaction snapshot failed: $error');
      }
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int sampleCount = widget.controller.reactionSamples.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Optional front-camera emotion tracking'),
              subtitle: const Text(
                'Stores emotion labels over time, not camera images.',
              ),
              value: _enabled,
              onChanged: _toggle,
            ),
            if (_message != null) Text(_message!),
            if (sampleCount > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text('Emotion samples collected: $sampleCount'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: widget.controller.reactionSamples
                    .take(8)
                    .map(
                      (ReactionEmotionSample sample) => Chip(
                        label: Text(
                          '${sample.label} ${(sample.confidence * 100).toStringAsFixed(0)}%',
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
}
