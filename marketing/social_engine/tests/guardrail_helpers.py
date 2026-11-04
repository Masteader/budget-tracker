"""Ways of hiding banned wording from a word list, shared by the guardrail tests.

Rule 05 asks for tests that prove behaviour. Here that means a rule must still fire once a
sample has been dressed up with diacritics, kashida, spacing, hidden characters, look-alike
letters or other digit forms.
"""

ARABIC_LETTERS = range(0x0621, 0x064B)


def with_fatha(text: str) -> str:
    return "".join(
        f"{ch}\u064e" if ord(ch) in ARABIC_LETTERS and ch != "\u0621" else ch for ch in text
    )


def with_kashida(text: str) -> str:
    return "".join(f"{ch}\u0640" if ord(ch) in ARABIC_LETTERS else ch for ch in text)


def with_zero_width(text: str) -> str:
    return "\u200b".join(text)


def with_joiners(text: str) -> str:
    return "\u200d".join(text)


def with_spaced_letters(text: str) -> str:
    return "   ".join(" ".join(word) for word in text.split())


def with_extra_spaces(text: str) -> str:
    return text.replace(" ", "   ")


def with_arabic_digits(text: str) -> str:
    return text.translate({ord(str(digit)): 0x0660 + digit for digit in range(10)})


def with_full_width(text: str) -> str:
    return "".join(chr(ord(ch) + 0xFEE0) if ch.isascii() and ch.isalnum() else ch for ch in text)


def with_cyrillic(text: str) -> str:
    return text.translate(str.maketrans("aeopc", "\u0430\u0435\u043e\u0440\u0441"))


EVASIONS = {
    "fatha": with_fatha,
    "kashida": with_kashida,
    "zero_width": with_zero_width,
    "joiners": with_joiners,
    "spaced_letters": with_spaced_letters,
    "extra_spaces": with_extra_spaces,
    "arabic_digits": with_arabic_digits,
    "full_width": with_full_width,
    "cyrillic": with_cyrillic,
    "upper": str.upper,
}
