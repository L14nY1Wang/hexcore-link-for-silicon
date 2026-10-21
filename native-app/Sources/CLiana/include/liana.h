#ifndef LIANA_H
#define LIANA_H

#include <stddef.h>
#include <stdint.h>

#define LIANA_PATH_MAX 512
#define LIANA_STRING_MAX 128

typedef struct {
    uint16_t vendor_id;
    uint16_t product_id;
    int32_t interface_number;
    int32_t usage_page;
    int32_t usage;
    int32_t release_number;
    uint8_t is_usb;
    char path[LIANA_PATH_MAX];
    char product[LIANA_STRING_MAX];
    char manufacturer[LIANA_STRING_MAX];
    char serial[LIANA_STRING_MAX];
} liana_device_info;

typedef struct LianaHandle LianaHandle;

/// hid_init() plus the vendor's non-exclusive open mode.
int liana_init(void);

/// Enumerate keyboards. Returns the number written to `out` (<= max).
int liana_enumerate(liana_device_info *out, int max);

/// Open a device by HID path. `is_usb` mirrors the vendor API: USB devices
/// report interface_number >= 0.
LianaHandle *liana_open(const char *path, int is_usb, int vendor_id);
void liana_close(LianaHandle *handle);

/// Look up a command's wire bytes. Returns 0 on success, -1 for unknown names.
int liana_command(const char *name, uint8_t *cmd, uint8_t *arg, size_t *reply_len);

/// Send a command with no reply handling. Returns 0 on success.
int liana_write(LianaHandle *handle, const char *command,
                const uint8_t *payload, size_t length, int dist);

/// Send a command and wait for its reply.
/// Returns the reply size, or -1 on timeout/error. `reply` receives at most
/// `reply_max` bytes. `dist` is the target MCU (3 = main).
int liana_transact(LianaHandle *handle, const char *command,
                   const uint8_t *payload, size_t length, int dist,
                   uint8_t *reply, size_t reply_max, int timeout_ms);

/// Send a command with an optional payload and collect its reply, reassembling
/// the protocol's multi-chunk frames. Returns the payload size or -1.
int liana_read_command_payload(LianaHandle *handle, const char *command, int dist,
                               const uint8_t *payload, size_t length,
                               uint8_t *reply, size_t reply_max, int timeout_ms);

static inline int liana_read_command(LianaHandle *handle, const char *command, int dist,
                                     uint8_t *reply, size_t reply_max, int timeout_ms) {
    return liana_read_command_payload(handle, command, dist, NULL, 0, reply, reply_max, timeout_ms);
}

/// Raw read from the device (no command). Returns bytes or -1.
int liana_poll(LianaHandle *handle, uint8_t *buffer, size_t max, int timeout_ms);

/// TCC "Input Monitoring" state: 1 granted, 0 denied, -1 unknown.
int liana_check_listen_access(void);
/// Ask macOS to show the Input Monitoring prompt. Returns 1 if granted.
int liana_request_listen_access(void);
const char *liana_last_error(LianaHandle *handle);

#endif
