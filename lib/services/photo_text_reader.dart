import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/ocr_name_picker.dart';

/// 제품 사진의 글자를 기기 안에서 읽어(인터넷 불필요) 물건 이름 후보를 만든다.
class PhotoTextReader {
  TextRecognizer? _recognizer;

  Future<List<String>> suggestNames(String imagePath) async {
    try {
      final recognizer = _recognizer ??= TextRecognizer(
        script: TextRecognitionScript.korean,
      );
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final lines = [
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrLine(line.text, line.boundingBox.height),
      ];
      return pickNamesFromOcr(lines);
    } on Exception {
      // 글자를 못 읽어도 사진 저장은 계속된다.
      return const [];
    }
  }

  Future<void> close() async => _recognizer?.close();
}
