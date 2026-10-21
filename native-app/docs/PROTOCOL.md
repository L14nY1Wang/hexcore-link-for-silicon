# Liana HID 协议调用契约

只读分析产物：从 `packdir/dist/renderers/*.js`、`packdir/dist/preloads/*.cjs` 逆出渲染器侧调用契约，
与 `native/liana-hid/src/hid_wrap.cc`（`kCommands` / `Dispatch` / `ReplyLenFor`）、
`work/dis.txt`（厂商 x86_64 `HID.node` 反汇编）、`work/names.txt`（字符串表）对照。

标注约定：**[确认]** = 两侧证据一致；**[推断]** = 单一来源、未实测；**「未确认」** = 没有找到证据。

---

## 1. 传输层

### 1.1 帧格式

```
[0]=0x7b [1]=ver [2]=(dist<<4)|0x01 [3]=seq [4..5]=len+2 (LE) [6]=0x00 [7]=0x7d [8]=cmd [9]=arg [10..]=payload
```

- `len` 字段 = payload 长度 + 2（cmd、arg 两个字节）。**[确认]**（`hid_wrap.cc:118-141`，厂商 `multi_package_create` @0xeff0）
- `seq` 低 4 位是分片序号；多分片时置 `0x80|seq`。**[确认]**
- hidapi 送入 `hid_write` 时前面补 report id `0x00`，整包补齐到 65 字节。**[确认]**（`Dispatch` 内 `wire(65)`）
- 厂商 `readDeviceType` 用的是硬编码常量 `{02 7b 10 31 00 02 00 00 7d 01 01}`（含 report id 0x02）。**[确认]**

### 1.2 版本字段与分片大小

| 链路 | ver | base/flags | max_payload |
| --- | --- | --- | --- |
| USB（`isUsb=true`） | `0x12` | `base=0x02` | vid==0x7d7 时 `0x36`，否则 `0x08` |
| BLE（`isUsb=false`） | `0x10` | `base=0x00` | `0x35` |

**[确认]** `hid_wrap.cc:70-86`，与厂商 `Liana::Liana` @0xd34b 一致。

### 1.3 dist（目标 MCU）

渲染器枚举 `Fe`（`App-163bf8f7.js`）：

| 名 | 值 |
| --- | --- |
| `USB_HOST` | 1 |
| `BLE_HOST` | 2 |
| `MCU_MAIN` | 3 |
| `MCU_LED` | 4 |
| `MCU_BLE` | 5 |
| `MCU_24G` | 6 |
| `MODULE_24G` | 7 |

- `device.dist` = G24 主控 ? `MCU_24G` : `MCU_MAIN`；`device.wirelessDist` = W800 ? `MODULE_24G` : `MCU_BLE`。**[确认]**
- 「键盘配列」把 **layer 序号当作 dist** 传：`x("keyboardLayer", layer)` → `dist=layer`。**[确认]**（厂商 `keyboardLayer` 直接把 `info[2]`(dist) 当 `r8d` 送进分片器）

### 1.4 调用形状（关键）

preload（`preloads/app.cjs`）：

```js
hidWriteTo(path, cmdName, syncId, ...extra)   // → device.writeTo(cmdName, cb, syncId, ...extra)
hidWriteWithSyncId(cmdName, syncId, ...extra) // 使用当前设备 path
```

napi 侧绑定后：`info[0]=cmdName, info[1]=cb, info[2]=syncId(=dist), info[3]=extra[0], info[4]=extra[1]`。

厂商含义（**这是契约本体**）：

| 命令族 | 调用形式 | 语义 |
| --- | --- | --- |
| `hidWriteWithArg0/1` | `(cmd, cb, sync, valueByte)` | `info[3]` 数字 = **1 字节 payload**，dist 固定 3（Arg1 追加一个自带常量字节） |
| `hidWriteWithBuffer` | `(cmd, cb, sync, buf)` | `info[3]` = Buffer/Uint8Array 整包 payload |
| 多参数（`keyboardLayer` 写） | `(cmd, cb, sync, layer, buf)` | `info[3]` = dist(layer)，`info[4]` = payload |

