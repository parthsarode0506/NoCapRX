import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Extracts text from a prescription image on supported mobile platforms.
/// Medicine identity is still confirmed by the local resolver after OCR.
class PrescriptionOcrService {
  static Future<String> extractText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(input);
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}