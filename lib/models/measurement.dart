class Measurement {
  final int? id;
  final DateTime timestamp;
  final double bpm;
  final double rmssd;
  final double sdnn;
  final double pnn50;
  final double lfHfRatio;
  final String stressStatus; // 'Rileks', 'Stres Sedang', 'Stres Tinggi'
  final double stressConfidence;
  final bool postBreathing; // true jika ini pengukuran post-breathing

  Measurement({
    this.id,
    required this.timestamp,
    required this.bpm,
    required this.rmssd,
    required this.sdnn,
    required this.pnn50,
    required this.lfHfRatio,
    required this.stressStatus,
    required this.stressConfidence,
    this.postBreathing = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'bpm': bpm,
      'rmssd': rmssd,
      'sdnn': sdnn,
      'pnn50': pnn50,
      'lf_hf_ratio': lfHfRatio,
      'stress_status': stressStatus,
      'stress_confidence': stressConfidence,
      'post_breathing': postBreathing ? 1 : 0,
    };
  }

  factory Measurement.fromMap(Map<String, dynamic> map) {
    return Measurement(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      bpm: (map['bpm'] as num).toDouble(),
      rmssd: (map['rmssd'] as num).toDouble(),
      sdnn: (map['sdnn'] as num).toDouble(),
      pnn50: (map['pnn50'] as num).toDouble(),
      lfHfRatio: (map['lf_hf_ratio'] as num).toDouble(),
      stressStatus: map['stress_status'] as String,
      stressConfidence: (map['stress_confidence'] as num).toDouble(),
      postBreathing: (map['post_breathing'] as int) == 1,
    );
  }
}
