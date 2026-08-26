enum BrailleLanguage {
  english,
  nepali,
  unicode;

  String get label => switch (this) {
    BrailleLanguage.english => 'English',
    BrailleLanguage.nepali => 'Nepali',
    BrailleLanguage.unicode => 'Unicode',
  };

  bool get isEnabled => true;
}

// ── Nepali map ──────────────────────────────────────────────────────────
//
// IDs here MUST match `char_id` from the Python generator's
// `nepali_braille_map.py` exactly, since that file is what produces the
// YOLO class labels the model is actually trained on:
//     char_id + 1 == 6-bit dot bitmask   (bit (d-1) set => dot d raised)
// Cross-checked against every consonant/vowel/sign the model needs to
// recognise; three corrections vs. the previous version of this file:
//   - फ (pha) was 21, which isn't a valid cell under the standard at all.
//     Its real code (dots 1,2,4) gives char_id 10.
//   - id 44 was labelled ऒ (a Kannada/Tamil vowel, not Devanagari). Its
//     real dot code (1,3,4,6) is chandra-o: ऑ.
//   - id 33 (previously ऎ) isn't a valid Devanagari cell under this
//     standard either and has been dropped; flag if your model was
//     actually trained expecting something at that id.
// Also newly added: halant (्, id 7) and the signs/punctuation that
// appear constantly in real Nepali prose (chandrabindu, anusvara,
// visarga, danda, comma) — all silently missing before, which meant
// every word using them (very common — halant alone appears in most
// sentences) lost characters on decode.
const Map<int, String> _nepaliMap = {
  0: 'अ',
  27: 'आ',
  9: 'इ',
  19: 'ई',
  36: 'उ',
  50: 'ऊ',
  16: 'ए',
  11: 'ऐ',
  20: 'ओ',
  41: 'औ',
  44: 'ऑ', // corrected label (was ऒ)

  4: 'क',
  39: 'ख',
  26: 'ग',
  34: 'घ',
  43: 'ङ',
  8: 'च',
  32: 'छ',
  25: 'ज',
  51: 'झ',
  17: 'ञ',
  61: 'ट',
  57: 'ठ',
  42: 'ड',
  62: 'ढ',
  59: 'ण',
  29: 'त',
  56: 'थ',
  24: 'द',
  45: 'ध',
  28: 'न',
  14: 'प',
  10: 'फ', // corrected id (was 21)
  2: 'ब',
  23: 'भ',
  12: 'म',
  60: 'य',
  22: 'र',
  6: 'ल',
  38: 'व',
  40: 'श',
  46: 'ष',
  13: 'स',
  18: 'ह',
  30: 'क्ष',
  48: 'ज्ञ',

  // Signs & punctuation — added; needed for ordinary prose (यहाँ,
  // सांस्कृतिक, छन्, सत्कार, sentence-ending।, etc).
  3: 'ँ', // chandrabindu
  47: 'ं', // anusvara
  31: 'ः', // visarga
  7: '्', // halant / virama — see `_decodeNepaliWord`, it is NOT just
  // printed in place; per rule 18 it silences the *next* consonant.
  49: '।', // danda (sentence/phrase separator)
  // Dots-2 is a genuine, inherent collision in the Bharati Braille
  // standard itself between comma and avagraha (ऽ). Comma is far more
  // common in ordinary text, so it wins by default here.
  1: ',',

  55: '!',
};

// ── Nepali decode state ────────────────────────────────────────────────
//
// Bharati Braille re-uses the *same* cell for an independent vowel and its
// dependent matra (e.g. dots-15 is both ए and े). `_nepaliMap` can only
// store one glyph per class id — it stores the independent-vowel form —
// so naive per-cell lookup always renders "ने" (न + े) as "नए" (न +
// implicit अ + ए), since every vowel cell gets printed as a standalone
// letter regardless of what preceded it.
//
// The fix is context, not a bigger table: a vowel-shaped cell is a MATRA
// if the cell immediately before it was a plain consonant, and stays an
// INDEPENDENT VOWEL otherwise (word start, after a space, after another
// vowel, or right after अ used as an explicit hiatus marker — e.g. "गई").
//
// Two more things need the same kind of context handling:
//   - HALANT (id 7) appears *before* the consonant it silences in the
//     braille stream (rule 18: धर्म -> [ध][halant][र][म]), so decoding
//     has to swap it back to "consonant + halant" print order.
//   - ऋ/ृ and ॠ/ॄ (vocalic r / rr, and their matras) are two-cell codes
//     that share their second cell (dots 1,2,3,5 -> id 22, same as र)
//     with the vocalic-r pair, and need 2-token lookahead to resolve.
const Map<int, String> _nepaliVowelToMatra = {
  27: 'ा', // आ -> ा
  9: 'ि', // इ -> ि
  19: 'ी', // ई -> ी
  36: 'ु', // उ -> ु
  50: 'ू', // ऊ -> ू
  16: 'े', // ए -> े
  11: 'ै', // ऐ -> ै
  20: 'ो', // ओ -> ो
  41: 'ौ', // औ -> ौ
  44: 'ॉ', // ऑ -> ॉ (chandra-o)
};

