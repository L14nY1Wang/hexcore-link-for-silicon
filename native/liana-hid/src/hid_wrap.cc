// arm64 reimplementation of @hexcore/node-hid 1.3.11 (Liana protocol).
// Protocol recovered from the x86_64 binary shipped in Hexcore Link 2.5.9.
#include <napi.h>
#include <thread>
#include <chrono>
#include <mutex>
#include <unordered_map>
#include <queue>
#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <functional>
#include <cstring>
#include <cstdlib>
#include <cwchar>
#include <locale>
#include "hidapi.h"

// macOS gates HID input behind TCC (Input Monitoring). These two calls are the
// supported way to ask for it: CheckAccess reports the current state, and
// RequestAccess triggers the system prompt for this app's identity.
#include <IOKit/hidsystem/IOHIDLib.h>

namespace {

// Per-frame tracing costs a file open per report and the keyboard streams
// continuously, so it stays off unless explicitly requested.
static bool HidDebug() {
  static const bool on = std::getenv("HEXCORE_HID_DEBUG") != nullptr;
  return on;
}

// hidapi returns wchar_t*, and the JS side compares these strings verbatim
// (product is used both as a display name and as a filter predicate), so they
// must survive the trip as UTF-8.
static std::string WideToUtf8(const wchar_t* w) {
  if (!w) return std::string();
  std::mbstate_t st{};
  size_t need = std::wcsrtombs(nullptr, &w, 0, &st);
  if (need == static_cast<size_t>(-1)) return std::string();
  std::string out(need, '\0');
  std::mbstate_t st2{};
  const wchar_t* src = w;
  std::wcsrtombs(&out[0], &src, need, &st2);
  return out;
}

struct Frame {
  std::vector<unsigned char> bytes;
};

// Frames recovered from the shipped x86_64 HID.node. Both branches of
// Liana::readDeviceType emit the same 11 bytes -- the USB path at 0x116f0
// (movabs 0x20031107b02 + 0x17d + 0x01) and the BLE path at 0x113bc produce
// byte-identical frames, so there is only one constant here.
static const unsigned char kReadDeviceType[11] = {0x02, 0x7b, 0x10, 0x31, 0x00, 0x02,
                                                  0x00, 0x00, 0x7d, 0x01, 0x01};

// Liana::multi_package_create (@0xeff0) builds an 8-byte header then appends the
// command byte, the arg byte and the payload:
//   7b <ver> <(seq_hi<<4)|base> <seq_lo> <len_lo> <len_hi> 00 7d <cmd> <arg> ...
// Report id 0x02 is prepended by hidapi's mac backend, so it is not part of this
// buffer. `seq_hi` is 0x1 only for multi-chunk packets; `seq_lo` carries the
// chunk index.
class Liana {
 public:
  // Mirrors Liana::Liana(hid_device*, bool is_ble, string, int vendor_id). The
  // JS constructor passes `isUsb` in this slot, so USB arrives as false.
  Liana(hid_device* dev, bool is_ble, std::string path, int vendor_id)
      : dev_(dev), is_ble_(is_ble), path_(std::move(path)), vendor_id_(vendor_id) {
    if (is_ble_) {
      ver_ = 0x10;
      flags_ = 0x01;
      base_ = 0x00;
      max_payload_ = 0x35;
    } else {
      // Liana::Liana @0xd34b loads 0x212 into [rbx+0x60]: ver 0x12, flags 0x02,
      // and then base 0x02. Emitting ver 0x02 here made every generic command
      // (readUDID, firmware, battery, ...) a frame the firmware ignored.
      ver_ = 0x12;
      flags_ = 0x01;
      base_ = 0x02;
      max_payload_ = (vendor_id == 0x7d7) ? 0x36 : 0x08;
    }
  }

  hid_device* dev() const { return dev_; }
  const std::string& path() const { return path_; }
  unsigned char max_payload() const { return max_payload_; }
  bool is_ble() const { return is_ble_; }

  // Returns the sequence of reports that make up one logical packet.
  std::vector<std::vector<unsigned char>> build(unsigned char cmd, unsigned char arg,
                                                unsigned char dist,
                                                const std::vector<unsigned char>& payload) {
    std::vector<std::vector<unsigned char>> out;
    const size_t chunk = max_payload_ ? max_payload_ : 1;
    const size_t total = payload.size();
    const size_t count = (total + chunk - 1) / chunk;
    if (count == 0) {
      out.push_back(header(cmd, arg, dist, 0, 0, 0, 0));
      return out;
    }
    for (size_t i = 0; i < count; ++i) {
      const size_t off = i * chunk;
      const size_t len = std::min(chunk, total - off);
      const size_t remain = (total - off) % chunk;
      out.push_back(header(cmd, arg, dist, (unsigned char)i, (unsigned char)(count - 1),
                           (unsigned char)(i == count - 1 ? 0 : remain), len));
      auto& f = out.back();
      f.insert(f.end(), payload.begin() + off, payload.begin() + off + len);
    }
    return out;
  }

