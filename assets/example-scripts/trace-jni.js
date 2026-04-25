// trace-jni.js - JNI 调用追踪 (rustFrida QuickJS)
// 追踪 RegisterNatives 和 native 方法调用

Java.ready(function() {
    console.log("[JNI] Starting JNI tracer...");

    // 追踪 RegisterNatives（App 注册 native 方法时触发）
    var registerNatives = Jni.addr("RegisterNatives");
    if (registerNatives) {
        Interceptor.attach(registerNatives, {
            onEnter: function(args) {
                var env = args[0];
                var clazz = args[1];
                var methods = args[2];
                var count = args[3].toInt32();

                console.log("\n[JNI] RegisterNatives called, count=" + count);

                // 读取每个注册的方法
                for (var i = 0; i < count; i++) {
                    var entry = Jni.readNativeMethodAt(methods, i);
                    if (entry) {
                        console.log("[JNI]   " + (entry.name || "?") +
                                    " sig=" + (entry.sig || "?") +
                                    " fn=" + entry.fnPtr);
                    }
                }
            }
        });
        console.log("[JNI] RegisterNatives hooked at " + registerNatives);
    }

    // 追踪 FindClass
    var findClass = Jni.addr("FindClass");
    if (findClass) {
        Interceptor.attach(findClass, {
            onEnter: function(args) {
                this.name = args[1].readCString();
            },
            onLeave: function(retval) {
                if (this.name) {
                    console.log("[JNI] FindClass: " + this.name + " → " + retval);
                }
            }
        });
        console.log("[JNI] FindClass hooked");
    }

    // 追踪 GetMethodID / GetStaticMethodID
    var getMethodID = Jni.addr("GetMethodID");
    if (getMethodID) {
        Interceptor.attach(getMethodID, {
            onEnter: function(args) {
                this.name = args[2].readCString();
                this.sig = args[3].readCString();
            },
            onLeave: function(retval) {
                console.log("[JNI] GetMethodID: " + this.name + this.sig + " → " + retval);
            }
        });
    }

    console.log("[JNI] Tracer ready.");
});

rpc.exports = {
    status: function() { return "jni-trace active"; }
};
