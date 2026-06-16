const List<String> kEmotionLabels = <String>[
  'angry',
  'disgust',
  'fear',
  'happy',
  'neutral',
  'sad',
  'surprise',
];

bool isSupportedEmotionLabel(String label) => kEmotionLabels.contains(label);
