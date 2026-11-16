import 'package:speech_to_text/speech_to_text.dart';

import '../core/item_categorizer.dart';

/// 음성 인식 결과 하나.
class VoiceResult {
  const VoiceResult({
    required this.words,
    required this.isFinal,
    this.alternatives = const [],
    this.confidence = -1,
  });

  final String words;
  final bool isFinal;

  /// 엔진이 "이것일 수도 있다"고 내놓은 다른 후보들. ([words]는 빠져 있다)
  final List<String> alternatives;

  /// 0~1. 엔진이 알려주지 않으면 -1.
  final double confidence;

  /// 확신이 낮아서 바로 저장하지 말고 후보를 보여줘야 하는지.
  /// 확신도를 모르면(-1) 믿고 저장한다. 잘못돼도 [되돌리기]가 있다.
  bool get isUnsure =>
      confidence >= 0 && confidence < 0.6 && alternatives.isNotEmpty;
}

/// 휴대폰의 음성 인식(Android: Google, iOS: Apple)으로 말을 글자로 바꾼다.
class VoiceInput {
  final _speech = SpeechToText();
  bool? _available;

  bool get isListening => _speech.isListening;

  /// 마이크와 음성 인식 권한을 요청한다. 거절하거나 기기가 지원하지 않으면 false.
  Future<bool> ensureReady({void Function(String error)? onError}) async {
    if (_available == true) return true;
    _available = await _speech.initialize(
      onError: (e) => onError?.call(e.errorMsg),
    );
    return _available!;
  }

  /// 말이 끝나면(3초 쉬면) [onResult]가 `isFinal: true`로 한 번 더 불린다.
  Future<void> listen({required void Function(VoiceResult) onResult}) {
    return _speech.listen(
      onResult: (r) {
        final words = r.recognizedWords;
        onResult(
          VoiceResult(
            words: words,
            isFinal: r.finalResult,
            alternatives: {
              for (final a in r.alternates)
                if (a.recognizedWords.trim().isNotEmpty &&
                    a.recognizedWords != words)
                  a.recognizedWords,
            }.take(3).toList(),
            confidence: r.hasConfidenceRating ? r.confidence : -1,
          ),
        );
      },
      listenOptions: SpeechListenOptions(
        localeId: 'ko_KR',
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
        // 물건 이름을 더 잘 알아듣게 힌트를 준다. (iOS)
        contextualPhrases: ItemCategorizer.knownNames.toList(),
      ),
    );
  }

  Future<void> stop() => _speech.stop();
}
