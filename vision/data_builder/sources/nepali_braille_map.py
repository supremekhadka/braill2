"""
Devanagari (Nepali) -> Bharati Braille mapping and text encoder.

Source of the dot codes: "Standard Bharati Braille Codes with Unicode
Mapped Chart", National Institute for the Empowerment of Persons with
Visual Disabilities (NIEPVD), Dehradun -- Release Date: 4 January 2025,
Section 3 "Devanagari Unicode along with Bharati Braille Codes for Hindi,
Sanskrit, Marathi, and Nepali" (pp. 11-16). This is the current official
Government of India standard; Nepal's own usage is reported to differ only
in a handful of punctuation marks (not covered here), so it is a reliable
basis for Devanagari-script Nepali.

Dot-code notation
------------------
Codes are stored as comma-separated braille *cells*, e.g. "5,1235" means
two consecutive cells: the first with only dot 5 raised, the second with
dots 1, 2, 3, 5 raised. A code with no comma such as "1245" is a single
cell with those four dots raised.

`char_id` uses the exact same convention as
`BrailleGenerator.id_to_bits()`:

    char_id + 1 == 6-bit dot bitmask   (bit (d-1) set  =>  dot d raised)

i.e. char_id == mask - 1, which is also (unicode_braille_codepoint -
0x2801), so these ids drop straight into the existing rendering pipeline.

Encoding rules implemented (NIEPVD standard, "Rules of Transcription"
items 18-24)
------------------------------------------------------------------------
- A consonant with nothing special following it keeps its silent
  inherent vowel "a" -- no extra cell is emitted (this is why Devanagari
  Braille is described as Grade-1 / abugida-like).
- A consonant followed by a dependent vowel sign (matra) is followed by
  the *full* braille cell of that vowel (Devanagari Braille never uses
  diacritic-style matra shapes -- vowels are always written out in full,
  after the consonant, regardless of where the matra sits in print).
- A consonant followed by virama (halant) is, in braille, *preceded* by
  the halant cell instead: the halant "moves" in front of the consonant
  it silences (rule 18). E.g. print "धर्म" (ध-र-्-म) becomes braille
  cells [ध][halant][र][म], not [ध][र][halant][म].
- A consonant directly followed by an *independent* vowel letter (not a
  matra -- true hiatus, e.g. "गई") gets an inserted dot-1 'अ' cell
  between them (rule 24).

This is a Grade-1, uncontracted approximation intended for generating
*visually and statistically realistic* Braille cell sequences for a
detection dataset -- it purposefully does not implement every disambig­
uation edge case in the standard (multi-vowel chains beyond one hiatus,
verse/footnote formatting, etc.).
"""
from __future__ import annotations

# Sentinel for "word gap" -- consumes a grid column but stamps no dots.
SPACE = -1


def _dots_to_mask(dot_str: str) -> int:
    mask = 0
    for ch in dot_str:
        if ch.isdigit():
            mask |= 1 << (int(ch) - 1)
    return mask


def _dots_to_char_id(dot_str: str) -> int:
    return _dots_to_mask(dot_str) - 1


def _cellcode_to_char_ids(cellcode: str) -> list[int]:
    """'5,1235' (two cells) -> [char_id(dots=5), char_id(dots=1235)]."""
    return [_dots_to_char_id(part.strip()) for part in cellcode.split(",")]