> ⚠️ **已确认的实现差异**：当前 `hid_wrap.cc:617-630` 把 `info[3]` 数字一律当成 `dist`，
> 且从不读 `info[4]`。因此「数字单字节写」（如 `backlightBrightness`、`usbPlugMode`…）
> 在当前 arm64 实现里 payload 为空、dist 被写成该值；「layer+buffer」形式会丢掉 payload。
> 本文所有 payload 均按**渲染器契约**记录，是否已在实机验证：**未确认**。

### 1.5 回复

- 读线程在 `buf[1..11]` 内找 `0x7d`（hidapi 有时带 report id、有时不带），`cmd=[marker+1]`、`arg=[marker+2]`。**[确认]**
- payload 起点 `marker+3`；长度先取 `len-2`，再被 `ReplyLenFor(name)` 覆盖。**[确认]**
- 回调签名 `cb(null, Buffer)`；无匹配 pending 键 `(path, cmd, arg)` 时该帧只作为 `data` 事件抛出。**[确认]**
- `ReplyLenFor` 表（`hid_wrap.cc:775-783`）：

| 命令 | 长度 | 含义 |
| --- | --- | --- |
| `readDeviceType` | 2 | `[model, type]` |
| `readFirmwareVersion` / `readIapFwVersion` | 6 | key/led/ble 各 2 字节 |
| `readBatteryPercentage` | 1 | 电量 % |
| `readPowerOnTime` | 4 | LE u32 秒 |
| `readHardwareState` | 8 | 未使用（「未确认」字段布局） |
| `readUDID` | 32 | 序列号原始字节 |
| 其余 | 0 | 回退到帧自带 len 字段 |

> 厂商二进制里 `readFirmwareVersion` 声明 2 字节但实际回 6 字节，所以必须按表取长。**[确认]**

### 1.6 preload 串行队列（`app.cjs`）

- 每个 path 一个 `{isRunning, queueArray}`；一次只跑一条命令。**[确认]**
- 特例：正在跑 `previewLightbar` 时到来的 `previewLight` 直接 `resolve(new Uint8Array)` 丢弃（不排队）。**[确认]**
- 回调只推进队列，不区分成功/失败。**[确认]**

---

## 2. 设备识别与通用信息

### 2.1 readDeviceType — `0x01 / 0x01`

- **payload**：无。**dist**：`MCU_MAIN(3)`，G24 主控用 `MCU_24G(6)`。
- **回复**：2 字节 `[model, type]`。
- **调用**：`App-163bf8f7.js` `Mt.readDeviceType(path, dist)`；`Device.init()` 里
  `const [model, type] = await Mt.readDeviceType(...)`，再按 vid/pid 覆写特例
  （785/41619 与 13073/41624 → AnnePro2D；13073/61449 → ApxAcrylicM2R5）。
- **枚举**（同文件 line 343）：
  - type `ye`：0 RESERVED、1 Keyboard、2 Mouse、4 Firefly、5 AKDM
  - model `we`：0 RESERVED、1 Anne、2 AnnePro、3 AnnePro2、4 AnneProISO、5 AnnePro2C18、6 Param68、
    7 AnneClassicD87、8 ApxF61、9 RETURNEDWING、10 ANNEPRO2SLIM、11 ApxFuji65、12 ApxTenet、
    13 ApxFuji65Rgb、14 AnnePro2D、15 W800、17 ApxF61V2、18 ApxAcrylicM2R5
  - Firefly model `Fn`：1 FireflyV1
- **[确认]**

### 2.2 readFirmwareVersion — `0x01 / 0x03`

- **payload**：无。**回复**：6 字节 → `nr()` 解码成 `{key, led, ble}`（`0.0.0` 形式）。
- **调用**：`Ng.getVersion(path, syncId, dist)`（`App-163bf8f7.js` line 1988），
  `Device.getFirmware()` 用 `isG24Master ? MCU_24G : MCU_MAIN`。
- **[确认]**

