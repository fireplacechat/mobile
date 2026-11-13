#include "PreviewMemory.h"

// Volatile stores cannot be elided before freeing the caller-owned buffer.
// This needs no platform-specific secure-memset availability or dependency.
void fireplace_preview_wipe(void *memory, size_t length) {
    volatile unsigned char *bytes = (volatile unsigned char *)memory;
    for (size_t index = 0; index < length; index++) bytes[index] = 0;
}