# --- Raw dot-code table, transcribed from the NIEPVD standard -------------
# Keys are Devanagari Unicode characters. Values are dot-code strings as
# printed in the source table ("," => new braille cell).
_RAW_TABLE: dict[str, str] = {
    # Various signs
    "\u0901": "3",          # ँ chandrabindu
    "\u0902": "56",         # ं anusvara
    "\u0903": "6",          # ः visarga
    "\u093C": "5",          # ़ nukta (combining)
    "\u093D": "2",          # ऽ avagraha

    # Independent vowels
    "\u0905": "1",          # अ a
    "\u0906": "345",        # आ aa
    "\u0907": "24",         # इ i
    "\u0908": "35",         # ई ii
    "\u0909": "136",        # उ u
    "\u090A": "1256",       # ऊ uu
    "\u090B": "5,1235",     # ऋ vocalic r
    "\u090C": "5,123",      # ऌ vocalic l
    "\u090F": "15",         # ए e
    "\u0910": "34",         # ऐ ai
    "\u0911": "1346",       # ऑ chandra o
    "\u0913": "135",        # ओ o
    "\u0914": "246",        # औ au
    "\u0960": "6,1235",     # ॠ vocalic rr
    "\u0961": "6,123",      # ॡ vocalic ll

    # Consonants
    "\u0915": "13",         # क ka
    "\u0916": "46",         # ख kha
    "\u0917": "1245",       # ग ga
    "\u0918": "126",        # घ gha
    "\u0919": "346",        # ङ nga
    "\u091A": "14",         # च cha
    "\u091B": "16",         # छ chha
    "\u091C": "245",        # ज ja
    "\u091D": "356",        # झ jha
    "\u091E": "25",         # ञ nya
    "\u091F": "23456",      # ट tta
    "\u0920": "2456",       # ठ ttha
    "\u0921": "1246",       # ड dda
    "\u0922": "123456",     # ढ ddha
    "\u0923": "3456",       # ण nna
    "\u0924": "2345",       # त ta
    "\u0925": "1456",       # थ tha
    "\u0926": "145",        # द da
    "\u0927": "2346",       # ध dha
    "\u0928": "1345",       # न na
    "\u092A": "1234",       # प pa
    "\u092B": "124",        # फ pha
    "\u092C": "12",         # ब ba
    "\u092D": "45",         # भ bha
    "\u092E": "134",        # म ma
    "\u092F": "13456",      # य ya
    "\u0930": "1235",       # र ra
    "\u0932": "123",        # ल la
    "\u0933": "456",        # ळ lla
    "\u0935": "1236",       # व va
    "\u0936": "146",        # श sha
    "\u0937": "12346",      # ष ssa
    "\u0938": "234",        # स sa
    "\u0939": "125",        # ह ha

    # Nukta-derived consonants (Persian-origin loanword sounds)
    "\u0958": "5,13",       # क़ qa
    "\u0959": "5,46",       # ख़ khha
    "\u095A": "5,1245",     # ग़ ghha
    "\u095B": "5,245",      # ज़ za
    "\u095C": "12456",      # ड़ ddda
    "\u095D": "5,12456",    # ढ़ rha
    "\u095E": "5,124",      # फ़ fa
    "\u095F": "5,13456",    # य़ yya

    # Dependent vowel signs (matras) -- identical dot code to the matching
    # independent vowel; see module docstring.
    "\u093E": "345",        # ा aa-matra
    "\u093F": "24",         # ि i-matra
    "\u0940": "35",         # ी ii-matra
    "\u0941": "136",        # ु u-matra
    "\u0942": "1256",       # ू uu-matra
    "\u0943": "5,1235",     # ृ vocalic-r matra
    "\u0944": "6,1235",     # ॄ vocalic-rr matra
    "\u0945": "1346",       # ॅ chandra-e matra
    "\u0947": "15",         # े e-matra
    "\u0948": "34",         # ै ai-matra
    "\u0949": "1346",       # ॉ chandra-o matra
    "\u094B": "135",        # ो o-matra
    "\u094C": "246",        # ौ au-matra

    # Virama / halant
    "\u094D": "4",          # ्

    # Digits (number-sign cell followed by the letter-shape cell)
    "\u0966": "3456,245",   # ०
    "\u0967": "3456,1",     # १
    "\u0968": "3456,12",    # २
    "\u0969": "3456,14",    # ३
    "\u096A": "3456,145",   # ४
    "\u096B": "3456,15",    # ५
    "\u096C": "3456,124",   # ६
    "\u096D": "3456,1245",  # ७
    "\u096E": "3456,125",   # ८
    "\u096F": "3456,24",    # ९

    # Punctuation actually given a numeric dot code in the standard.
    "\u0964": "256",        # । danda (phrase/sentence separator)
    "\u0965": "256,256",    # ॥ double danda (approximated as danda x2)
    ",": "2",                # comma -> Dot 2 (per "Rules of Transcription")
    ".": "46",                # full stop / decimal point -> Dot 4,6
}