 private:
  // Byte-for-byte what the vendor hands to IOHIDDeviceSetReport (captured with
  // an IOHIDDeviceSetReport interposer):
  //   [0]=0x7b [1]=ver [2]=(dist<<4)|0x01 [3]=seq [4..5]=len+2 [6]=0 [7]=0x7d
  //   [8]=cmd [9]=arg [10..]=payload
  // `dist` is the target MCU (MCU_MAIN=3) and explains the 0x31 in every frame.
  std::vector<unsigned char> header(unsigned char cmd, unsigned char arg, unsigned char dist,
                                    unsigned char seq, unsigned char last_index,
                                    unsigned char remainder, size_t len) {
    std::vector<unsigned char> f;
    f.reserve(10 + len);
    const bool multi = !(last_index == 0 && remainder == 0);
    f.push_back(0x7b);
    f.push_back(ver_);
    f.push_back((unsigned char)((dist << 4) | 0x01));
    f.push_back(static_cast<unsigned char>(multi ? (0x80 | (seq & 0x7f)) : (seq & 0x0f)));
    const unsigned int field = static_cast<unsigned int>(len + 2);
    f.push_back((unsigned char)(field & 0xff));
    f.push_back((unsigned char)((field >> 8) & 0xff));
    f.push_back(0x00);
    f.push_back(0x7d);
    f.push_back(cmd);
    f.push_back(arg);
    return f;
  }

  hid_device* dev_;
  bool is_ble_;
  std::string path_;
  int vendor_id_;
  unsigned char ver_, flags_, base_, max_payload_;
};

struct Pending {
  Napi::ThreadSafeFunction tsfn;
  std::chrono::steady_clock::time_point at;
  size_t want;  // expected reply payload length; 0 = use the frame's own field
};

std::mutex g_mu;
std::unordered_map<std::string, Pending> g_pending;
std::unordered_map<std::string, std::shared_ptr<Liana>> g_devices;

std::string keyFor(const std::string& path, unsigned char cmd, unsigned char arg) {
  char buf[16];
  snprintf(buf, sizeof buf, "|%02x|%02x", cmd, arg);
  return path + buf;
}

}  // namespace

unsigned char ArgFor(const std::string& name);
static size_t ReplyLenFor(const std::string& name);
static std::vector<unsigned char> BufferToVector(const Napi::CallbackInfo& info, size_t idx);
unsigned char CommandFor(const std::string& name);
namespace { Napi::Object MakeEmitter(Napi::Env env); }

// ---------------------------------------------------------------------------
// HID class: thin wrapper matching node-hid's surface plus the Liana dispatch.
// ---------------------------------------------------------------------------
class HID : public Napi::ObjectWrap<HID> {
 public:
  static Napi::Object Init(Napi::Env env, Napi::Object exports);
  explicit HID(const Napi::CallbackInfo& info);
  ~HID() override;

 private:
  Napi::Value Close(const Napi::CallbackInfo& info);
  Napi::Value Write(const Napi::CallbackInfo& info);
  Napi::Value WriteTo(const Napi::CallbackInfo& info);
  Napi::Value Read(const Napi::CallbackInfo& info);
  Napi::Value ReadSync(const Napi::CallbackInfo& info);
  Napi::Value ReadTimeout(const Napi::CallbackInfo& info);
  Napi::Value GetFeatureReport(const Napi::CallbackInfo& info);
  Napi::Value SendFeatureReport(const Napi::CallbackInfo& info);
  Napi::Value SetNonBlocking(const Napi::CallbackInfo& info);
  Napi::Value GetDeviceInfo(const Napi::CallbackInfo& info);
  Napi::Value On(const Napi::CallbackInfo& info);
  Napi::Value Once(const Napi::CallbackInfo& info);
  Napi::Value Off(const Napi::CallbackInfo& info);
  Napi::Value RemoveAllListeners(const Napi::CallbackInfo& info);
  Napi::Value Emit(const Napi::CallbackInfo& info);
  Napi::Value ListenerCount(const Napi::CallbackInfo& info);

  void Dispatch(const Napi::CallbackInfo& info, const std::string& cmd_name,
                unsigned char cmd, unsigned char arg, unsigned char dist,
                const std::vector<unsigned char>& payload, Napi::Value cb);

  std::shared_ptr<Liana> liana_;
  bool closed_ = false;

