enum BrailleLanguage {
  english,
  unicode;

  String get label => switch (this) {
    BrailleLanguage.english => 'English',
    BrailleLanguage.unicode => 'Unicode',
  };

  bool get isEnabled => true;
}

const Map<int, String> _englishMap = {
  // Letters
  0: 'a',
  2: 'b',
  8: 'c',
  24: 'd',
  16: 'e',
  10: 'f',
  26: 'g',
  18: 'h',
  9: 'i',
  25: 'j',
  4: 'k',
  6: 'l',
  12: 'm',
  28: 'n',
  20: 'o',
  14: 'p',
  30: 'q',
  22: 'r',
  13: 's',
  29: 't',
  36: 'u',
  38: 'v',
  57: 'w',
  44: 'x',
  60: 'y',
  52: 'z',
  // Punctuation
  1: ',',
  5: ';',
  17: ':',
  49: '.',
  21: '!',
  3: "'",
  35: '-',
  53: '(',
  33: '?',
  // Indicators (sentinel values — consumed by the text-builder, not emitted)
  59: '[NUM]',
  31: '[CAPS]',
};

String _idToUnicode(int id) {
  if (id < 0 || id > 62) return '';
  return String.fromCharCode(0x2801 + id);
}

String classIdToChar(int classId, BrailleLanguage language) {
  switch (language) {
    case BrailleLanguage.english:
      return _englishMap[classId] ?? '';
    case BrailleLanguage.unicode:
      return _idToUnicode(classId);
  }
}

const String kIndicatorCaps = '[CAPS]';
const String kIndicatorNumber = '[NUM]';

const Map<String, String> kBrailleLetterToDigit = {
  'a': '1',
  'b': '2',
  'c': '3',
  'd': '4',
  'e': '5',
  'f': '6',
  'g': '7',
  'h': '8',
  'i': '9',
  'j': '0',
};

String buildTextFromLines(List<dynamic> lines, BrailleLanguage language) {
  final buf = StringBuffer();

  for (int li = 0; li < lines.length; li++) {
    final line = lines[li];

    for (int wi = 0; wi < (line.words as List).length; wi++) {
      if (wi > 0) buf.write(' ');

      bool capitalNext = false;
      bool capsLock = false;
      bool numberMode = false;

      final cells = line.words[wi].cells as List;
      for (int ci = 0; ci < cells.length; ci++) {
        final id = cells[ci].detection.classId as int;
        final raw = classIdToChar(id, language);

        if (raw == kIndicatorCaps) {
          if (capitalNext) {
            capsLock = true;
            capitalNext = false;
          } else {
            capitalNext = true;
          }
          continue;
        }

        if (raw == kIndicatorNumber) {
          numberMode = true;
          capitalNext = false;
          continue;
        }
        if (raw.isEmpty) continue;

        String ch = raw;
        if (numberMode && language == BrailleLanguage.english) {
          final digit = kBrailleLetterToDigit[ch];
          if (digit != null) {
            ch = digit;
          } else {
            numberMode = false;
          }
        }

        if (language == BrailleLanguage.english) {
          if (capsLock) {
            ch = ch.toUpperCase();
          } else if (capitalNext) {
            ch = ch.toUpperCase();
            capitalNext = false;
          }
        }

        buf.write(ch);
      }
    }

    if (li < lines.length - 1) buf.write('\n');
  }

  return buf.toString();
}
