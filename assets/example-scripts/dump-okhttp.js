// dump-okhttp.js - 抓取 OkHttp 请求/响应 (rustFrida QuickJS)
// 输出所有 OkHttp 网络请求的 URL、Header、Body

Java.ready(function() {
    console.log("[OkHttp] Starting OkHttp request interceptor...");

    try {
        var RealCall = Java.use("okhttp3.internal.connection.RealCall");
        var Buffer = Java.use("okio.Buffer");

        // hook execute（同步请求）
        RealCall.execute.impl = function() {
            var req = this.request();
            var url = req.url().toString();
            var method = req.method();
            var headers = req.headers().toString();

            console.log("\n[OkHttp] ======== REQUEST ========");
            console.log("[OkHttp] " + method + " " + url);
            console.log("[OkHttp] Headers:\n" + headers);

            // 打印 request body
            var body = req.body();
            if (body !== null) {
                try {
                    var buf = Buffer.$new();
                    body.writeTo(buf);
                    console.log("[OkHttp] Body: " + buf.readUtf8());
                } catch (e) {
                    console.log("[OkHttp] Body: (unreadable)");
                }
            }

            // 执行原始请求
            var resp = this.$orig();

            console.log("[OkHttp] ======== RESPONSE ========");
            console.log("[OkHttp] Status: " + resp.code() + " " + resp.message());
            console.log("[OkHttp] Headers:\n" + resp.headers().toString());

            return resp;
        };

        console.log("[OkHttp] RealCall.execute hooked");

    } catch (e) {
        console.log("[OkHttp] RealCall not found: " + e);
    }

    // hook enqueue（异步请求）
    try {
        var RealCall2 = Java.use("okhttp3.internal.connection.RealCall");
        RealCall2.enqueue.impl = function(callback) {
            var req = this.request();
            console.log("[OkHttp-Async] " + req.method() + " " + req.url().toString());
            return this.$orig(callback);
        };
        console.log("[OkHttp] RealCall.enqueue hooked");
    } catch (e) {
        console.log("[OkHttp] Async hook skipped");
    }

    console.log("[OkHttp] Interceptor ready.");
});

rpc.exports = {
    status: function() { return "okhttp-dump active"; }
};