### 2.3 readBatteryPercentage — `0x81 / 0x11`

- **payload**：无。**回复**：1 字节，`r[0]`，异常/空回 0。
- **调用**：`Mt.getBattery(path, syncId)`；`Device.updateBattery()`，每秒轮询中每 600 s 刷一次。

### 2.4 readPowerOnTime — `0x81 / 0x02`

- **回复**：4 字节 LE u32（秒）。`0xFFFFFFFF` 视为 0。
- **调用**：`Mt.getUptime()` → `Vs("readPowerOnTime")` 后 `nodejs.readUInt32LE(t)`。

### 2.5 readUDID — `0x81 / 0x0d`

- **回复**：32 字节；全 `0xFF` 或全 `0x00` 视为无序列号。
- **转换**：`Hg()` 逐字节补零后填入 `xxxx-xxxx-…` 模板并大写（8 组 4 字符）。
- **调用**：`Fg(path, syncId, dist)`，`Device.init()` 内 `serialNumber`。

### 2.6 readHardwareState — `0x01 / 0x09`

- **回复**：8 字节。仅存在于 `kCommands` / `ReplyLenFor`，渲染器未找到调用点，字段含义**未确认**。

### 2.7 deviceAlias — `0x04 / 0x00`

- **读**：`hidWriteTo(path,"deviceAlias",syncId,dist)`，回复按 `[len][utf16be 名][crc32 4B]` 解析，
  `len-1==data[0]` 且 crc 校验通过才生效，否则回退默认名。**dist 默认 `MCU_MAIN`**（W800）。
- **写**：清空 → `payload=[0x00]`；设置 → `[utf16beLen+4, ...utf16be(≤48B), ...crc32]`。
- **调用**：`Mt.alias.get/set`；`Wg()` 带 sessionStorage 缓存。
- **[确认]**

### 2.8 usbPlugMode `0x01/0x23`、usbSwitchState `0x01/0x20`、keycapStyle `0x01/0x31`、rfMode `0x01/0x13`

| 命令 | 写 payload | 读回复 | 备注 |
| --- | --- | --- | --- |
| `usbPlugMode` | 1 字节（1=默认 / 0=切换） | 1 字节 | W800 专属页面 |
| `usbSwitchState` | 只读 | 1 字节 | — |
| `keycapStyle` | u16 LE | u16 LE | W800；`set()` 走 `gr()` |
| `rfMode` | 1 字节 | 1 字节 | `Mt.rfMode.get/set` |

**[确认]**（读写经 `Rt/Oe/gr` → `hidWriteWithSyncId`）

---

## 3. 键盘配列（keyboardLayer）

> **重要**：渲染器从不发送 `uploadKbdLayout` 这个字符串。`keyboardStore.uploadKbdLayout(layer)`
> 只是 `x("keyboardLayer", layer)` 的 JS 方法名。`kCommands` 里 `uploadKbdLayout(0x10,0x02)`
> 与 `keyboardLayer(0x10,0x02)` 同码，属于二进制里的别名。**[确认]**

### 3.1 keyboardLayer（读） — `0x10 / 0x02`，dist=layer

- **payload**：无。**dist**：layer 序号 0..3。
- **回复**：`2 * keycapNum` 字节，按 u16 LE 逐键解析为 keycode 数组。
- **校验**：`uploadKbdLayout` 只在 `r.length === kbdProfile.keycapNum*2` 时接受，否则回空数组。
- **调用**：
  - `index-3fa97e8c.js` `uploadKbdLayout(layer)` / `getDefaultLayer(path, layer)`
  - `index-792dd774.js` `getLayersById(-1)`：依次读 layer 0/1/2/3，每层间隔 `Ze(100)` ms（即 100 ms）
- **[确认]**

### 3.2 keyboardLayer（写） — `0x10 / 0x02`，dist=layer

- **payload**：每键 u16 LE 拼接（长度 `keycapNum*2`）。调用 `he(layers)`：
  ```js
  r.push(...window.app.nodejs.writeUInt16LE(keycode)); await b("keyboardLayer", layer, Uint8Array.from(r))
  ```
  → `writeTo("keyboardLayer", cb, syncId, layer, buf)`，dist=layer、payload=buf。