  // The renderer treats HID instances as EventEmitters (dev.on('data', ...)),
  // so delegate the event surface to a real JS EventEmitter instead of
  // reimplementing Node's listener bookkeeping in C++.
  Napi::ObjectReference emitter_;
  Napi::ThreadSafeFunction tsfn_;
  // node-hid's wrapper drives 'data' through read(cb); the callback is handed
  // to the background reader instead of blocking the JS thread here.
  Napi::ThreadSafeFunction readCb_;
  std::mutex readMu_;
  std::atomic<bool> reading_{false};
  std::thread reader_;
};

// A joinable std::thread aborts the process when destroyed, so the reader must
// be stopped and joined here. Everything the reader touches is owned by this
// object, hence the join happens before any member is released.
HID::~HID() {
  reading_ = false;
  if (reader_.joinable()) {
    try { reader_.join(); } catch (...) {}
  }
  if (tsfn_ != nullptr) {
    try { tsfn_.Release(); } catch (...) {}
  }
  if (readCb_ != nullptr) {
    try { readCb_.Release(); } catch (...) {}
  }
  if (!emitter_.IsEmpty()) emitter_.Reset();
}

Napi::Object HID::Init(Napi::Env env, Napi::Object exports) {
  const napi_property_attributes kAttr = static_cast<napi_property_attributes>(
      napi_writable | napi_enumerable | napi_configurable);
  Napi::Function func = DefineClass(
      env, "HID",
      {
          // node-hid's wrapper re-exports native methods onto the instance with
          // `for (var i in binding.HID.prototype)`, which only walks enumerable
          // keys. Non-enumerable methods would leave writeTo/readTimeout
          // undefined on every device object.
          InstanceMethod("close", &HID::Close, kAttr),
          InstanceMethod("write", &HID::Write, kAttr),
          InstanceMethod("writeTo", &HID::WriteTo, kAttr),
          InstanceMethod("read", &HID::Read, kAttr),
          InstanceMethod("readSync", &HID::ReadSync, kAttr),
          InstanceMethod("readTimeout", &HID::ReadTimeout, kAttr),
          InstanceMethod("getFeatureReport", &HID::GetFeatureReport, kAttr),
          InstanceMethod("sendFeatureReport", &HID::SendFeatureReport, kAttr),
          InstanceMethod("setNonBlocking", &HID::SetNonBlocking, kAttr),
          InstanceMethod("getDeviceInfo", &HID::GetDeviceInfo, kAttr),
          InstanceMethod("on", &HID::On, kAttr),
          InstanceMethod("addListener", &HID::On, kAttr),
          InstanceMethod("once", &HID::Once, kAttr),
          InstanceMethod("off", &HID::Off, kAttr),
          InstanceMethod("removeListener", &HID::Off, kAttr),
          InstanceMethod("removeAllListeners", &HID::RemoveAllListeners, kAttr),
          InstanceMethod("emit", &HID::Emit, kAttr),
          InstanceMethod("listenerCount", &HID::ListenerCount, kAttr),
      });
  exports.Set("HID", func);
  return exports;
}

