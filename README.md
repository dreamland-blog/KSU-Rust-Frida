# KSU-Frida Manager v2.0.0 — Powered by rustFrida

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
ksu-frida-manager/
├── module.prop                    # 模块元数据
├── META-INF/                      # 刷入框架
├── customize.sh                   # 安装脚本
├── service.sh                     # 开机清理 (不启动 rustfrida)
├── post-fs-data.sh                # 开机前期 (建目录)
├── uninstall.sh                   # 卸载清理
├── sepolicy.rule                  # SELinux 规则
├── build.sh                       # 构建脚本
├── system/bin/
│   ├── kfm                        # 命令调度器
│   └── rustfrida                  # 引擎二进制
├── scripts/                       # 子命令脚本
│   ├── kfm-start.sh
│   ├── kfm-stop.sh
│   ├── kfm-status.sh
│   ├── kfm-inject.sh
│   ├── kfm-spawn.sh
│   ├── kfm-watch.sh
│   ├── kfm-rpc.sh
│   ├── kfm-analyze-enter.sh
│   ├── kfm-analyze-exit.sh
│   ├── kfm-log.sh
│   ├── kfm-stealth.sh
│   └── lib/ (common.sh, logging.sh, json.sh)
└── assets/
    ├── default-config.json
    └── example-scripts/ (hello.js, bypass-ssl-pinning.js, ...)
```

---

## 兼容性

| 维度 | 支持范围 |
|------|---------|
| Root 方案 | KernelSU 0.7+, KSU-Next, Magisk 24+ |
| 架构 | arm64-v8a (ARM64 only) |
| Android | 9 (API 28) ~ 17 |
| 验证设备 | Pixel 6 Pro (Android 14/16, KernelSU 3.2.0 + SUSFS) |

---

## License

本模块整合了 [rustFrida](../rustFrida-master/) 引擎。rustFrida 使用 wxWindows 许可证（兼容 Frida）。