- **回复**：无（不等待）。**[推断]**
- ⚠️ 当前 native `WriteTo` 只读 `info[3]`，这条路径会丢 payload（见 §1.4）。

### 3.3 kbdLayoutType — `0x10 / 0xf1`

- **payload**：无。**回复**：1 字节 → `isOledAtLeft = !!r[0]`（ApxTenet / T70 专用）。
- **调用**：`Device.t70Init()`：`hidWriteTo(path,"kbdLayoutType",syncId)`（dist 未显式给 → 默认 3）。
- **[确认]**

### 3.4 kbdLayoutParam — `0x90 / 0xf2`（**不在 kCommands**）

- **payload**：无。**回复**：长度须等于请求长度 `r`（渲染器传 80），
  前 4 字节 u32 LE = 后续内容的 crc32，校验失败返回 `[]`。
- **写**：`[crc32 4B][参数体]`，走 `gr("kbdLayoutParam", …)`。
- **调用**：`qs.param`；`t70Init()` 里 `qs.param.get(path, syncId, 80)` 覆盖 `keycapStyles`。
- **cmd/arg 来源**：厂商反汇编（`$0x90/$0xf2`）；`kCommands` 缺失 → 需要补表。**[确认 cmd/arg，payload 语义 推断]**

### 3.5 kbdCapsType `0x20/0x09`、kbdTapkeyTimeout `0x10/0x13`

- `kbdCapsType`：1 字节，`0xFF` 视为未设置（回退默认 1）。
- `kbdTapkeyTimeout`：1 字节，合法区间 10..200，越界自动写回 26。
- 调用：`index-3fa97e8c.js` `H.type` / `qs.tapTimeout`。

---

## 4. 灯光

### 4.1 downloadLight — `0x20 / 0x02`

- **payload**（`index-3fa97e8c.js` `Se()`）：
  ```
  [count, (256-count)&0xFF, 0x00, 0x00]
  for each effect:
     [ledType, u16LE rgbLen, u16LE nameLen, checksum(1B), rgbData..., utf16be(name)...]
  ```
  `checksum = Me(h)`（对 rgb+name 的 8 位和取反加 1 风格校验，具体算法**未确认**）。
  `ledType ≤ 2` 为彩色（1=单色、2=多彩），`> 2` 直接使用原始 RGB 串。
- **回复**：无。
- **调用**：`index-3fa97e8c.js` 灯效保存流程；`index-0449b0ba.js` 灯条编辑页 `downloadLight=()`。
- **[确认 payload 结构]**

### 4.2 previewLight / previewLightbar — `0x03 / 0x00` 与 `0x20 / 0x??`

- **调用形状**（`App-163bf8f7.js`，带 1 s 去抖集合 `_t`，同 key 并发返回 `"busy"`）：
  ```js
  hidWriteTo(path, "previewLight",     syncId, 255, ledType, Uint8Array.from(rgb))
  hidWriteTo(path, "previewLightbar",  syncId, 255, ledType, Uint8Array.from(rgb))
  ```
  参数序列 = `(sync, 255, type, rgb[])`。
- **厂商实现**（`previewOrDownloadLight` @0x12220）：payload = `[type, brightness] + rgb`，
  `dist` 来自 `info[2]`，`brightness` 来自 `info[3]`（即上面那个 255）。
  命令码：`previewLight`/`previewLightWithoutThrottle` → `0x03`；`previewLightbar`/`lightbarLed` → `0x20`/`0x21`。
- **回复**：无（`Dispatch` 仍会注册 pending，实际按 1 s 超时回收：**未确认**）。
- 第二种写法：`index-3fa97e8c.js` `vr.lightBar.preview(type, rgb)` → `b("previewLightbar", 255, type, Uint8Array(rgb))`。
- **[确认调用形状；payload/arg 细节 推断]**

### 4.3 previewLightWithoutThrottle — `0x03 / 0x00`