HID::HID(const Napi::CallbackInfo& info) : Napi::ObjectWrap<HID>(info) {
  Napi::Env env = info.Env();
  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "HID constructor requires at least one argument")
        .ThrowAsJavaScriptException();
    return;
  }
  std::string path = info[0].As<Napi::String>().Utf8Value();
  // The wrapper does `new HID(path, isUsb, vendorId)`, but Liana takes is_ble in
  // this slot. Inverting here keeps every frame header on the right branch:
  // reading it as isUsb sent USB devices down the BLE path (ver 0x10, base 0x00)
  // and the firmware ignored every command.
  bool is_usb = info.Length() > 1 && info[1].IsBoolean() ? info[1].As<Napi::Boolean>().Value() : false;
  bool is_ble = !is_usb;
  int vendor_id = info.Length() > 2 && info[2].IsNumber() ? info[2].As<Napi::Number>().Int32Value() : 0;

  hid_device* dev = hid_open_path(path.c_str());
  if (!dev) {
    Napi::Error::New(env, "could not open device").ThrowAsJavaScriptException();
    return;
  }
  liana_ = std::make_shared<Liana>(dev, is_ble, path, vendor_id);
  {
    std::lock_guard<std::mutex> lk(g_mu);
    g_devices[path] = liana_;
  }

  // One reader per device. It owns the blocking hid_read loop, resolves any
  // pending command callbacks, and forwards frames to JS as 'data' events.
  reading_ = true;
  // The reader runs off the JS thread and cannot touch V8 directly. It hands
  // each frame to this callback, which re-emits it on the instance's emitter.
  // Building the emitter here rather than in On() keeps emit() valid for frames
  // that arrive before the first listener is attached.
  emitter_ = Napi::Persistent(MakeEmitter(env));
  Napi::Function sender = Napi::Function::New(
      env,
      [](const Napi::CallbackInfo& ci) {
        auto* self = static_cast<HID*>(ci.Data());
        if (!self || self->emitter_.IsEmpty()) return ci.Env().Undefined();
        Napi::Object em = self->emitter_.Value().As<Napi::Object>();
        em.Get("emit").As<Napi::Function>().Call(
            em, {Napi::String::New(ci.Env(), "data"), ci[0]});
        return ci.Env().Undefined();
      },
      "hexcore-hid-emit", this);
  tsfn_ = Napi::ThreadSafeFunction::New(env, sender, "hexcore-hid-reader", 0, 1);
  std::shared_ptr<Liana> liana = liana_;
  std::string dev_path = path;
  reader_ = std::thread([this, liana, dev_path]() {
    std::vector<unsigned char> buf(64);
    while (reading_) {
      int n = hid_read_timeout(liana->dev(), buf.data(), buf.size(), 50);
      if (n <= 0) {
        if (n < 0 && HidDebug()) { const wchar_t* e = hid_error(liana->dev()); FILE* f = fopen("/tmp/hx/hid_log.txt", "a"); if (f) { fprintf(f, "READERR %d err=%ls\n", n, e ? e : L"(null)"); fclose(f); } }
        continue;
      }
      if (HidDebug()) { FILE* f = fopen("/tmp/hx/hid_log.txt", "a"); if (f) { fprintf(f, "READ %d:", n); for (int i=0;i<n&&i<16;i++) fprintf(f," %02x", buf[i]); fprintf(f,"\n"); fclose(f); } }
      // Replies use the same non-report-id prefix as requests:
      //   [0]=0x7b [1]=ver [2]=flags [3]=seq [4..5]=len [6]=0 [7]=0x7d [8]=cmd [9]=arg
      // Locate the 0x7d marker rather than assuming a fixed offset: hidapi
      // prepends the report id on some reads and not on others. Parsing at
      // offset 2 never matched, so every callback timed out even when the
      // keyboard had answered.
      int marker = -1;
      for (int i = 1; i < n - 2 && i < 12; ++i) {
        if (buf[i] == 0x7d) { marker = i; break; }
      }
      if (marker > 0) {
        unsigned char cmd = buf[marker + 1];
        unsigned char arg = buf[marker + 2];
        std::function<void()> fire;
        {
          std::lock_guard<std::mutex> lk(g_mu);
          auto it = g_pending.find(keyFor(dev_path, cmd, arg));
          if (it != g_pending.end()) {
            Napi::ThreadSafeFunction t = it->second.tsfn;
            const size_t want = it->second.want;
            g_pending.erase(it);
            // The length field at [marker-3, marker-2] counts the two command
            // bytes that follow the header, so the payload is len-2 bytes.
            // Returning the whole 64-byte report made callers parse trailing
            // padding as data.
            const size_t payload_at = static_cast<size_t>(marker) + 3;
            const unsigned int declared =
                static_cast<unsigned int>(buf[marker - 3]) |
                (static_cast<unsigned int>(buf[marker - 2]) << 8);
            size_t payload_len = declared >= 2 ? declared - 2 : 0;
            if (want > 0) payload_len = want;  // per-command, see ReplyLenFor
            if (payload_at + payload_len > static_cast<size_t>(n))
              payload_len = n > payload_at ? static_cast<size_t>(n) - payload_at : 0;
            std::vector<unsigned char> payload(buf.begin() + payload_at,
                                               buf.begin() + payload_at + payload_len);
            fire = [t, payload]() mutable {
              auto* data = new std::vector<unsigned char>(payload);
              t.NonBlockingCall(data, [](Napi::Env env, Napi::Function cb,
                                         std::vector<unsigned char>* d) {
                cb.Call({env.Null(), Napi::Buffer<unsigned char>::Copy(env, d->data(), d->size())});
                delete d;
              });
              t.Release();
            };
          }
        }
        if (HidDebug()) { FILE* f = fopen("/tmp/hx/frames.log","a"); if (f) { fprintf(f, "RX marker=%d cmd=%02x arg=%02x match=%d n=%d:", marker, cmd, arg, fire ? 1 : 0, n); for (int i=0;i<n&&i<24;i++) fprintf(f," %02x", buf[i]); fprintf(f,"\n"); fclose(f); } }
        if (fire) fire();
      }
      // Hand the frame to an outstanding read(cb) if one is registered — the
      // wrapper turns that callback into the 'data' event. Otherwise emit on
      // the emitter listeners subscribed through on('data', ...).
      Napi::ThreadSafeFunction read_cb;
      {
        std::lock_guard<std::mutex> lk(readMu_);
        if (readCb_ != nullptr) {
          read_cb = readCb_;
          readCb_ = Napi::ThreadSafeFunction();
        }
      }
      auto* copy = new std::vector<unsigned char>(buf.begin(), buf.begin() + n);
      if (read_cb != nullptr) {
        read_cb.NonBlockingCall(copy, [](Napi::Env env, Napi::Function cb,
                                         std::vector<unsigned char>* d) {
          cb.Call({env.Null(), Napi::Buffer<unsigned char>::Copy(env, d->data(), d->size())});
          delete d;
        });
        read_cb.Release();
      } else {
        tsfn_.NonBlockingCall(copy, [](Napi::Env env, Napi::Function cb,
                                       std::vector<unsigned char>* d) {
          cb.Call({Napi::Buffer<unsigned char>::Copy(env, d->data(), d->size())});
          delete d;
        });
      }
    }
  });
}

