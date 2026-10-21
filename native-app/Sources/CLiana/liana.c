// arm64-native Liana HID protocol, extracted from the vendor's x86_64 addon.
// See port/native/liana-hid/src/hid_wrap.cc for the reverse-engineering notes.
#include "liana.h"

#include <IOKit/hidsystem/IOHIDLib.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>

#include "hidapi.h"

// Declared in hidapi/mac/hid.c but absent from the public header.
extern void hid_darwin_set_open_exclusive(int open_exclusive);

struct LianaHandle {
    hid_device *dev;
    int is_ble;
    int vendor_id;
    unsigned char ver;
    unsigned char flags;
    unsigned char base;
    unsigned char max_payload;
    char path[LIANA_PATH_MAX];
};

// Command name -> (cmd, arg), recovered from the vendor's writeWithName table.
typedef struct {
    const char *name;
    unsigned char cmd;
    unsigned char arg;
} CmdSpec;

static const CmdSpec kCommands[] = {
    {"readDeviceType", 0x01, 0x01},
    {"readFirmwareVersion", 0x01, 0x03},
    {"readHardwareState", 0x01, 0x09},
    {"readBatteryPercentage", 0x81, 0x11},
    {"resetPowerOnTime", 0x01, 0x0b},
    {"readPowerOnTime", 0x81, 0x02},
    {"writeBacklightAuto", 0x01, 0x0c},
    {"readUDID", 0x81, 0x0d},
    {"writeUDID", 0x01, 0x0e},
    {"deviceAlias", 0x04, 0x00},
    {"getCombinationMode", 0x81, 0xf1},
    {"rfMode", 0x01, 0x13},
    {"usbSwitchState", 0x01, 0x20},
    {"usbPlugMode", 0x01, 0x23},
    {"keycapStyle", 0x01, 0x31},
    {"writeIapMode", 0x03, 0x00},
    {"readIapMode", 0x03, 0x00},
    {"readIapFwVersion", 0x01, 0x03},
    {"writeIapMemory", 0x04, 0x00},
    {"writeEraseMemory", 0x05, 0x00},
    // Measured on an Anne Pro 2D: reading is 0x90/0x01 with latency=3,
    // writing is 0x10/0x01 with the layer byte prepended to the payload.
    // The vendor renderer uses 0x10/0x02 for reads, which this firmware
    // ignores; that is a vendor bug, not a protocol variant.
    {"readKeyboardLayer", 0x90, 0x01},
    {"writeKeyboardLayer", 0x10, 0x01},
    {"uploadKbdLayout", 0x10, 0x02},
    {"kbdMagicFn", 0x10, 0x03},
    {"kbdTap", 0x10, 0x05},
    {"kbdCapsType", 0x20, 0x09},
    {"kbdTapkeyTimeout", 0x10, 0x13},
    {"kbdLayoutType", 0x10, 0xf1},
    {"toggleLed", 0x20, 0x01},
    {"previewLightWithoutThrottle", 0x03, 0x00},
    {"downloadLight", 0x20, 0x02},
    {"lightHoldOn", 0x20, 0x0d},
    {"backlightBrightness", 0x20, 0x15},
    {"indicatorMode", 0x20, 0x18},
    {"indicatorColor", 0x20, 0x1a},
    {"readCapslockLedColor", 0xa0, 0x1c},
    {"writeCapslockLedColor", 0x20, 0x1c},
    {"readLedPowerMode", 0x20, 0x1e},
    {"writeLedPowerMode", 0x20, 0x1f},
    {"lightbarIndicatorMode", 0x20, 0x22},
    {"lightbarBrightness", 0x20, 0x23},
    {"keylightIndicatorMode", 0x20, 0x25},
    {"lightbarIndicatorColor", 0x20, 0x26},
    {"fireflyIndicatorMode", 0x20, 0x28},
    {"keyLedOCC1", 0x20, 0x2a},
    {"keyLedOCC2", 0x20, 0x2b},
    {"writeAudioVisualConfig", 0x21, 0x01},
    {"writeAudioVisualData", 0x21, 0x02},
    {"readMacroConfig", 0xb0, 0x0c},
    {"readMacroActiveList", 0x30, 0x07},
    {"readMacroMap", 0xb0, 0x0b},
    {"readMacro", 0x30, 0x09},
    {"clearMacro", 0x30, 0x0a},
    {"writeMacroConfig", 0x30, 0x0c},
    {"checkMacroVersion", 0xb0, 0x10},
    {"setBleOn", 0x40, 0x01},
    {"deleteBleHost", 0x40, 0x05},
    {"readBleMac", 0x40, 0x30},
    {"akdmAllUp", 0x52, 0x01},
    {"akdmAllDown", 0x52, 0x02},
    {"akdmSingle", 0x52, 0x03},
    {"vMouseCursorSpeed", 0x60, 0x01},
    {"vMouseSpeedX", 0x60, 0x03},
    {"vMouseCursorGain", 0x60, 0x06},
    {"writeOledImg", 0x70, 0x01},
    {"writeOledChar", 0x70, 0x08},
    {"writeOledDateTime", 0x70, 0x07},
    {"writeOledMonitor", 0x70, 0x09},
    {"oledTimeFormat", 0x70, 0x0a},
    {"wl24gAddress", 0x41, 0x01},
    {"wl24gSlave", 0xc1, 0x02},
    {"wl24gChannel", 0x41, 0x05},
    {"wl24gRestart", 0x41, 0x06},
    {"wl24gRunMode", 0x41, 0x07},
    {"enterPairMode", 0x41, 0x0d},
    {"exitPairMode", 0x41, 0x0e},
    {"module24gAddress", 0x41, 0x01},
    {"module24gChannel", 0x41, 0x05},
    {"module24gSyncId", 0x41, 0x08},
    {"module24gReinit", 0x41, 0x09},
    {"module24gMasterId", 0x41, 0x0a},
    {"module24gMasterInfo", 0x41, 0x0b},
    {"argbPreview", 0x10, 0x00},
};

