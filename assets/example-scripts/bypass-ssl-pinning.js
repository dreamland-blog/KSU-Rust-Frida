// bypass-ssl-pinning.js - SSL Pinning 绕过 (rustFrida QuickJS)
// 支持 OkHttp3 / HttpsURLConnection / TrustManager

Java.ready(function() {
    console.log("[SSL-Bypass] Starting SSL pinning bypass...");

    // 1. OkHttp3 CertificatePinner
    try {
        var CertPinner = Java.use("okhttp3.CertificatePinner");
        CertPinner.check.overload("java.lang.String", "java.util.List").impl = function(hostname, peerCerts) {
            console.log("[SSL-Bypass] OkHttp3 CertificatePinner.check bypassed for: " + hostname);
            // 不调 $orig，直接放行
        };
        console.log("[SSL-Bypass] OkHttp3 CertificatePinner hooked");
    } catch (e) {
        console.log("[SSL-Bypass] OkHttp3 not found, skipping");
    }

    // 2. TrustManagerFactory → 替换为空 TrustManager
    try {
        var X509TM = Java.use("javax.net.ssl.X509TrustManager");
        var SSLContext = Java.use("javax.net.ssl.SSLContext");

        var TrustManager = Java.use("java.security.cert.X509Certificate");

        var EmptyTrustManager = Java.use("javax.net.ssl.X509TrustManager");
        EmptyTrustManager.checkClientTrusted.impl = function(chain, authType) {
            console.log("[SSL-Bypass] checkClientTrusted bypassed");
        };
        EmptyTrustManager.checkServerTrusted.impl = function(chain, authType) {
            console.log("[SSL-Bypass] checkServerTrusted bypassed");
        };
        console.log("[SSL-Bypass] X509TrustManager hooked");
    } catch (e) {
        console.log("[SSL-Bypass] TrustManager hook failed: " + e);
    }

    // 3. OkHttp3 HostnameVerifier
    try {
        var OkHostVerifier = Java.use("okhttp3.internal.tls.OkHostnameVerifier");
        OkHostVerifier.verify.overload("java.lang.String", "javax.net.ssl.SSLSession").impl = function(hostname, session) {
            console.log("[SSL-Bypass] HostnameVerifier bypassed for: " + hostname);
            return true;
        };
        console.log("[SSL-Bypass] OkHostnameVerifier hooked");
    } catch (e) {
        console.log("[SSL-Bypass] OkHostnameVerifier not found, skipping");
    }

    console.log("[SSL-Bypass] Done. All available SSL pinning methods bypassed.");
});

rpc.exports = {
    status: function() { return "ssl-bypass active"; }
};