// ---------------------------------------------------------------------------
// EventEmitter surface + background reader.
//
// The renderer does `dev.on('data', fn)` and expects the device to push frames
// as they arrive. Emitting from the reader thread is unsafe, so the emitter is
// a real JS EventEmitter that we drive through a ThreadSafeFunction.
// ---------------------------------------------------------------------------
namespace {
Napi::Object MakeEmitter(Napi::Env env) {
  // require() is not in scope inside RunScript, so reach Node's module loader
  // through process.getBuiltinModule (available on every supported Electron).
  Napi::Object process = env.Global().Get("process").As<Napi::Object>();
  Napi::Function getBuiltin = process.Get("getBuiltinModule").As<Napi::Function>();
  Napi::Object events = getBuiltin.Call(process, {Napi::String::New(env, "events")}).As<Napi::Object>();
  Napi::Function ctor = events.Get("EventEmitter").As<Napi::Function>();
  return ctor.New({});
}
}  // namespace

Napi::Value HID::On(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (emitter_.IsEmpty()) emitter_ = Napi::Persistent(MakeEmitter(env));
  Napi::Value r = emitter_.Value().As<Napi::Object>()
                      .Get("on").As<Napi::Function>()
                      .Call(emitter_.Value(), {info[0], info[1]});
  return r;
}

Napi::Value HID::Once(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (emitter_.IsEmpty()) emitter_ = Napi::Persistent(MakeEmitter(env));
  return emitter_.Value().As<Napi::Object>()
      .Get("once").As<Napi::Function>()
      .Call(emitter_.Value(), {info[0], info[1]});
}

Napi::Value HID::Off(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (emitter_.IsEmpty()) return env.Undefined();
  return emitter_.Value().As<Napi::Object>()
      .Get("removeListener").As<Napi::Function>()
      .Call(emitter_.Value(), {info[0], info[1]});
}

Napi::Value HID::RemoveAllListeners(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (emitter_.IsEmpty()) return env.Undefined();
  return emitter_.Value().As<Napi::Object>()
      .Get("removeAllListeners").As<Napi::Function>()
      .Call(emitter_.Value(), {});
}

Napi::Value HID::Emit(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (emitter_.IsEmpty()) return Napi::Boolean::New(env, false);
  return emitter_.Value().As<Napi::Object>()
      .Get("emit").As<Napi::Function>()
      .Call(emitter_.Value(), {info[0], info[1]});
}

Napi::Value HID::ListenerCount(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (emitter_.IsEmpty()) return Napi::Number::New(env, 0);
  return emitter_.Value().As<Napi::Object>()
      .Get("listenerCount").As<Napi::Function>()
      .Call(emitter_.Value(), {info[0]});
}

Napi::Value HID::Read(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!liana_ || closed_) {
    Napi::Error::New(env, "Unable to read from a closed HID device").ThrowAsJavaScriptException();
    return env.Undefined();
  }
  if (info.Length() < 1 || !info[0].IsFunction()) {
    Napi::TypeError::New(env, "read requires a callback").ThrowAsJavaScriptException();
    return env.Undefined();
  }
  // Reading here would call hid_read() on the JS thread, which only returns
  // once a report arrives — with an idle keyboard that parks the renderer
  // forever. The background reader owns the blocking read and resolves this.
  std::lock_guard<std::mutex> lk(readMu_);
  if (readCb_ != nullptr) {
    try { readCb_.Release(); } catch (...) {}
  }
  readCb_ = Napi::ThreadSafeFunction::New(env, info[0].As<Napi::Function>(),
                                          "hexcore-hid-read", 0, 1);
  return env.Undefined();
}

