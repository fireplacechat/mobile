#include "fireplace_crypto_exports.h"
#include "fireplace_crypto.h"

// Dart resolves these symbols by name. Keep their addresses reachable from
// the registered plugin so the static linker cannot discard unused bridges.
typedef void (*Symbol)(void);
static Symbol volatile bridges[] = {
  (Symbol)fp_free,
  (Symbol)fp_identity_generate, (Symbol)fp_identity_public,
  (Symbol)fp_identity_sign, (Symbol)fp_identity_verify,
  (Symbol)fp_identity_consistent, (Symbol)fp_identity_fingerprint,
  (Symbol)fp_device_generate, (Symbol)fp_device_certify,
  (Symbol)fp_device_verify_cert, (Symbol)fp_device_consistent,
  (Symbol)fp_prekey_generate, (Symbol)fp_prekey_sign,
  (Symbol)fp_prekey_onetime, (Symbol)fp_prekey_verify,
  (Symbol)fp_session_initiate, (Symbol)fp_session_accept,
  (Symbol)fp_session_encrypt, (Symbol)fp_session_decrypt,
  (Symbol)fp_session_validate, (Symbol)fp_session_self_check,
  (Symbol)fp_session_load, (Symbol)fp_session_save, (Symbol)fp_session_destroy,
  (Symbol)fp_session_encrypt_handle, (Symbol)fp_session_decrypt_handle,
  (Symbol)fp_recovery_generate, (Symbol)fp_recovery_display,
  (Symbol)fp_recovery_parse, (Symbol)fp_recovery_encrypt, (Symbol)fp_recovery_decrypt,
  (Symbol)fp_link_fingerprint, (Symbol)fp_link_confirmation,
  (Symbol)fp_link_seal, (Symbol)fp_link_open, (Symbol)fp_safety_number
};

void fireplace_crypto_ensure_linked(void) {
  for (size_t index = 0; index < sizeof(bridges) / sizeof(bridges[0]); index++) {
    (void)bridges[index];
  }
}