const int _kNepaliAId = 0; // अ — also the rule-24 hiatus signal
const int _kNepaliHalantId = 7; // ्

// Two-cell vocalic-r / vocalic-rr codes. First cell id -> (matra, vowel).
// Both share second-cell id 22 (र's code) as the lookahead partner.
const int _kVocalicRLookaheadPartner = 22;
const Map<int, (String matra, String vowel)> _kVocalicTwoCellCodes = {
  15: ('ृ', 'ऋ'), // dots-5 then dots-1235
  31: ('ॄ', 'ॠ'), // dots-6 then dots-1235
};

final Set<int> _nepaliVowelIds = {_kNepaliAId, ..._nepaliVowelToMatra.keys};

/// Everything in `_nepaliMap` that isn't a vowel, a sign, or punctuation
/// behaves like a consonant for decoding purposes, including the two
/// pre-composed conjuncts (क्ष, ज्ञ) — they end in an inherent-a
/// consonant sound just like a plain consonant does.
final Set<int> _nepaliNonConsonantIds = {
  ..._nepaliVowelIds,
  _kNepaliHalantId,
  3, 47, 31, 49, 1, 55, // signs / punctuation
  ..._kVocalicTwoCellCodes.keys,
};
final Set<int> _nepaliConsonantIds =
    _nepaliMap.keys.where((id) => !_nepaliNonConsonantIds.contains(id)).toSet();

/// Decodes one word's worth of Nepali class ids, resolving the vowel vs.
/// matra ambiguity, the halant reorder, and the vocalic-r two-cell codes
/// from context instead of a fixed per-cell table.
String _decodeNepaliWord(List<int> classIds) {
  final buf = StringBuffer();
  bool prevConsonant = false;
  bool pendingHalant = false;
  final n = classIds.length;
  int i = 0;

  while (i < n) {
    final id = classIds[i];

    // Two-cell vocalic r/rr lookahead.
    if (i + 1 < n &&
        _kVocalicTwoCellCodes.containsKey(id) &&
        classIds[i + 1] == _kVocalicRLookaheadPartner) {
      final (matra, vowel) = _kVocalicTwoCellCodes[id]!;
      buf.write(prevConsonant ? matra : vowel);
      prevConsonant = false;
      i += 2;
      continue;
    }

    if (id == _kNepaliHalantId) {
      // Rule 18: halant precedes (in braille) the consonant it silences.
      // Hold it and emit "consonant + ्" once that consonant arrives.
      pendingHalant = true;
      prevConsonant = false;
      i += 1;
      continue;
    }

    if (id == _kNepaliAId && prevConsonant) {
      // Rule-24 hiatus signal (e.g. गई): swallow it; the vowel cell that
      // follows renders as a full independent letter, not a matra.
      prevConsonant = false;
      i += 1;
      continue;
    }

    final char = _nepaliMap[id];
    if (char == null || char.isEmpty) {
      i += 1;
      continue;
    }

    if (_nepaliConsonantIds.contains(id)) {
      if (pendingHalant) {
        buf.write(char);
        buf.write('्');
        pendingHalant = false;
        prevConsonant = false;
      } else {
        buf.write(char);
        prevConsonant = true;
      }
      i += 1;
      continue;
    }

    if (_nepaliVowelIds.contains(id)) {
      final matra = prevConsonant ? _nepaliVowelToMatra[id] : null;
      buf.write(matra ?? char);
      prevConsonant = false;
      i += 1;
      continue;
    }

    // Signs / punctuation.
    buf.write(char);
    prevConsonant = false;
    i += 1;
  }

  return buf.toString();
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
    case BrailleLanguage.nepali:
      return _nepaliMap[classId] ?? '';
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

      final cells = line.words[wi].cells as List;

      if (language == BrailleLanguage.nepali) {
        // Context-aware path: needs the whole word's id sequence at once
        // to resolve matras, halant reordering, and vocalic-r codes (see
        // `_decodeNepaliWord` above).
        final ids = cells.map((c) => c.detection.classId as int).toList();
        buf.write(_decodeNepaliWord(ids));
        continue;
      }

      bool capitalNext = false;
      bool capsLock = false;
      bool numberMode = false;

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