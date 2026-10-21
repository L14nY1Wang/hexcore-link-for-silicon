{
  "targets": [
    {
      "target_name": "HID",
      "sources": ["src/hid_wrap.cc", "hidapi/mac/hid.c"],
      "include_dirs": ["hidapi/hidapi", "<!@(node -p \"require('node-addon-api').include\")"],
      "defines": ["NAPI_DISABLE_CPP_EXCEPTIONS", "_LARGEFILE_SOURCE", "_FILE_OFFSET_BITS=64"],
      "cflags!": ["-fno-exceptions"],
      "cflags_cc!": ["-fno-exceptions"],
      "xcode_settings": {
        "CLANG_CXX_LIBRARY": "libc++",
        "MACOSX_DEPLOYMENT_TARGET": "11.0",
        "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
        "OTHER_CFLAGS": ["-Wno-deprecated-declarations"]
      },
      "link_settings": {
        "libraries": ["-framework IOKit", "-framework CoreFoundation", "-framework AppKit"]
      }
    }
  ]
}
