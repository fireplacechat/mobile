/// Text policy counts Unicode code points, not UTF-16 units or grapheme clusters.
const maxMessageCharacters = 16384;
const messageLimitError = 'Messages can contain at most 16,384 characters.';
const oversizedPreviewCharacters = 512;

int messageCharacters(String text) => text.runes.length;

bool messageTooLong(String text) =>
    text.runes.take(maxMessageCharacters + 1).length > maxMessageCharacters;

String clipMessage(String text, int characters) =>
    String.fromCharCodes(text.runes.take(characters));