// Synchronous polling read. hid_read() would block until the next report, so
// poll with a zero timeout instead and return null when nothing is pending.
Napi::Value HID::ReadSync(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!liana_ || closed_) return env.Null();
  std::vector<unsigned char> buf(64);
  int n = hid_read_timeout(liana_->dev(), buf.data(), buf.size(), 0);
  if (n <= 0) return env.Null();
  return Napi::Buffer<unsigned char>::Copy(env, buf.data(), n);
}

Napi::Value HID::ReadTimeout(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!liana_ || closed_) return env.Undefined();
  int ms = info.Length() > 0 && info[0].IsNumber() ? info[0].As<Napi::Number>().Int32Value() : 0;
  std::vector<unsigned char> buf(64);
  int n = hid_read_timeout(liana_->dev(), buf.data(), buf.size(), ms);
  if (n <= 0) return env.Undefined();
  return Napi::Buffer<unsigned char>::Copy(env, buf.data(), n);
}

Napi::Value HID::GetFeatureReport(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!liana_ || closed_) return env.Undefined();
  unsigned char report_id = info.Length() > 0 && info[0].IsNumber()
                                ? (unsigned char)info[0].As<Napi::Number>().Int32Value()
                                : 0;
  std::vector<unsigned char> buf(64);
  buf[0] = report_id;
  int n = hid_get_feature_report(liana_->dev(), buf.data(), buf.size());
  if (n <= 0) return env.Undefined();
  return Napi::Buffer<unsigned char>::Copy(env, buf.data(), n);
}

Napi::Value HID::SendFeatureReport(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!liana_ || closed_) return env.Undefined();
  std::vector<unsigned char> buf = BufferToVector(info, 0);
  if (buf.empty()) return Napi::Number::New(env, 0);
  int rc = hid_send_feature_report(liana_->dev(), buf.data(), buf.size());
  return Napi::Number::New(env, rc);
}

Napi::Value HID::SetNonBlocking(const Napi::CallbackInfo& info) {
  if (liana_ && !closed_) hid_set_nonblocking(liana_->dev(), 1);
  return info.Env().Undefined();
}

Napi::Value HID::GetDeviceInfo(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  Napi::Object o = Napi::Object::New(env);
  if (liana_) o.Set("path", Napi::String::New(env, liana_->path()));
  return o;
}

Napi::Value HID::Close(const Napi::CallbackInfo& info) {
  if (!closed_ && liana_) {
    hid_close(liana_->dev());
    {
      std::lock_guard<std::mutex> lk(g_mu);
      g_devices.erase(liana_->path());
    }
    closed_ = true;
  }
  return info.Env().Undefined();
}

Napi::Value HID::Write(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!liana_ || closed_) {
    Napi::Error::New(env, "device is not open").ThrowAsJavaScriptException();
    return env.Undefined();
  }
  std::vector<unsigned char> buf = BufferToVector(info, 0);
  if (buf.empty()) return Napi::Number::New(env, 0);
  int rc = hid_write(liana_->dev(), buf.data(), buf.size());
  // node-hid's write takes an optional completion callback; the renderer
  // relies on it to sequence commands, so honour both call styles.
  for (size_t i = 1; i < info.Length(); ++i) {
    if (!info[i].IsFunction()) continue;
    Napi::Function cb = info[i].As<Napi::Function>();
    if (rc < 0) cb.Call({Napi::Error::New(env, "write error").Value()});
    else cb.Call({env.Null(), Napi::Number::New(env, rc)});
    break;
  }
  return Napi::Number::New(env, rc);
}