# Three-codepoint conjuncts that get their OWN single braille cell instead
# of being spelled out as consonant + halant + consonant.
_CONJUNCTS: dict[str, str] = {
    "\u0915\u094D\u0937": "12345",  # क्ष ksha
    "\u091C\u094D\u091E": "156",    # ज्ञ jna / gya
}

DEVANAGARI_TO_IDS: dict[str, list[int]] = {
    ch: _cellcode_to_char_ids(code) for ch, code in _RAW_TABLE.items()
}
CONJUNCT_TO_IDS: dict[str, list[int]] = {
    ch: _cellcode_to_char_ids(code) for ch, code in _CONJUNCTS.items()
}

DOT1_A = _dots_to_char_id("1")   # explicit अ, used for vowel-hiatus insertion
HALANT = _dots_to_char_id("4")   # halant / virama cell

_VOWEL_LETTERS = set("\u0905\u0906\u0907\u0908\u0909\u090A\u090B\u090C"
                      "\u090F\u0910\u0911\u0913\u0914\u0960\u0961")
_MATRAS = set("\u093E\u093F\u0940\u0941\u0942\u0943\u0944\u0945\u0947"
              "\u0948\u0949\u094B\u094C")
_CONSONANTS = set("\u0915\u0916\u0917\u0918\u0919\u091A\u091B\u091C\u091D"
                   "\u091E\u091F\u0920\u0921\u0922\u0923\u0924\u0925\u0926"
                   "\u0927\u0928\u092A\u092B\u092C\u092D\u092E\u092F\u0930"
                   "\u0932\u0933\u0935\u0936\u0937\u0938\u0939\u0958\u0959"
                   "\u095A\u095B\u095C\u095D\u095E\u095F")
_VIRAMA = "\u094D"


def text_to_char_ids(text: str) -> list[int]:
    """
    Convert a Nepali/Devanagari string into a flat sequence of Braille
    char_ids, one entry per physical braille cell (multiple ids for
    two-cell signs such as digits or nukta letters). `SPACE` (-1) marks a
    word gap and should not be stamped as a cell by the caller.

    Unmapped characters (stray Latin letters, emoji, uncommon symbols,
    etc.) are silently skipped rather than emitting an incorrect shape.
    """
    ids: list[int] = []
    n = len(text)
    i = 0
    while i < n:
        ch = text[i]

        if ch.isspace():
            i += 1
            continue

        # Three-codepoint conjuncts (ksha, jna) are checked first.
        triple = text[i:i + 3]
        if triple in CONJUNCT_TO_IDS:
            ids.extend(CONJUNCT_TO_IDS[triple])
            i += 3
            continue

        if ch in _CONSONANTS:
            cons_ids = DEVANAGARI_TO_IDS[ch]
            nxt = text[i + 1] if i + 1 < n else ""

            if nxt == _VIRAMA:
                # Halant precedes the consonant it silences (rule 18).
                ids.append(HALANT)
                ids.extend(cons_ids)
                i += 2
            elif nxt in _MATRAS:
                ids.extend(cons_ids)
                ids.extend(DEVANAGARI_TO_IDS[nxt])
                i += 2
            elif nxt in _VOWEL_LETTERS:
                # True hiatus: independent vowel directly after a
                # consonant, e.g. "गई" (rule 24).
                ids.extend(cons_ids)
                ids.append(DOT1_A)
                ids.extend(DEVANAGARI_TO_IDS[nxt])
                i += 2
            else:
                ids.extend(cons_ids)
                i += 1
            continue

        if ch in DEVANAGARI_TO_IDS:
            ids.extend(DEVANAGARI_TO_IDS[ch])
            i += 1
            continue

        # Unmapped character: skip.
        i += 1

    return ids


def text_to_words(text: str) -> list[list[int]]:
    """Split `text` on whitespace and encode each word independently.

    Convenience wrapper used by the page layout code, which needs to
    word-wrap without ever splitting a word's cells across lines.
    """
    return [text_to_char_ids(w) for w in text.split()]