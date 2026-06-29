def apply_braille_rules(text_line: str) -> str:
    """
    Apply Braille capitalisation and numeric-mode indicators to a raw character sequence.

    Indicators consumed:
      [CAPS][CAPS]  — enter word-level uppercase mode
      [CAPS]        — capitalise the single following letter
      [NUM]      — enter numeric mode; maps a–j -> 1–0 until a space or punctuation
    """
    i = 0
    output = ""
    upper_mode = False
    number_mode = False

    while i < len(text_line):
        if text_line.startswith("[CAPS][CAPS]", i):
            upper_mode = True
            i += len("[CAPS][CAPS]")
            continue

        if text_line.startswith("[CAPS]", i):
            i += len("[CAPS]")
            if i < len(text_line):
                output += text_line[i].upper()
                i += 1
            continue

        if text_line.startswith("[NUM]", i):
            number_mode = True
            i += len("[NUM]")
            continue

        ch = text_line[i]

        if ch in " ,.;:!?-()\"'":
            number_mode = False
            upper_mode = False
            output += ch
            i += 1
            continue

        if number_mode and ch.isalpha():
            num_map = {
                "a": "1", "b": "2", "c": "3", "d": "4", "e": "5",
                "f": "6", "g": "7", "h": "8", "i": "9", "j": "0",
            }
            if ch.lower() in num_map:
                output += num_map[ch.lower()]
            else:
                number_mode = False
                output += ch.upper() if upper_mode else ch
            i += 1
            continue

        if ch == " ":
            upper_mode = False

        output += ch.upper() if upper_mode else ch
        i += 1

    return output