- **调用**（环境氛围灯，`App-163bf8f7.js` line 1947）：
  ```js
  hidWriteTo(device.path, "previewLightWithoutThrottle", device.syncId, 255, 1, Uint8Array.from([0,0,0]))
  ```
  用于「关闭氛围灯 → 熄灯」。参数 = `(sync, 255, 1, [0,0,0])`。
- 与 §4.2 同一厂商实现，仅绕过渲染器侧节流。**[确认调用点]**

### 4.4 backlightBrightness — `0x20 / 0x15`

- **payload**：1 字节亮度（0..100 由 UI 限制；main 进程 IPC 透传）。
- **调用**：
  - `App-163bf8f7.js`：`window.ipc.rendererOn("write-brightness", (path, v) => hidWriteTo(path,"backlightBrightness",0,v))`
  - `background-066cfa05.js`：窗口滑块 100 ms 去抖 → `ipc.sendToApp("write-brightness", devicePath, r)`
  - 键盘回传：设备 `data` 帧 `cmd==0x20 && arg==0x15` 时把 `B[10]`(USB) / `B[11]`(BLE) 当新亮度推给 UI
- **[确认]**

### 4.5 指示灯 / 灯条 / 灯效颜色族（`0x20 / 0x18…0x2b`）

| 命令 | cmd/arg | payload | 回复 | 调用 |
| --- | --- | --- | --- | --- |
| `indicatorMode` | 20/18 | 1 字节 | 1 | `W.mode`（`index-3fa97e8c.js`） |
| `indicatorColor` | 20/1a | RGB 3 字节 | 3 字节 | `W.color`，空/全 0 → `#ffffff` |
| `indicatorKBMode` | 20/19 | 1 字节 | 1 | `Y.mode`（默认 0） |
| `indicatorKBColor` | 20/1b | RGB 3 字节 | 3 字节 | `Y.color` |
| `readCapslockLedColor` | a0/1c | 无 | 3 字节 | `H.color.get`（默认 `[255,0,0]`） |
| `writeCapslockLedColor` | 20/1c | RGB 3 字节 | 无 | `H.color.set` |
| `lightbarIndicatorMode` | 20/22 | 1 字节 | 1（>4 归 1） | `et.mode` |
| `lightbarIndicatorColor` | 20/26 | RGB 3 字节 | 3 字节 | `et.color` |
| `keylightIndicatorMode` | 20/25 | 1 字节 | 1（>4 归 2） | `H.mode` |
| `keyLedOCC1` | 20/2a | 1 字节 | 1 | `vr.keyLedOCC1` |
| `keyLedOCC2` | 20/2b | 1 字节 | 1 | `vr.keyLedOCC2` |
| `fireflyIndicatorMode` | 20/28 | 1 字节 | 1 | `es.indicator`，**dist=6（MCU_24G）** |
| `readLedPowerMode` | 20/1e | 无 | 1 | 渲染器无调用点（**未确认**） |
| `writeLedPowerMode` | 20/1f | 1 字节 | 无 | 同上 |
| `lightbarBrightness` | 20/23 | 1 字节 | 1 | 渲染器无调用点（**未确认**） |
| `lightHoldOn` | 20/0d | 1 字节 | 无 | 渲染器无调用点（**未确认**） |
| `toggleLed` | 20/01 | 1 字节 | 无 | 渲染器无调用点（**未确认**） |
| `writeBacklightAuto` | 01/0c（厂商：hidWriteWithArg1） | 1 字节 | 无 | 渲染器无调用点（**未确认**） |
| `writeIndicatorBrightness` | 20/14 | 1 字节 | 无 | 渲染器无调用点（**未确认**） |

**[确认 cmd/arg 与渲染器调用形状]**

---

## 5. 宏

### 5.1 checkMacroVersion — `0xb0 / 0x10`

- **payload**：无。**回复**：渲染器用返回值做真值判断（`const c = await D("checkMacroVersion", 0)`），
  具体字节含义**未确认**。
- **调用**：`M_()` 读取流程、`P_()` 写入流程各一次。