static const CmdSpec *FindCommand(const char *name) {
    for (size_t i = 0; i < sizeof kCommands / sizeof kCommands[0]; ++i) {
        if (strcmp(name, kCommands[i].name) == 0) return &kCommands[i];
    }
    return NULL;
}

static size_t ReplyLenFor(const char *name) {
    if (strcmp(name, "readDeviceType") == 0) return 2;
    if (strcmp(name, "readFirmwareVersion") == 0) return 6;
    if (strcmp(name, "readIapFwVersion") == 0) return 6;
    if (strcmp(name, "readBatteryPercentage") == 0) return 1;
    if (strcmp(name, "readPowerOnTime") == 0) return 4;
    if (strcmp(name, "readHardwareState") == 0) return 8;
    if (strcmp(name, "readUDID") == 0) return 32;
    return 0;  // unknown: use the frame's declared length
}

int liana_command(const char *name, uint8_t *cmd, uint8_t *arg, size_t *reply_len) {
    const CmdSpec *spec = FindCommand(name);
    if (!spec) return -1;
    if (cmd) *cmd = spec->cmd;
    if (arg) *arg = spec->arg;
    if (reply_len) *reply_len = ReplyLenFor(name);
    return 0;
}

static int64_t NowMs(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static size_t PutHeader(LianaHandle *h, uint8_t *frame, uint8_t cmd, uint8_t arg,
                        uint8_t dist, uint8_t seq, uint8_t last_index,
                        uint8_t remainder, size_t len) {
    int multi = !(last_index == 0 && remainder == 0);
    unsigned field = (unsigned)(len + 2);
    frame[0] = 0x7b;
    frame[1] = h->ver;
    frame[2] = (uint8_t)((dist << 4) | 0x01);
    frame[3] = (uint8_t)(multi ? (0x80 | (seq & 0x7f)) : (seq & 0x0f));
    frame[4] = (uint8_t)(field & 0xff);
    frame[5] = (uint8_t)((field >> 8) & 0xff);
    frame[6] = 0x00;
    frame[7] = 0x7d;
    frame[8] = cmd;
    frame[9] = arg;
    return 10;
}

static int SendCommand(LianaHandle *h, uint8_t cmd, uint8_t arg, uint8_t dist,
                       const uint8_t *payload, size_t total) {
    const size_t chunk = h->max_payload ? h->max_payload : 1;
    const size_t count = total ? (total + chunk - 1) / chunk : 1;
    uint8_t frame[128];
    uint8_t wire[65];

    for (size_t i = 0; i < count; ++i) {
        const size_t off = i * chunk;
        const size_t len = total ? (i + 1 == count ? total - off : chunk) : 0;
        const size_t remain = total ? (total - off) % chunk : 0;
        size_t n = PutHeader(h, frame, cmd, arg, dist, (uint8_t)i,
                             (uint8_t)(count - 1), (uint8_t)(i + 1 == count ? 0 : remain), len);
        if (len) memcpy(frame + n, payload + off, len);
        n += len;

        // Report id 0 lives in byte 0; the Liana payload starts at byte 1 and
        // the rest is zero padding to the device's 64-byte report size.
        memset(wire, 0, sizeof wire);
        if (n > sizeof wire - 1) n = sizeof wire - 1;
        memcpy(wire + 1, frame, n);
        if (hid_write(h->dev, wire, sizeof wire) < 0) return -1;
    }
    return 0;
}

int liana_write(LianaHandle *h, const char *command, const uint8_t *payload,
                size_t length, int dist) {
    const CmdSpec *spec = FindCommand(command);
    if (!spec || !h || !h->dev) return -1;
    return SendCommand(h, spec->cmd, spec->arg, (uint8_t)dist, payload, length);
}

int liana_transact(LianaHandle *h, const char *command, const uint8_t *payload,
                   size_t length, int dist, uint8_t *reply, size_t reply_max,
                   int timeout_ms) {
    const CmdSpec *spec = FindCommand(command);
    if (!spec || !h || !h->dev) return -1;
    if (SendCommand(h, spec->cmd, spec->arg, (uint8_t)dist, payload, length) < 0) return -1;

    const int64_t deadline = NowMs() + (timeout_ms > 0 ? timeout_ms : 1000);
    uint8_t buf[64];
    while (NowMs() < deadline) {
        int n = hid_read_timeout(h->dev, buf, sizeof buf, 50);
        if (n <= 0) continue;

        // Locate the 0x7d marker: hidapi sometimes prepends the report id and
        // sometimes does not, so a fixed offset does not work.
        int marker = -1;
        for (int i = 1; i < n - 2 && i < 12; ++i) {
            if (buf[i] == 0x7d) { marker = i; break; }
        }
        if (marker < 0) continue;

        const uint8_t rcmd = buf[marker + 1];
        const uint8_t rarg = buf[marker + 2];
        if (rcmd != spec->cmd || rarg != spec->arg) continue;  // unsolicited frame

        const size_t payload_at = (size_t)marker + 3;
        const unsigned declared = (unsigned)buf[marker - 3] | ((unsigned)buf[marker - 2] << 8);
        size_t payload_len = declared >= 2 ? declared - 2 : 0;
        const size_t want = ReplyLenFor(command);
        if (want > 0) payload_len = want;
        if (payload_at + payload_len > (size_t)n) {
            payload_len = (size_t)n > payload_at ? (size_t)n - payload_at : 0;
        }
        if (payload_len > reply_max) payload_len = reply_max;
        if (reply) memcpy(reply, buf + payload_at, payload_len);
        return (int)payload_len;
    }
    return -1;
}

int liana_read_command_payload(LianaHandle *h, const char *command, int dist,
                               const uint8_t *payload, size_t length,
                               uint8_t *reply, size_t reply_max, int timeout_ms) {
    const CmdSpec *spec = FindCommand(command);
    if (!spec || !h || !h->dev) return -1;
    if (SendCommand(h, spec->cmd, spec->arg, (uint8_t)dist, payload, length) < 0) return -1;

    const int64_t deadline = NowMs() + (timeout_ms > 0 ? timeout_ms : 1500);
    size_t total = 0;
    uint8_t buf[64];
    while (NowMs() < deadline) {
        int n = hid_read_timeout(h->dev, buf, sizeof buf, 50);
        if (n <= 0) continue;

        int marker = -1;
        for (int i = 1; i < n - 2 && i < 12; ++i) {
            if (buf[i] == 0x7d) { marker = i; break; }
        }
        if (marker < 4) continue;
        if (buf[marker + 1] != spec->cmd || buf[marker + 2] != spec->arg) {
            if (getenv("LIANA_TRACE")) {
                fprintf(stderr, "RX cmd=%02x arg=%02x marker=%d n=%d\n",
                        buf[marker + 1], buf[marker + 2], marker, n);
            }
            continue;
        }

        const unsigned char seq = buf[marker - 4];
        const int multi = (seq & 0x80) != 0;
        const size_t payload_at = (size_t)marker + 3;
        const unsigned declared = (unsigned)buf[marker - 3] | ((unsigned)buf[marker - 2] << 8);
        size_t payload_len = declared >= 2 ? declared - 2 : 0;
        if (payload_at + payload_len > (size_t)n) {
            payload_len = (size_t)n > payload_at ? (size_t)n - payload_at : 0;
        }
        if (total + payload_len > reply_max) payload_len = reply_max - total;
        if (reply && payload_len) memcpy(reply + total, buf + payload_at, payload_len);
        total += payload_len;
        if (!multi) break;
    }
    return total > 0 ? (int)total : -1;
}

int liana_poll(LianaHandle *h, uint8_t *buffer, size_t max, int timeout_ms) {
    if (!h || !h->dev) return -1;
    return hid_read_timeout(h->dev, buffer, max, timeout_ms);
}

static void CopyWide(char *dst, size_t cap, const wchar_t *src) {
    if (!dst || cap == 0) return;
    dst[0] = '\0';
    if (!src) return;
    wcstombs(dst, src, cap - 1);
    dst[cap - 1] = '\0';
}

int liana_init(void) {
    if (hid_init() != 0) return -1;
    // Seizing the keyboard tears it out of the IOHID registry; the vendor
    // opens non-exclusively.
    hid_darwin_set_open_exclusive(0);
    return 0;
}

int liana_enumerate(liana_device_info *out, int max) {
    struct hid_device_info *list = hid_enumerate(0, 0);
    int n = 0;
    for (struct hid_device_info *p = list; p; p = p->next) {
        // Skip macOS virtual nodes; they reject every output report.
        if (p->path && strstr(p->path, "IOHIDUserDevice") != NULL) continue;
        if (n >= max) break;
        liana_device_info *d = &out[n++];
        memset(d, 0, sizeof *d);
        d->vendor_id = p->vendor_id;
        d->product_id = p->product_id;
        d->interface_number = p->interface_number;
        d->usage_page = p->usage_page;
        d->usage = p->usage;
        d->release_number = p->release_number;
        d->is_usb = p->interface_number >= 0;
        if (p->path) { strncpy(d->path, p->path, LIANA_PATH_MAX - 1); }
        CopyWide(d->product, LIANA_STRING_MAX, p->product_string);
        CopyWide(d->manufacturer, LIANA_STRING_MAX, p->manufacturer_string);
        CopyWide(d->serial, LIANA_STRING_MAX, p->serial_number);
    }
    hid_free_enumeration(list);
    return n;
}

LianaHandle *liana_open(const char *path, int is_usb, int vendor_id) {
    if (!path) return NULL;
    hid_device *dev = hid_open_path(path);
    if (!dev) return NULL;

    LianaHandle *h = (LianaHandle *)calloc(1, sizeof *h);
    if (!h) { hid_close(dev); return NULL; }
    h->dev = dev;
    h->is_ble = !is_usb;
    h->vendor_id = vendor_id;
    strncpy(h->path, path, LIANA_PATH_MAX - 1);
    if (h->is_ble) {
        h->ver = 0x10; h->flags = 0x01; h->base = 0x00; h->max_payload = 0x35;
    } else {
        h->ver = 0x12; h->flags = 0x01; h->base = 0x02;
        h->max_payload = vendor_id == 0x7d7 ? 0x36 : 0x08;
    }
    return h;
}

void liana_close(LianaHandle *h) {
    if (!h) return;
    if (h->dev) hid_close(h->dev);
    free(h);
}

const char *liana_last_error(LianaHandle *h) {
    if (!h || !h->dev) return "no device";
    const wchar_t *err = hid_error(h->dev);
    if (!err) return NULL;
    static _Thread_local char buf[256];
    wcstombs(buf, err, sizeof buf - 1);
    buf[sizeof buf - 1] = '\0';
    return buf;
}

int liana_check_listen_access(void) {
    IOHIDAccessType t = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
    if (t == kIOHIDAccessTypeGranted) return 1;
    if (t == kIOHIDAccessTypeDenied) return 0;
    return -1;
}

int liana_request_listen_access(void) {
    return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) ? 1 : 0;
}
