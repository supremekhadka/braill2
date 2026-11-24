import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/braille_mappings.dart';
import 'package:app/core/line_reconstructor.dart';
import 'package:app/services/tflite_service.dart';

Detection _det(int classId) =>
    Detection(x1: 0, y1: 0, x2: 0.04, y2: 0.1, confidence: 0.9, classId: classId);

BrailleLine _line(List<int> classIds) => BrailleLine([
      BrailleWord(classIds
          .map((id) => BrailleCell(detection: _det(id), cx: 0, cy: 0, width: 0.04, height: 0.1))
          .toList()),
    ]);

void main() {
  test('ST-7: English mapping produces expected characters', () {
    expect(classIdToChar(0, BrailleLanguage.english), 'a');
    expect(classIdToChar(2, BrailleLanguage.english), 'b');
  });

  test('ST-7: Nepali mapping produces expected characters', () {
    expect(classIdToChar(4, BrailleLanguage.nepali), 'क');
    expect(classIdToChar(0, BrailleLanguage.nepali), 'अ');
  });

  test('ST-7: Unicode mapping falls back to braille codepoint', () {
    expect(classIdToChar(0, BrailleLanguage.unicode), '\u2801');
  });

  test('ST-7: caps indicator capitalizes next English letter', () {
    final text = buildTextFromLines([_line([31, 0])], BrailleLanguage.english);
    expect(text, 'A');
  });

  test('ST-7: number indicator converts English letters to digits', () {
    final text = buildTextFromLines([_line([59, 0])], BrailleLanguage.english);
    expect(text, '1');
  });
}