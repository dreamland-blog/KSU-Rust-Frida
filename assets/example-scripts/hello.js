// hello.js - 基础测试脚本 (rustFrida QuickJS)
// 验证 rustfrida 注入是否成功

console.log("[+] rustFrida agent loaded");
console.log("[+] Process PID: " + Process.id);

// 列出已加载的模块
var mods = Module.enumerateModules();
console.log("[+] Loaded modules: " + mods.length);
for (var i = 0; i < Math.min(mods.length, 10); i++) {
    console.log("    " + mods[i].name + " @ " + mods[i].base + " (" + mods[i].size + ")");
}

// 测试 Java 环境
Java.ready(function() {
    console.log("[+] Java VM available");
    var Build = Java.use("android.os.Build");
    console.log("[+] Device: " + Build.MODEL.value);
    console.log("[+] Android: " + Build.VERSION.RELEASE.value);
    console.log("[+] SDK: " + Build.VERSION.SDK_INT.value);
});

// 注册 RPC 导出（可通过 kfm rpc call 调用）
rpc.exports = {
    ping: function() { return "pong from rustFrida"; },
    info: function() {
        return {
            pid: Process.id,
            modules: Module.enumerateModules().length
        };
    }
};
