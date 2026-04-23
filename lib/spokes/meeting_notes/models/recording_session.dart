import 'dart:convert';

class RecordingSession {
  final String id;
  final DateTime startTime;
  final String outputFilePath;
  final DateTime lastFlushed;

  RecordingSession({
    required this.id,
    required this.startTime,
    required this.outputFilePath,
    required this.lastFlushed,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'outputFilePath': outputFilePath,
        'lastFlushed': lastFlushed.toIso8601String(),
      };

  factory RecordingSession.fromJson(Map<String, dynamic> json) =>
      RecordingSession(
        id: json['id'],
        startTime: DateTime.parse(json['startTime']),
        outputFilePath: json['outputFilePath'],
        lastFlushed: DateTime.parse(json['lastFlushed']),
      );

  RecordingSession copyWith({
    String? id,
    DateTime? startTime,
    String? outputFilePath,
    DateTime? lastFlushed,
  }) {
    return RecordingSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      outputFilePath: outputFilePath ?? this.outputFilePath,
      lastFlushed: lastFlushed ?? this.lastFlushed,
    );
  }
}

class TranscriptSegment {
  final String speakerLabel;
  final Duration timestamp;
  final String text;

  TranscriptSegment({
    required this.speakerLabel,
    required this.timestamp,
    required this.text,
  });

  TranscriptSegment copyWith({
    String? speakerLabel,
    Duration? timestamp,
    String? text,
  }) {
    return TranscriptSegment(
      speakerLabel: speakerLabel ?? this.speakerLabel,
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
    );
  }
}