Napi::Value HID::WriteTo(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong param.").ThrowAsJavaScriptException();
    return env.Null();
  }
  if (!liana_ || closed_) {
    Napi::Error::New(env, "device is not open").ThrowAsJavaScriptException();
    return env.Null();
  }
  std::string cmd_name = info[0].As<Napi::String>().Utf8Value();
  // The renderer passes (cmd, dist, arg, ...) and appends the reply callback
  // last, so scan for it rather than assuming a fixed position.
  Napi::Value cb = env.Undefined();
  if (HidDebug()) {
    FILE* lf = fopen("/tmp/hx/hid_args.txt", "a");
    if (lf) { fprintf(lf, "WRITETO %s argc=%d |", cmd_name.c_str(), (int)info.Length());
      for (size_t i = 0; i < info.Length(); ++i) {
        fprintf(lf, " [%zu]%s", i, info[i].IsFunction() ? "fn" : info[i].IsString() ? "str" : info[i].IsNumber() ? "num" : info[i].IsBuffer() ? "buf" : info[i].IsObject() ? "obj" : "?");
      }
      fprintf(lf, "\n"); fclose(lf); }
  }
  for (size_t i = 1; i < info.Length(); ++i) {
    if (info[i].IsFunction()) { cb = info[i]; break; }
  }
  // The wrapper calls writeTo(cmdName, cb, dist, [arg|buffer], ...extra), so the
  // chunk selector the vendor calls `dist` is info[2] and the command argument
  // is info[3]. Reading info[2] as the arg sent every command with dist in the
  // arg slot and produced frames the firmware silently ignored.
  unsigned char arg = 0;
  std::vector<unsigned char> payload;
  if (info.Length() > 3) {
    if (info[3].IsBuffer())
      payload = BufferToVector(info, 3);
    else if (info[3].IsTypedArray())
      payload = BufferToVector(info, 3);
    else if (info[3].IsNumber())
      arg = (unsigned char)info[3].As<Napi::Number>().Int32Value();
  }

  // `hidWriteTo(path, cmd, syncId, mcu)`; the last numeric arg picks the target
  // MCU and lands in header byte 2. Commands that omit it address MCU_MAIN.
  unsigned char dist = 3;
  if (info.Length() > 3 && info[3].IsNumber())
    dist = (unsigned char)info[3].As<Napi::Number>().Int32Value();

  unsigned char cmd = CommandFor(cmd_name);
  arg = ArgFor(cmd_name);
  Dispatch(info, cmd_name, cmd, arg, dist, payload, cb);
  return Napi::Number::New(env, 0);
}

void HID::Dispatch(const Napi::CallbackInfo& info, const std::string& cmd_name,
                   unsigned char cmd, unsigned char arg, unsigned char dist,
                   const std::vector<unsigned char>& payload, Napi::Value cb) {
  Napi::Env env = info.Env();
  // Commands that the firmware answers asynchronously: register a callback keyed
  // by (path, cmd, arg); the reader thread resolves it.
  if (cb.IsFunction()) {
    Napi::Function fn = cb.As<Napi::Function>();
    auto tsfn = Napi::ThreadSafeFunction::New(env, fn, "hexcore-hid", 0, 1);
    std::lock_guard<std::mutex> lk(g_mu);
    g_pending[keyFor(liana_->path(), cmd, arg)] =
        Pending{tsfn, std::chrono::steady_clock::now(), ReplyLenFor(cmd_name)};
  }
  for (auto& f : liana_->build(cmd, arg, dist, payload)) {
    // Report id 0: the first byte of the buffer tells hidapi which id to use,
    // and the vendor sends id 0 with the Liana payload starting at byte 1.
    // Trailing bytes are zero padding to the device's 64-byte report size.
    std::vector<unsigned char> wire(65, 0);
    const size_t n = std::min(f.size(), wire.size() - 1);
    std::copy(f.begin(), f.begin() + n, wire.begin() + 1);
    int rc = hid_write(liana_->dev(), wire.data(), wire.size());
    if (HidDebug()) {
      FILE* lf = fopen("/tmp/hx/hid_log.txt", "a");
      if (lf) { fprintf(lf, "WRITE rc=%d cmd=%02x arg=%02x dist=%02x len=%zu:", rc, cmd, arg, dist, wire.size());
        for (size_t i=0;i<wire.size();i++) fprintf(lf," %02x", wire[i]); fprintf(lf,"\n"); fclose(lf); }
    }
  }
}

// ---------------------------------------------------------------------------
// Command name -> (cmd, arg) table, recovered from Liana::writeWithName.
// ---------------------------------------------------------------------------
struct CmdSpec { const char* name; unsigned char cmd; unsigned char arg; };
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
    {"keyboardLayer", 0x10, 0x02},
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

unsigned char CommandFor(const std::string& name) {
  for (auto& c : kCommands)
    if (name == c.name) return c.cmd;
  return 0x00;
}

// The wire argument for a command comes from this table, not from the caller:
// the renderer's extra parameter is the target MCU (`dist`). Reading battery
// with the caller's value sent arg 0x00 instead of 0x11 and the firmware
// answered with the generic status block.
unsigned char ArgFor(const std::string& name) {
  for (auto& c : kCommands)
    if (name == c.name) return c.arg;
  return 0x00;
}

// Expected reply payload size per command. The device's own length field is
// not usable here: readFirmwareVersion answers with 6 bytes while declaring 2,
// so callers that slice by the declared length get nothing.
static size_t ReplyLenFor(const std::string& name) {
  if (name == "readDeviceType") return 2;
  if (name == "readFirmwareVersion" || name == "readIapFwVersion") return 6;
  if (name == "readBatteryPercentage") return 1;
  if (name == "readPowerOnTime") return 4;
  if (name == "readHardwareState") return 8;
  if (name == "readUDID") return 32;
  return 0;  // unknown: fall back to the frame's own length field
}

