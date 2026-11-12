/// Firestore error codes that mean a write definitely did NOT commit. After
/// one of these the advanced ratchets can be put back and the person told
/// plainly that nothing was sent. Any other failure (network lost, timeout)
/// is ambiguous: the message may exist.
const definitelyNotPublished = {
  'permission-denied',
  'invalid-argument',
  'failed-precondition',
  'not-found',
  'already-exists',
  'resource-exhausted',
  'unauthenticated',
};

/// The rules refused the message: the pacing rule, a block, or a request
/// that may not be answered.
const permissionDeniedText =
    'This message could not be sent. You may be sending too fast, or the '
    'other person may have blocked you or is not accepting messages.';

/// Plain words for any other definite refusal, by error code.
String refusedText(String code) => switch (code) {
  'resource-exhausted' =>
    'The server is busy or its free usage limit has been reached, so nothing '
        'was sent. Try again later.',
  'invalid-argument' =>
    'This message could not be sent (it may be too large), so nothing was '
        'sent. Try a shorter message.',
  'unauthenticated' =>
    'Your sign-in has expired, so nothing was sent. Sign in again and retry.',
  _ => 'This message could not be sent, so nothing was sent. Please try again.',
};