### 5.2 readMacroConfig — `0xb0 / 0x0c`

- **回复**：前 2 字节 u16 LE = 宏总数；`0` 或 `0xFFFF` → 视为无宏，直接返回空表。
- **调用**：`M_(keymapTable)`。

### 5.3 readMacroMap — `0xb0 / 0x0b`（arg 复用为 layer）

- **payload**：无（厂商侧把它当 `hidReadOrWrite`，layer 通过 `dist` 或 arg 传递：**未确认**）。
- **回复**：每键 1 字节宏 id，`0xFF` = 该键无宏；渲染器按 `keymapTable` 的键序展开成
  `{layer, keyIndex, macroGroup:-1, macroId, index}`。
- **调用**：`rt(t, layer)` 对 layer 0/1/2/3 各调一次。

### 5.4 readMacroApp — `0xb0 / 0x0d`（**不在 kCommands**）

- **payload**：`u16 LE 宏序号`。
- **回复**布局（`M_()` 解析）：
  ```
  [0..1] ?            [2..3] u16 nameLen        [4..5] u16 宏体长度
  [6..7] u16 icon（仅新固件分支）
  [8..11] 或 [6..9]   u32 uuid
  [..] 宏体 macroValue（长度 = bodyLen-3）
  [末尾 nameLen B]   utf16be 名称
  ```
  宏体起点 = `10`（旧）/`12`（新），长度 `bodyLen-3`；名称取回复尾部 `nameLen` 字节。
- **cmd/arg 来源**：厂商反汇编（`$0xb0` / stack arg `0x0d`），`kCommands` 缺失。

### 5.5 writeMacroConfig — `0x30 / 0x0c`

- **payload**：`u16 LE 宏数量`。
- **调用**：`P_()` 在写 map/条目之前先写一次。

### 5.6 writeMacroMap — `0x30 / 0x??`（**不在 kCommands**）

- **调用**：`b("writeMacroMap", Uint8Array([layer]), Uint8Array(mapArray))`
  → payload = 该层每个键 1 字节宏索引，`0xFF` 填充空位；`W800` 额外把颜色压暗 90%。
- 厂商实现 `writeMacroMap` @0x14970：`info[2]` = dist，`info[3]`/`info[4]` 两个 buffer；arg 精确值**未确认**。

### 5.7 writeMacroApp — `0x30 / 0x0d`（**不在 kCommands**）

- **payload**：
  ```
  [u16LE 宏序号][u16LE bodyLen][u16LE nameLen][u16LE icon][crc32 4B][宏体..., 0,0,0][utf16be 名称]
  ```
  新固件（`checkMacroVersion` 真值）带 icon 字段，旧固件省略。
- **回复**：无（写流程不等回复）。**[推断]**

### 5.8 clearMacro — `0x30 / 0x0a`

- **payload**：固定 4 字节 `[0,0,0,0]`（`Z("clearMacro",[0,0,0,0])`）。
- **调用**：`index-3fa97e8c.js` `ue()`，恢复出厂时清空宏区。

### 5.9 其余宏命令（渲染器无调用点）

`readMacro 30/09`、`readMacroActiveList 30/07`、`writeMacro 30/??`、`writeMacroFn 30/??`、
`resetMacro 30/??`、`downloadMacro 30/??`：仅出现在厂商分发表，payload 语义全部**未确认**。

---

## 6. 音效（Audio Visualizer）

### 6.1 writeAudioVisualConfig — `0x21 / 0x01`，dist=4（MCU_LED）

### 6.2 writeAudioVisualData — `0x21 / 0x02`，dist=4（MCU_LED）

- 二者均 `hidWriteWithBuffer` 族（厂商：`ecx=4` 作为 dist，payload 取 `info[3]`）。
- **渲染器调用点**：在 `packdir/dist/renderers/*.js` 里**未找到** `writeAudioVisualConfig` /
  `writeAudioVisualData` / `writeAudioVisualize` 的字面量。音效页存在（`App-163bf8f7.js` 里
  `ambientStore` / `audioStore.startCapture()` / BlackHole 2ch 回环采集），但真正下发走的是
  §4.2 的 `previewLight`（氛围灯颜色由音频频谱驱动）。
