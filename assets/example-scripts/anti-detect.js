// anti-detect.js - 反检测脚本 (rustFrida QuickJS)
// 对抗常见的 Frida/root/hook 检测手段
// 建议配合 kfm stealth wxshadow 使用

// 1. Native 层：hook 常见的反调试检测
var openAddr = Module.findExportByName("libc.so", "open");
hook(openAddr, function(pathPtr, flags) {
    var path = Memory.readCString(ptr(pathPtr));

    // 拦截 /proc/self/maps 读取（检测 frida/agent SO）
    if (path && (path.indexOf("frida") !== -1 || path.indexOf("agent") !== -1)) {
        console.log("[Anti] Blocked open(): " + path);
        this.x0 = ptr(Memory.allocUtf8String("/dev/null"));
        return this.orig();
    }

    // 拦截 /proc/self/status 读取（检测 TracerPid）
    if (path && path.indexOf("/proc/self/status") !== -1) {
        console.log("[Anti] Redirecting /proc/self/status read");
    }

    return this.orig();
}, Hook.WXSHADOW);  // 使用影子页隐写，/proc/mem 不可见

// 2. hook ptrace 检测
var ptraceAddr = Module.findExportByName("libc.so", "ptrace");
if (ptraceAddr) {
    hook(ptraceAddr, function(request) {
        // PTRACE_TRACEME = 0
        if (Number(request) === 0) {
            console.log("[Anti] Blocked ptrace(PTRACE_TRACEME)");
            return 0;  // 假装成功
        }
        return this.orig();
    }, Hook.WXSHADOW);
}

// 3. hook strstr 检测（App 内搜索 "frida" 字符串）
var strstrAddr = Module.findExportByName("libc.so", "strstr");
if (strstrAddr) {
    hook(strstrAddr, function(haystack, needle) {
        var needleStr = Memory.readCString(ptr(needle));
        if (needleStr && (needleStr.indexOf("frida") !== -1 ||
                          needleStr.indexOf("gum-js") !== -1 ||
                          needleStr.indexOf("rustfrida") !== -1 ||
                          needleStr.indexOf("agent") !== -1)) {
            console.log("[Anti] Blocked strstr() for: " + needleStr);
            return 0;  // 返回 NULL，表示没找到
        }
        return this.orig();
    }, Hook.WXSHADOW);
}

// 4. Java 层反检测
Java.ready(function() {
    // 隐藏 su 二进制
    try {
        var Runtime = Java.use("java.lang.Runtime");
        Runtime.exec.overload("java.lang.String").impl = function(cmd) {
            if (cmd.indexOf("su") !== -1 || cmd.indexOf("magisk") !== -1) {
                console.log("[Anti] Blocked Runtime.exec: " + cmd);
                throw Java.use("java.io.IOException").$new("Permission denied");
            }
            return this.$orig(cmd);
        };
    } catch (e) {}

    // 隐藏 root 相关包
    try {
        var PM = Java.use("android.app.ApplicationPackageManager");
        PM.getPackageInfo.overload("java.lang.String", "int").impl = function(name, flags) {
            if (name.indexOf("magisk") !== -1 || name.indexOf("supersu") !== -1 ||
                name.indexOf("kernelsu") !== -1 || name.indexOf("kfm") !== -1) {
                console.log("[Anti] Hidden package: " + name);
                throw Java.use("android.content.pm.PackageManager$NameNotFoundException").$new(name);
            }
            return this.$orig(name, flags);
        };
    } catch (e) {}

    console.log("[Anti] Java anti-detection hooks installed");
});

console.log("[Anti] Anti-detection active (WXSHADOW mode)");

rpc.exports = {
    status: function() { return "anti-detect active"; }
};
