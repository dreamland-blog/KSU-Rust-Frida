# KSU-Frida Manager v2.0.0 — Powered by rustFrida&Trace

> 整合 [rustFrida](../rustFrida-master/) 引擎的 KSU/Magisk 模块，提供完整的 Android ARM64 动态插桩管理方案。
> 解决 frida-server 开机卡 logo 问题，单一二进制，手机端按需管理。

---

## 目录

- [核心改进](#核心改进)
- [架构设计](#架构设计)
- [安装](#安装)
- [命令参考](#命令参考)
- [注入模式](#注入模式)
- [隐写模式](#隐写模式)
- [JS API](#js-api)
- [HTTP RPC](#http-rpc)
- [分析模式](#分析模式)
- [示例脚本](#示例脚本)
- [构建](#构建)
- [故障排查](#故障排查)
- [踩坑记录 & 已知问题](#踩坑记录--已知问题)

---

## 核心改进

| 维度 | 原版 KFM v1.0 (frida-server) | 整合版 v2.0 (rustFrida) |
|------|------|------|
| 二进制 | frida-server + frida-inject (两个) | **rustfrida 单文件** (内嵌 loader + agent) |
| 体积 | ~40MB (frida-server) | **~3.9MB** (自包含) |
| 通信 | 每次 `su -c "kfm xxx"` | **HTTP RPC 直连** (低延迟) |
| 注入模式 | attach only | **attach + spawn + watch-so** |
| 反检测 | 无 | **NORMAL / WXSHADOW / RECOMP** 三级隐写 |
| JS 引擎 | 依赖 Frida 版本 | **内置 QuickJS** (无版本依赖) |
| Java Hook | Frida API | **Frida 兼容 API** + ART 底层扩展 |
| Spawn 机制 | 无 | **zymbiote** (Zygote 劫持) |
| SO 监控 | 无 | **eBPF ldmonitor** (内核级 dlopen 追踪) |

---

## 架构设计

```
┌──────────────────────────────────────────────────────────────┐
│  用户层                                                       │
│                                                              │
│  终端: su -c 'kfm start/inject/spawn'                        │
│  App:  HTTP → 127.0.0.1:28042/rpc/0/myFunc (直连 RPC)        │
│  PC:   adb forward tcp:28042 tcp:28042 → curl/frida          │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  控制层: /system/bin/kfm → scripts/kfm-*.sh                  │
│                                                              │
│  kfm-start.sh    延迟启动 + 冲突检测 + 写 PID                 │
│  kfm-inject.sh   查找 PID → rustfrida --pid                  │
│  kfm-spawn.sh    rustfrida --spawn (zymbiote)                │
│  kfm-analyze-*.sh  模块禁用/恢复 + 重启                       │
│  kfm-rpc.sh      wget → rustfrida HTTP RPC                   │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  引擎层: /system/bin/rustfrida (3.9MB, ARM64 ELF)            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ 内嵌组件 (include_bytes! 编译时打包)                    │    │
│  │  ├── bootstrapper.bin  (10KB ARM64 shellcode)         │    │
│  │  ├── rustfrida-loader.bin (2.5KB loader shellcode)    │    │
│  │  └── libagent.so (QuickJS + hook engine + crash handler)│   │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  功能模块:                                                    │
│  ├── ptrace 注入 (attach to PID)                              │
│  ├── zymbiote (zygote hijack for spawn)                      │
│  ├── HTTP RPC server (多 session, JSON API)                   │
│  ├── REPL (交互式 JS, Tab 补全)                                │
│  ├── SELinux policy patching                                  │
│  └── stealth hooks (NORMAL / WXSHADOW / RECOMP)              │
└──────────────────────────────────────────────────────────────┘
```

### 为什么不卡 logo?

```
铁律: service.sh / post-fs-data.sh 绝不启动 rustfrida

开机流程:
  init.rc → zygote → system_server → boot_completed
                                            ↓
                    service.sh 只做: 清理残留 PID + pkill 僵尸进程
                                            ↓
                    用户手动: kfm start (检查 uptime>30s + 延迟 3s)
                                            ↓
                    rustfrida 在安全时间点启动, 不与 zygisk 竞争
```

---

## 安装

### 前置条件
- 已 root 的 ARM64 设备 (KernelSU / KSU-Next / Magisk)
- Android 9+

### 安装步骤

```bash
# 推送模块到手机
adb push ksu-frida-manager-v2.0.0.zip /sdcard/Download/

# 方式1: KSU-Next Manager → 模块 → 从存储安装
# 方式2: Magisk Manager → 模块 → 从存储安装

# 重启
adb reboot

# 验证
adb shell "su -c 'kfm version'"
# → {"module":"v2.0.0","rustfrida":"0.16.10"}

adb shell "su -c 'kfm status'"
# → {"server":{"running":false,...},"module_version":"v2.0.0",...}
```

---

## 命令参考

### 生命周期

```bash
kfm start                      # 启动 rustfrida (RPC port 28042, localhost)
kfm start --rpc-port 9191      # 自定义 RPC 端口
kfm stop                       # 停止 rustfrida, 清理进程
kfm restart                    # 重启
kfm status                     # JSON 状态 (进程/端口/模式/版本)
```

### 注入

```bash
kfm inject <pkg> <script>      # attach 到已运行的 App
kfm spawn <pkg> [script]       # 启动 App 并从第一行代码 hook
kfm watch <so_name> <script>   # 等 SO 加载再注入 (需 eBPF)
```

### 分析模式

```bash
kfm analyze enter              # 禁用 zygisk/PIF 等冲突模块 → 重启
kfm analyze exit               # 恢复所有模块 → 重启
kfm analyze status             # 当前是 normal 还是 analysis
```

### 隐写模式

```bash
kfm stealth                    # 查看当前模式 + 可用模式
kfm stealth normal             # 标准模式 (默认)
kfm stealth wxshadow           # 影子页 (/proc/mem 不可见)
kfm stealth recomp             # 代码重编译 (仅 4B patch)
```

### RPC 远程调用

```bash
kfm rpc call <func> [args...]  # 调用 JS 导出的函数
kfm rpc eval <code>            # 执行 JS 代码
kfm rpc sessions               # 列出活跃 session
```

### 工具

```bash
kfm log server                 # 查看 rustfrida 日志
kfm log server -f              # 实时跟踪日志
kfm log kfm                   # 查看 kfm 管理器日志
kfm version                    # 模块 + 引擎版本
kfm help                       # 帮助
```

---

## 注入模式

### 1. Attach (附加到运行中的进程)

```bash
kfm inject com.example.app /sdcard/hook.js
```

**原理**: rustfrida 通过 ptrace 系统调用附加到目标进程 → 注入 ARM64 bootstrapper shellcode → 探测 libc 符号 → 加载 rustfrida-loader → dlopen libagent.so → 初始化 QuickJS 引擎 → 执行用户 JS 脚本。

**适用场景**: App 已经在运行，想 hook 某个函数。

### 2. Spawn (从启动开始 hook)

```bash
kfm spawn com.example.app hook.js
```

**原理**: rustfrida 注入 `zymbiote` 到 Android 的 zygote 进程 → hook `setArgV0()` 和 `selinux_android_setcontext()` → 当目标 App 从 zygote fork 出来时，暂停子进程 → 注入 agent → 恢复执行。

**优势**: 可以 hook `Application.onCreate()`、`ClassLoader` 初始化、甚至 `<clinit>` 静态初始化块。标准 attach 模式做不到这些。

### 3. Watch-SO (SO 加载触发)

```bash
kfm watch libnative.so hook.js
```

**原理**: 利用 eBPF 在内核层追踪 dlopen/dlopen64 系统调用 → 当目标进程加载指定 SO 时自动触发注入。

**适用场景**: 目标 App 延迟加载 native 库，需要精确在 SO 加载那一刻 hook `JNI_OnLoad` 或 SO 内部函数。

> 注意：watch-so 需要编译时启用 ldmonitor feature (`--features ldmonitor-feature`)

---

## 隐写模式

rustfrida 支持三级内存保护，对抗不同强度的反 hook 检测：

| 模式 | 代码修改方式 | /proc/mem 可见? | 性能影响 | 适用场景 |
|------|------------|----------------|---------|---------|
| **NORMAL** | mprotect RWX → 直写代码页 | 可见 | 无 | 普通分析 |
| **WXSHADOW** | 内核分配影子页，原页不变 | 不可见 | 微小 | 有反 Frida 检测的 App |
| **RECOMP** | 整函数重编译到新内存，原地仅 4B 跳转 | 仅 4B 可见 | 中等 | 高强度反 hook 环境 |

```bash
# 全局设置 (写入 config.json, 重启 rustfrida 生效)
kfm stealth wxshadow
kfm restart

# 或在 JS 脚本中按函数指定
hook(target, callback, Hook.WXSHADOW);
hook(target, callback, Hook.RECOMP);
Interceptor.attach(target, {onEnter, onLeave}, Hook.WXSHADOW);
```

---

## JS API

rustfrida 的 QuickJS 引擎提供 **Frida 兼容 API**，同时扩展了 Jni、NativeFunction、QBDI 等能力。

### Native Hook

```javascript
// 基本 hook (Frida 风格)
hook(Module.findExportByName("libc.so", "open"), function(path, flags) {
    console.log("open:", Memory.readCString(ptr(path)));
    return this.orig();  // 调用原函数
});

// 修改返回值
hook(Module.findExportByName("libc.so", "getpid"), function() {
    this.orig();
    return 12345;
});

// Interceptor.attach (双阶段)
Interceptor.attach(Module.findExportByName("libc.so", "open"), {
    onEnter(args) {
        this.path = args[0].readCString();
    },
    onLeave(retval) {
        console.log("open(" + this.path + ") = " + retval.toInt32());
    }
});

// NativeFunction (任意签名调用)
var open = new NativeFunction(
    Module.findExportByName("libc.so", "open"),
    "int", ["pointer", "int"]
);
var fd = open(Memory.allocUtf8String("/tmp/test"), 0);

// 移除 hook
unhook(Module.findExportByName("libc.so", "open"));
```

### Java Hook

```javascript
// Java.perform 和 Java.ready 完全等价，兼容标准 Frida 脚本
Java.perform(function() {
    var Activity = Java.use("android.app.Activity");

    // hook 实例方法
    Activity.onResume.impl = function() {
        console.log("onResume:", this.$className);
        return this.$orig();
    };

    // 指定 overload
    var MyClass = Java.use("com.example.MyClass");
    MyClass.foo.overload("int", "java.lang.String").impl = function(i, s) {
        console.log("foo called:", i, s);
        return this.$orig(i, "modified");
    };

    // 字段访问
    var Build = Java.use("android.os.Build");
    console.log("Model:", Build.MODEL.value);
    Build.MODEL.value = "FakeDevice";

    // 创建对象
    var JString = Java.use("java.lang.String");
    var s = JString.$new("hello from rustFrida");

    // 移除 hook
    Activity.onResume.impl = null;
});
```

### JNI API

```javascript
// 获取 JNI 函数地址
var registerNatives = Jni.addr("RegisterNatives");
var findClass = Jni.addr("FindClass");

// 获取 JNIEnv
var env = Jni.env;
```

### RPC 导出

```javascript
rpc.exports = {
    ping: function() { return "pong"; },
    getAppName: function() {
        var ctx = Java.use("android.app.ActivityThread")
            .currentApplication().getApplicationContext();
        return String(ctx.getPackageName());
    }
};

// 调用: kfm rpc call ping
// 或:   curl -X POST http://127.0.0.1:28042/rpc/0/ping
```

---

## HTTP RPC

rustfrida 内置 HTTP RPC 服务器，`kfm start` 后自动监听。

### 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | 健康检查 |
| GET | `/sessions` | 列出所有 session |
| POST | `/rpc/<session>/<method>` | 调用 JS 导出函数 |

### 使用

```bash
# 从手机本地调用
wget -qO- http://127.0.0.1:28042/health

# 从 PC 调用 (需要 adb forward)
adb forward tcp:28042 tcp:28042
curl http://127.0.0.1:28042/sessions
curl -X POST http://127.0.0.1:28042/rpc/0/ping
curl -X POST http://127.0.0.1:28042/rpc/0/add -d '[3, 4]'
# → {"ok":true,"result":7}
```

---

## 分析模式

分析模式用于需要深度调试但 zygisk 模块冲突的场景。

### 流程

```
正常模式 (zygisk/PIF 等全部启用, 银行 App 正常)
    ↓ kfm analyze enter
禁用冲突模块 → 自动重启
    ↓
分析模式 (zygote 干净, rustfrida 无冲突)
    ↓ kfm start + kfm inject/spawn
完成分析
    ↓ kfm stop → kfm analyze exit
恢复所有模块 → 自动重启
    ↓
正常模式 (银行 App 恢复正常)
```

### 冲突模块清单 (可配置)

默认禁用: `zygisksu`, `zygisk_vector`, `playintegrityfix`, `pifs_cleverestech`, `YH_YC`

可在 `/data/adb/kfm/config.json` 的 `conflict_modules` 数组中自定义。

---

## 示例脚本

模块内置 5 个示例脚本，安装后位于 `/data/adb/kfm/scripts/`:

| 脚本 | 功能 | 用法 |
|------|------|------|
| `hello.js` | 基础测试，打印设备信息 | `kfm inject com.app hello.js` |
| `dump-okhttp.js` | 抓取 OkHttp 请求/响应 | `kfm inject com.app dump-okhttp.js` |
| `bypass-ssl-pinning.js` | 绕过 SSL Pinning | `kfm inject com.app bypass-ssl-pinning.js` |
| `anti-detect.js` | 反 Frida/root 检测 | `kfm inject com.app anti-detect.js` |
| `trace-jni.js` | 追踪 JNI 调用 | `kfm inject com.app trace-jni.js` |

---

## 构建

### 前置条件

- Android NDK 25+
- Rust toolchain + `aarch64-linux-android` target
- Python 3
- (可选) `bpf-linker` (仅 watch-so 功能)

### 一键构建

```bash
cd ksu-frida-manager
./build.sh
# 产出: build/ksu-frida-manager-v2.0.0.zip
```

### 手动构建

```bash
# 1. 安装 Rust target
rustup target add aarch64-linux-android

# 2. 配置 .cargo/config.toml (指向你的 NDK 路径)

# 3. 构建 loader shellcode
cd rustFrida-master
python3 loader/build_helpers.py

# 4. 构建 agent
cargo build -p agent --release

# 5. 构建 rustfrida
cargo build -p rust_frida --release

# 6. 打包
cp target/aarch64-linux-android/release/rustfrida ../ksu-frida-manager/system/bin/
cd ../ksu-frida-manager
zip -r ksu-frida-manager-v2.0.0.zip . -x '*.DS_Store' 'build*' 'README*'
```

### 构建产物

```
loader/build/bootstrapper.bin      10KB   ARM64 进程探测 shellcode
loader/build/rustfrida-loader.bin  2.5KB  Agent 加载 shellcode
target/.../libagent.so             ~2MB   注入到目标进程的动态库
target/.../rustfrida               3.9MB  自包含主程序 (ARM64 ELF)
ksu-frida-manager-v2.0.0.zip      1.7MB  KSU/Magisk 刷入包
```

---

## 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| `kfm: command not found` | 模块未装或未重启 | 重启手机 |
| `kfm: inaccessible or not found` | KernelSU+SUSFS overlay 未挂载 | 见下方 [PATH 问题](#path-问题kfm-找不到) |
| `kfm start` 返回 requires root | App 没 root 权限 | KSU/Magisk 中给 App 授权 |
| `system too young, wait Ns more` | 开机时间 <30s | 等待系统完全启动后再试 |
| `rustfrida binary not found` | overlay 未生效，路径找不到 | 见下方 [二进制路径问题](#rustfrida-binary-not-found) |
| `rustfrida died within 2s` | 多种原因 | 见下方 [启动闪退问题](#rustfrida-died-within-2s) |
| 注入后 App 闪退 | hook 代码有误 | 检查 JS 脚本，确认函数签名 |
| 分析模式进去卡 logo | 禁了必要模块 | adb 连接 → `rm /data/adb/modules/xxx/disable` |
| RPC 连不上 | 端口未转发 | `adb forward tcp:28042 tcp:28042` |

### 日志文件

```
/data/adb/kfm/logs/rustfrida.log   # 引擎日志 (启动/注入/错误)
/data/adb/kfm/logs/kfm.log         # 管理器日志 (命令执行记录)
```

---

## 踩坑记录 & 已知问题

### PATH 问题：kfm 找不到

**现象**：安装模块重启后，`su -c "kfm"` 报 `inaccessible or not found`。

**原因**：KernelSU + SUSFS 环境下，magic mount (OverlayFS) 有时不会将模块的 `system/bin/` 文件挂载到 `/system/bin/`。这不是模块 bug，是 KSU+SUSFS 的已知行为。

**解决方案（推荐）**：将 kfm wrapper 放到 KSU 自带的 PATH 目录：

```bash
# 一次性执行，永久生效（重启不丢）
su -c 'cat > /data/adb/ksu/bin/kfm << "EOF"
#!/system/bin/sh
exec sh /data/adb/modules/ksu-frida-manager/system/bin/kfm "$@"
EOF
chmod 755 /data/adb/ksu/bin/kfm'
```

验证：
```bash
su -c "which kfm"
# → /data/adb/ksu/bin/kfm
su -c "kfm version"
```

**原理**：KernelSU su shell 的 PATH 包含 `/data/adb/ksu/bin`，在此目录放转发脚本即可绕过 overlay 问题。

---

### rustfrida binary not found

**现象**：`kfm start` 返回 `{"status":"error","reason":"rustfrida binary not found at /system/bin/rustfrida"}`

**原因**：同上，overlay 未挂载，`/system/bin/rustfrida` 不存在。

**解决**：v2.0.0 已修复。`common.sh` 会自动检测路径：

```sh
# 优先 /system/bin（overlay 正常时）
# fallback 模块目录（overlay 失效时）
if [ -x "/system/bin/rustfrida" ]; then
    RUSTFRIDA_BIN="/system/bin/rustfrida"
else
    RUSTFRIDA_BIN="$MODULE_DIR/system/bin/rustfrida"
fi
```

如果仍然报错，检查二进制是否存在且有执行权限：
```bash
su -c "ls -la /data/adb/modules/ksu-frida-manager/system/bin/rustfrida"
su -c "file /data/adb/modules/ksu-frida-manager/system/bin/rustfrida"
```

---

### rustfrida died within 2s

**现象**：`kfm start` 返回 died within 2s，查日志发现 server 启动后立即退出。

**常见原因 & 解决**：

#### 原因1：无效 CLI 参数

日志中如果看到 `unexpected argument '--stealth'`：

```
error: unexpected argument '--stealth' found
```

**解释**：`--stealth` 不是 rustfrida CLI 参数。隐写模式通过运行时 RPC/REPL 设置，不是启动参数。

**解决**：不要在 `kfm start` 时传 `--stealth`，改用运行后设置：
```bash
kfm start
kfm stealth wxshadow   # 运行时切换
```

#### 原因2：stdin EOF 导致 server REPL 退出

日志中看到正常启动后立即 "正在退出 server..."：

```
RPC HTTP server listening on 0.0.0.0:28042
Server 模式已启动 ...
正在退出 server...     ← 立即退出
```

**解释**：rustfrida server 模式内置交互式 REPL (rustyline)。`nohup` 将 stdin 重定向到 `/dev/null`，readline 收到 EOF 立即退出。

**解决**：v2.0.0 已修复。使用 FIFO 保持 stdin 打开：

```sh
# kfm-start.sh 中的实现
FIFO_FILE="$RUNTIME_DIR/run/rustfrida.fifo"
mkfifo "$FIFO_FILE"
sleep 2147483647 > "$FIFO_FILE" &  # 持有写端防 EOF
"$RUSTFRIDA_BIN" $ARGS < "$FIFO_FILE" > "$LOG_FILE" 2>&1 &
```

---

### JS 兼容性：Java.perform vs Java.ready

**现象**：标准 Frida 脚本中的 `Java.perform(function() {...})` 报错 `Java.perform is not a function`。

**解决**：v2.0.0 已内置兼容。`Java.perform` 是 `Java.ready` 的原生别名，两种写法均可：

```javascript
// Frida 标准写法 ✓
Java.perform(function() {
    var Activity = Java.use("android.app.Activity");
    // ...
});

// rustfrida 原生写法 ✓
Java.ready(function() {
    var Activity = Java.use("android.app.Activity");
    // ...
});
```

> 注意：如果使用旧版 rustfrida 二进制，需要在脚本头部加 polyfill：
> ```javascript
> if (typeof Java.perform === 'undefined' && typeof Java.ready === 'function') {
>     Java.perform = Java.ready;
> }
> ```

---

### 设备上无 wget/curl

**现象**：想在手机上直接测试 RPC 但没有 HTTP 客户端。

**解决**：

```bash
# 方式1：从 PC 端通过 adb forward 测试
adb forward tcp:28042 tcp:28042
curl http://127.0.0.1:28042/sessions
curl -X POST http://127.0.0.1:28042/rpc/0/ping

# 方式2：用 kfm rpc 子命令（内部使用 busybox wget）
kfm rpc sessions
kfm rpc call ping

# 方式3：安装 busybox 模块后使用 wget
busybox wget -qO- http://127.0.0.1:28042/health
```

---

### 重启后需要重新启动 server

**这是设计行为，不是 bug。** rustfrida 不随开机启动（防卡 logo）。每次重启后需手动：

```bash
su -c "kfm start"
```

如果确实需要开机自启（自行承担风险），可修改 `service.sh`：

```sh
# ⚠️ 不推荐 — 如果 rustfrida 出问题会卡 logo
(sleep 60 && /data/adb/ksu/bin/kfm start) &
```

---

## 目录结构

```
KSUhook/
├── deploy.sh                 # 一键部署引擎+脚本到设备
├── run.sh                    # 注入目标 App (attach / spawn / 后台)
│
├── hook.js                   # 通用 SSL Pinning 解钉 (Conscrypt/OkHttp/WebView...)
├── hook2.js                  # TikTok 抓包 (native Cronet/mssdk hook)
├── hook_keeta_capture.js     # Keeta mtgsig 抓取 (本仓库重点)
├── scripts/
│   ├── qbdi.js               # Qbdi 高层封装: 读写寄存器/内存 + QBDI Trace
│   ├── bypass_and_modify.js  # Tier1 实战: 任意地址读写寄存器/内存篡改 (自包含)
│   ├── qbdi_trace.js         # QBDI 指令级 Trace 模板 (需 --qbdi 构建)
│   ├── grab_all.js           # Grab 更新绕过 + SSL + 网络监控 (规范写法范例)
│   ├── grab1.js / grab2.js   # Grab 更新绕过 / SSL 解钉
│   └── Trip.js               # Trip.com SSL 解钉
├── tools/
│   └── trace_decode.py       # QBDI trace_bundle.pb 离线解码器 (零依赖, capstone 可选反汇编)
│
├── rustFrida-master/         # rustfrida 引擎源码 + 预编译二进制
│   ├── quickjs-hook/         # QuickJS 脚本运行时 (Java/Native/qbdi JS API)
│   ├── qbdi/                 # QBDI 静态库 (libQBDI.a + 头文件)
│   └── qbdi-helper/          # QBDI 封装 -> qbdi_helper.so (trace bundle 写盘)
├── ksu-frida-manager/        # KFM — 设备端常驻管理模块 (可选, 见下)
└── docs/
    └── 使用文档.md           # ★ 详细使用手册 (部署/KFM/QBDI/排错)
```

---

## 兼容性

| 维度 | 支持范围 |
|------|---------|
| Root 方案 | KernelSU 0.7+, KSU-Next, Magisk 24+ |
| 架构 | arm64-v8a (ARM64 only) |
| Android | 9 (API 28) ~ 17 |
| 验证设备 | Pixel 6 Pro (Android 14/16, KernelSU 3.2.0 + SUSFS) |

### Tier 2 — QBDI 指令级 Trace(需 `./deploy.sh --qbdi`)

> [!IMPORTANT]
> QBDI 是**编译期 feature,预编译二进制默认没开**。必须 `./deploy.sh --qbdi` 重新编译部署,全局 `qbdi` 对象与 `Qbdi.setupTrace` 才可用。源码在 `rustFrida-master/{qbdi,qbdi-helper}/`。

和标准 Frida / 网上教程的关键差异:

- 不是 `new Qbdi.VM()` + 逐指令 JS 回调(那样每条指令回 JS 会 ANR)。Trace 由原生 `qbdi_helper.so` 把「指令 + 寄存器 + 内存访问 + call/ret」写成 **protobuf trace bundle 落盘**到**应用私有目录**(默认 `/data/data/<包名>/trace_bundle.pb`),拉回来**离线解码**。
- QBDI 在自己的 VM 里**重放**目标代码,所以流程是 `Interceptor.attach` 命中 → 在 VM 内 `qbdi.call(...)` 重放并产出 trace。

一键 Trace(`run.sh` 自动拼接 `qbdi.js` + 入口脚本):

```bash
# 1. 带 QBDI 编译部署 (需 Rust + Android NDK; 仓库的预编译二进制已带 QBDI)
./deploy.sh --qbdi

# 2. 一键追踪某 native 函数 (偏移或导出符号都行)
./run.sh --trace     com.sankuai.sailor.afooddelivery libmtguard.so 0x5b120
./run.sh --trace     com.zhiliaoapp.musically         libc.so       open
./run.sh --trace-mem com.sankuai.sailor.afooddelivery libmtguard.so 0x5b120   # 含内存访问

# 3. 触发目标逻辑后, 一键拉取 + 离线解码
./run.sh --pull-trace com.sankuai.sailor.afooddelivery
```

### 离线解码 trace bundle(`tools/trace_decode.py`)

落盘的 `trace_bundle.pb` = 4 字节 magic `TRB1` + 一串 length-delimited protobuf 事件(指令地址 / 内存访问 / 外部返回 / 动态代码块 / 寄存器快照 / 模块元数据)。解码器零依赖,装了 `capstone` 还能反汇编指令流:

```bash
# 手动拉取 (trace 在应用私有目录, 需 su)
adb shell "su -c 'cat /data/data/<包名>/trace_bundle.pb'" > trace_bundle.pb

python3 tools/trace_decode.py trace_bundle.pb                 # 概览 + 顺序事件
python3 tools/trace_decode.py trace_bundle.pb --insn --disasm # 仅指令流 + 反汇编 (pip install capstone)
python3 tools/trace_decode.py trace_bundle.pb --mem           # 仅内存读写
python3 tools/trace_decode.py trace_bundle.pb --rebase        # 地址显示为 模块base+偏移
python3 tools/trace_decode.py trace_bundle.pb --summary       # 只看各类事件计数
python3 tools/trace_decode.py trace_bundle.pb --dump-chunks ./code  # 导出动态执行的代码镜像
```

脚本里手动用 `Qbdi` 封装(等价于 `run.sh --trace` 内部逻辑):

```javascript
var m = Process.findModuleByName('libmtguard.so');
var target = m.base.add(0x5b120);                          // 可执行地址(函数入口)
Qbdi.setupTrace(target, '/data/data/<包名>');             // target 必须可执行; attach 模式必须传输出目录
Qbdi.hookWithQbdi(target);                                 // 命中即在 VM 内重放并产 trace
// ... 触发后 ...
Qbdi.stopTrace();                                          // 内部会 qbdi.shutdown() flush + 发布 trace_bundle.pb
```

> 真机实测验证过的三个铁律(否则 trace 出不来):
> ① `setupTrace`/`registerTraceCallbacks` 的 target 必须是**可执行地址**,传模块基址会 `not found in /proc/self/maps`;
> ② attach(`-p PID`)模式默认输出目录为空,**必须显式传**应用可写目录(如 `/data/data/<包名>`);
> ③ 必须 `qbdi.shutdown()`(`Qbdi.stopTrace()` 已内置)才会同步 flush 并发布 `trace_bundle.pb`。

底层 `qbdi.*` 扁平 API(`Qbdi` 封装即基于此):`newVM / destroyVM / allocateVirtualStack / addInstrumentedRange / addInstrumentedModuleFromAddr / recordMemoryAccess / registerTraceCallbacks / unregisterTraceCallbacks / run / call / getGPR / setGPR / getFPR / setFPR / lastError`;常量 `MEMORY_READ|WRITE|READ_WRITE`、`REG_PC|LR|SP|BP|FLAG|RETURN`。

### 性能与避坑

> [!WARNING]
> DBI 指令级插桩开销极大(目标函数可慢 10~50 倍),对高频/密集计算逻辑(如 OLLVM 控制流平坦化)易触发 ANR 或写盘爆量。

- **只追小范围**:`setupTrace(base, size)` 圈定单个 `.so` 或函数区间,别全量插桩系统库。
- 用完及时 `Qbdi.stopTrace()`,并清理 `/data/data/<包名>/trace_bundle.pb*`(含分片 `.s*.part*`)。
- `qbdi` 未定义 / `newVM` 返回 null / `lastError()` 报 "blob not configured" → 引擎没带 QBDI feature,回到 `./deploy.sh --qbdi`。
- App 闪退 `SIGSEGV (SEGV_ACCERR)`:多半插桩到了非可执行页,确认 `setupTrace` 的 base/size 只覆盖目标 SO 的可执行段。

---

## 脚本语法铁律(重要)

rustfrida 跑 **QuickJS**,与标准 Frida (V8) 有三条必须遵守的差异。**所有仓库内脚本都遵循此规范**(参考 `scripts/grab_all.js`):

| # | 标准 Frida | rustfrida | 用错后果 |
|---|-----------|-----------|----------|
| 1 | `.implementation =` | `.impl =`(`.implementation` 是其别名,也可用) | — |
| 2 | `this.方法名(args)` 调原方法 | **`this.$orig(args)`** | 用错 → **无限递归崩溃** |
| 3 | `Java.registerClass()` | 不支持 | 改为直接 hook 系统类 |

`.overload(...)` **支持**,用法同 Frida(`.overload('java.lang.String','int')` 或裸 JNI 签名 `.overload('(Ljava/lang/String;)V')`)。

其它注意点:

| 问题 | 说明 |
|------|------|
| 多个 `Java.perform()` | 只执行**最后一个**,所有 Java hook 必须合并进同一个 |
| `setTimeout` / `Script.nextTick` | 不存在,需 polyfill |
| `Java.enumerateLoadedClasses` | 可用(`hook.js` 用它扫混淆 pinner) |
| Java 反射(`getDeclaredMethods`) | 不可用,用方法名穷举替代 |

### 标准模板

```javascript
'use strict';

// Polyfill: rustfrida 用 Java.ready 代替 Java.perform
if (typeof Java !== 'undefined' && typeof Java.perform === 'undefined'
    && typeof Java.ready === 'function') {
    Java.perform = Java.ready;
}

Java.perform(function () {
    var Foo = Java.use('com.example.Foo');

    // 正确
    Foo.bar.overload('int').impl = function (x) {
        console.log('hooked: ' + x);
        return this.$orig(x);     // 调原方法
    };

    // 错误 — 无限递归!
    // Foo.bar.impl = function (x) { return this.bar(x); };
});
```

---

## SSL Pinning 解钉

`hook.js` 是通用解钉脚本,覆盖:Conscrypt `TrustManagerImpl.verifyChain` / `Platform.checkServerTrusted`、`SSLContext.init`、OkHttp `CertificatePinner`(含 R8 混淆变体扫描)、`HostnameVerifier`、`NetworkSecurityTrustManager`、WebView `onReceivedSslError`。

```bash
./run.sh com.airbnb.android hook.js
# 配合 Charles/Burp 设系统代理即可抓 HTTPS
```

---

## KFM 设备端常驻模块(可选)

`ksu-frida-manager/` 是把 rustfrida 封装成 Magisk/KSU 模块的方案,装上后可在设备上直接用 `kfm` 命令注入(适合不接电脑的场景)。

### 安装

```bash
# 1. 把二进制塞进模块再打包
cp rustFrida-master/target/aarch64-linux-android/release/rustfrida \
   ksu-frida-manager/system/bin/rustfrida
cd ksu-frida-manager && zip -r ../ksu-frida-manager.zip . -x '*.DS_Store' && cd ..

# 2. 推送并安装 (Magisk)
adb push ksu-frida-manager.zip /sdcard/
adb shell "su -c 'magisk --install-module /sdcard/ksu-frida-manager.zip'"
adb shell "su -c 'reboot'"

# 2'. KernelSU
adb shell "su -c 'ksud module install /sdcard/ksu-frida-manager.zip'"
adb shell "su -c 'reboot'"
```

### KSU 额外配置(重启后执行一次)

> [!IMPORTANT]
> KSU 的 `/system/bin` overlay 可能不生效,需手动链接到 KSU 的 PATH 目录。Magisk 无需此步。

```bash
adb shell "su -c '
  cp /data/adb/modules/ksu-frida-manager/system/bin/kfm      /data/adb/kfm/kfm
  cp /data/adb/modules/ksu-frida-manager/system/bin/rustfrida /data/adb/kfm/rustfrida
  chmod 755 /data/adb/kfm/kfm /data/adb/kfm/rustfrida
  ln -sf /data/adb/kfm/kfm      /data/adb/ksu/bin/kfm
  ln -sf /data/adb/kfm/rustfrida /data/adb/ksu/bin/rustfrida
'"
```

### kfm 命令

```bash
kfm inject <包名> <脚本>            # attach 注入
kfm inject <包名> <脚本1> <脚本2>   # 多脚本 (自动合并)
kfm spawn  <包名> <脚本>            # spawn 注入
kfm start | stop                   # 启停常驻 server
```

---

## FAQ

| 问题 | 解决 |
|------|------|
| `rustfrida 未部署` | 先 `./deploy.sh` |
| hook 后 App 无限循环/崩溃 | 调原方法用错了 — 把 `this.方法名()` 改成 `this.$orig()` |
| hook 不生效 | 确认用 `.impl`/`.implementation`;spawn 大型 App 易超时,改 attach |
| 多脚本只执行一个 | 合并到一个文件,只保留一个 `Java.perform` |
| `registerClass` 报错 | 不支持,改为直接 hook 系统类(如 `TrustManagerImpl.verifyChain`) |
| `kfm: not found` (KSU) | 执行上方「KSU 额外配置」链接到 `/data/adb/ksu/bin/` |
| `kfm spawn` 超时 | 大型 App 用 `kfm inject`(先启动再注入) |
| 找不到目标方法 | App 可能混淆/分包,先用 `Java.enumerateLoadedClasses` 确认类名 |
| `qbdi is not defined` / `newVM` 返回 null | 引擎没带 QBDI feature,用 `./deploy.sh --qbdi` 重新编译部署 |
| QBDI trace 导致 App 卡死/ANR | 缩小插桩范围(只圈单个函数),用完及时 `unregisterTraceCallbacks`+`destroyVM` |

---



---

## License

本模块整合了 [rustFrida](../rustFrida-master/) 引擎。rustFrida 使用 wxWindows 许可证（兼容 Frida）。