- **结论**：payload 结构与触发时机**未确认**；`writeAudioVisualize`（厂商独有，`cmd` 见
  `writeAudioVisualize` @0x132c0，`cmd=0x20`）同样**未确认**。

---

## 7. OLED（ApxTenet / T70）

### 7.1 writeOledImg — `0x70 / 0x01`

- **payload**：128 个包，每包 33 字节：`[rowIndex(0..127), 32 字节像素]`。
- **像素编码**（`index-ea81becb.js` `ti()`）：每 8 个源像素压成 4 字节——
  取 `(r+g+b)/3` 量化到 4 bit 作高半字节、下一像素作低半字节。
- **调用**：`downloadImg()`，256×32 裁剪画布。

### 7.2 writeOledChar — `0x70 / 0x08`

- **payload**：同 §7.1 的 128×33 结构（文字画布同样编码）。
- **调用**：`downloadText()`。

### 7.3 writeOledDateTime — `0x70 / 0x07`

- **payload**：`[month, day, weekday(1..7, 周日=7), hour, minute, second]`，各 1 字节。
- **调用**：`App-163bf8f7.js` `setTimeToKbd(path)`，在设备 `productId===61445` 且非 IAP 时，
  上线 5 s 后触发一次。

### 7.4 writeOledMonitor — `0x70 / 0x09`

- **payload**：`[cpuTemp, gpuTemp, hddTemp]`（各 1 字节，取整，缺省 0）。
- **调用**：`pollHardware()`：先 `window.api.getHardwareInfo()`（IPC），成功后写入，1 s 一轮；
  仅 `isServerStateOn` 为真时继续轮询。

### 7.5 oledTimeFormat — `0x70 / 0x0a`

- **payload**：1 字节（时间制式）。**调用**：`ki.timeFormat.get/set`（`index-ea81becb.js`）。

### 7.6 writeOledScroll — `0x70 / 0x05`（**不在 kCommands**）

- **payload**：1 字节开关（`zt("writeOledScroll", 1|0)`）。**调用**：`handleTextAnimation()`。

---

## 8. 无线 / 24G 模块

### 8.1 BLE

| 命令 | cmd/arg | 说明 |
| --- | --- | --- |
| `deleteBleHost` | 40/05 | 清除蓝牙配对；`hidWriteTo(path,"deleteBleHost",syncId,wirelessDist)`，dist = `wirelessDist` |
| `setBleOn` | 40/01 | 渲染器无调用点（**未确认**） |
| `readBleMac` | 40/30 | 渲染器无调用点（**未确认**） |

`deleteBleHost` 调用点：`index-3fa97e8c.js` `ve.deleteBleHost()`，仅 `profile.isMcuBle && isUsb` 时显示按钮。

### 8.2 4G/24G（`0x41` 族，dist 6=MCU_24G / 7=MODULE_24G）

| 命令 | cmd/arg | 读回复 | 调用 |
| --- | --- | --- | --- |
| `wl24gAddress` | 41/01 | 原样字节数组 | `es.address`（App-163bf8f7） |
| `wl24gSlave` | c1/02 | 从机列表 | `es.client.getAll` |
| `wl24gSlaveDel` | 41/03 | — | `es.client.delete` |
| `wl24gState` | 41/04 | 原样 | `es.getState` |
| `wl24gChannel` | 41/05 | 1 字节 | `es.channel` |
| `wl24gRestart` | 41/06 | — | `es.restart()` |
| `wl24gRunMode` | 41/07 | — | 无调用点（**未确认**） |
| `enterPairMode` / `exitPairMode` | 41/0d / 41/0e | — | 配对流程 |

`module24g*` 全族（`0x41 / 0x01..0x0b`，dist=7）用于键盘内置 24G 模块：`address/channel/syncId/
reinit/masterId/masterInfo`，调用点在 `index-3245b65a.js`（`G/J/Q/Ct/fe/he` 常量组）。
设备 `cmd==0x41 && arg==0x10` 的**上行帧**表示「正在配对」，渲染器收到后 `sendToApp("wireless-paring")`。**[确认]**