// ---------------------------------------------------------------------------
// getDevicesAsync
// ---------------------------------------------------------------------------
Napi::Value GetDevicesAsync(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (info.Length() < 1 || !info[0].IsFunction()) {
    Napi::TypeError::New(env, "callback required").ThrowAsJavaScriptException();
    return env.Undefined();
  }
  Napi::Function cb = info[0].As<Napi::Function>();
  hid_device_info* list = hid_enumerate(0, 0);
  Napi::Array devs = Napi::Array::New(env);
  uint32_t n = 0;
  for (hid_device_info* p = list; p; p = p->next) {
    // Skip macOS virtual nodes. `IOHIDUserDevice` entries are host-created
    // placeholders (they show up here with the keyboard's own name and ids) and
    // reject every output report with kIOReturnUnsupported. The renderer's
    // device filter accepts one of them as a real device, so init() stalls on
    // it and the physical keyboard is never added.
    if (p->path && strstr(p->path, "IOHIDUserDevice") != nullptr) continue;
    Napi::Object o = Napi::Object::New(env);
    o.Set("vendorId", Napi::Number::New(env, p->vendor_id));
    o.Set("productId", Napi::Number::New(env, p->product_id));
    o.Set("path", Napi::String::New(env, p->path ? p->path : ""));
    o.Set("isUsb", Napi::Boolean::New(env, p->interface_number >= 0));
    o.Set("release", Napi::Number::New(env, p->release_number));
    o.Set("interface", Napi::Number::New(env, p->interface_number));
    o.Set("usagePage", Napi::Number::New(env, p->usage_page));
    o.Set("usage", Napi::Number::New(env, p->usage));
    o.Set("product", Napi::String::New(env, WideToUtf8(p->product_string)));
    o.Set("manufacturer", Napi::String::New(env, WideToUtf8(p->manufacturer_string)));
    o.Set("serialNumber", Napi::String::New(env, WideToUtf8(p->serial_number)));
    devs.Set(n++, o);
  }
  hid_free_enumeration(list);
  cb.Call({env.Null(), devs});
  return env.Undefined();
}

// ---------------------------------------------------------------------------
// Input Monitoring permission (TCC).
// ---------------------------------------------------------------------------
static Napi::Value CheckListenAccess(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  IOHIDAccessType t = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
  const char* name = t == kIOHIDAccessTypeGranted ? "granted"
                     : t == kIOHIDAccessTypeDenied ? "denied"
                                                   : "unknown";
  return Napi::String::New(env, name);
}

static Napi::Value RequestListenAccess(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  bool ok = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
  return Napi::Boolean::New(env, ok);
}

// Declared in hidapi/mac/hid.c but absent from the public header.
extern "C" void hid_darwin_set_open_exclusive(int open_exclusive);
// Defined in hidapi/mac/hid.c: writes a report with an explicit report id.

Napi::Object InitAll(Napi::Env env, Napi::Object exports) {
  hid_init();
  // hidapi defaults to kIOHIDOptionsTypeSeizeDevice ("exclusive"), but seizing
  // this keyboard tears the IOHIDDevice out of the registry right after open:
  // the removal callback fires and every later read returns "device
  // disconnected". The vendor build opens non-exclusively.
  hid_darwin_set_open_exclusive(0);
  HID::Init(env, exports);
  exports.Set("getDevicesAsync", Napi::Function::New(env, GetDevicesAsync, "getDevicesAsync"));
  exports.Set("checkListenAccess", Napi::Function::New(env, CheckListenAccess, "checkListenAccess"));
  exports.Set("requestListenAccess", Napi::Function::New(env, RequestListenAccess, "requestListenAccess"));
  return exports;
}

NODE_API_MODULE(hexcore_hid, InitAll)

std::vector<unsigned char> BufferToVector(const Napi::CallbackInfo& info, size_t idx) {
  std::vector<unsigned char> out;
  if (idx >= info.Length()) return out;
  Napi::Value v = info[idx];
  if (v.IsBuffer()) {
    Napi::Buffer<unsigned char> b = v.As<Napi::Buffer<unsigned char>>();
    out.assign(b.Data(), b.Data() + b.Length());
  } else if (v.IsTypedArray()) {
    Napi::TypedArray a = v.As<Napi::TypedArray>();
    Napi::ArrayBuffer ab = a.ArrayBuffer();
    const unsigned char* base = static_cast<const unsigned char*>(ab.Data());
    out.assign(base + a.ByteOffset(), base + a.ByteOffset() + a.ByteLength());
  }
  return out;
}