### 8.3 从机上线/下线（上行）

- `cmd==0xC1 && arg==0x13`：`B[10]` = slotId，`B[14]` = 在线标志 → `deviceStore.onDeviceUpdate(path, slotId, online)`。**[确认]**

---

## 9. 固件升级（IAP）

| 命令 | cmd/arg | payload | 调用 |
| --- | --- | --- | --- |
| `readIapMode` | 03/00 | 无；回复 1 字节 | `Ng.iapMode.get`（`1=IAP, 2=APP`） |
| `writeIapMode` | 03/00 | 1 字节 | `Ng.iapMode.set`，失败仅打日志 |
| `readIapFwVersion` | 01/03 | 无；回复 6 字节 | `Ng.readIapFwVersion()` |
| `writeIapMemory` | 04/00 | 数据块 Buffer，dist = 地址参数 | `Ng.writeIapMemory(addr, buf, dist)`，失败自动重试一次 |
| `writeEraseMemory` | 05/00 | 1 字节 | `Ng.eraseMemory(addr, v)` |

**注意**：`readIapMode` 与 `writeIapMode` 在 `kCommands` 中同码同 arg（`0x03/0x00`），
读/写差异只由 `cb` 是否存在与 payload 决定。**[确认]**

---

## 10. 虚拟鼠标 / 其他

| 命令 | cmd/arg | payload | 调用 |
| --- | --- | --- | --- |
| `vMouseCursorSpeed` | 60/01 | 1 字节（1..10） | `m.cursorSpeed`（`index-3fa97e8c.js`） |
| `vMouseCursorGain` | 60/06 | 1 字节（1..10） | `m.cursorGain` |
| `vMouseSpeedY` | 60/0? | 1 字节 | `m.wheelY`（1..10）；**不在 kCommands，arg 未确认** |
| `vMouseSpeedX` | 60/03 | 1 字节 | 无调用点（**未确认**） |
| `getCombinationMode` | 81/f1 | 无 / 回复 1 字节 | 无调用点（**未确认**） |
| `writeUDID` | 01/0e | 32 字节 | 无调用点（**未确认**） |
| `resetPowerOnTime` | 01/0b | 无 | 无调用点（**未确认**） |
| `setBleOn` | 40/01 | 1 字节 | 无调用点（**未确认**） |
| `argbPreview` | 10/00 | Buffer | 无调用点（**未确认**） |
| `akdmAllUp/Down/Single` | 52/01,02,03 | 1 字节 | 无调用点（**未确认**） |

---

## 11. 待办 / 需补齐项

1. `kCommands` 缺失但渲染器在用或厂商分发表里存在的命令：
   `kbdLayoutParam (0x90/0xf2)`、`readMacroApp (0xb0/0x0d)`、`writeMacroApp (0x30/0x0d)`、
   `writeMacroMap (0x30/?)`、`writeOledScroll (0x70/0x05)`、`vMouseSpeedY`、`wl24gState (0x41/0x04)`、
   `wl24gSlaveDel (0x41/0x03)`、`previewLight (0x03)`、`previewLightbar (0x20/0x21)`、
   `lightbarLed (0x21)`、`writeIndicatorBrightness (0x20/0x14)`、`indicatorKBMode/Color (0x20/0x19,0x1b)`。
2. `WriteTo` 参数映射需按 §1.4 修正：`info[3]` 数字 = 单字节 payload（不是 dist），
   `info[4]` = 大 payload；`keyboardLayer` 需同时接受 `(dist=layer, buf)`。
3. `ReplyLenFor` 需要补：`readMacroConfig`(2)、`keycapStyle`(2)、`readCapslockLedColor`(3)、
   `lightbarIndicatorColor`(3)、`kbdLayoutParam`(调用方指定)、`readMacroApp`(变长)。
4. §6 音效下发的真实入口仍需抓到实机报文才能确认。
