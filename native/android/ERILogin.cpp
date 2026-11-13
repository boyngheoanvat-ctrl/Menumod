// ERI Login Android native client, arm64-v8a / armeabi-v7a.
// Call from a Unity bootstrap scene before loading gameplay.
// JNI uses Android's built-in HTTPS implementation; no embedded Admin secret.
#include <jni.h>
#include <string>
#include <algorithm>
#include <cctype>

static JavaVM* g_vm = nullptr;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

static bool clear_exception(JNIEnv* e) {
    if (e->ExceptionCheck()) {
        e->ExceptionClear();
        return true;
    }
    return false;
}

static std::string json_escape(const char* ptr) {
    std::string output;
    const unsigned char* s = reinterpret_cast<const unsigned char*>(ptr ? ptr : "");
    for (; *s; ++s) {
        switch (*s) {
            case '"': output += "\\\""; break;
            case '\\': output += "\\\\"; break;
            case '\n': output += "\\n"; break;
            case '\r': output += "\\r"; break;
            case '\t': output += "\\t"; break;
            default:
                if (*s < 0x20) {
                    const char* hex = "0123456789abcdef";
                    output += "\\u00";
                    output.push_back(hex[(*s >> 4) & 15]);
                    output.push_back(hex[*s & 15]);
                } else output.push_back(static_cast<char>(*s));
        }
    }
    return output;
}

static bool valid_app(const char* app) {
    if (!app) return false;
    const size_t n = std::char_traits<char>::length(app);
    if (n < 2 || n > 128) return false;
    for (size_t i=0; i<n; ++i) {
        const unsigned char c = static_cast<unsigned char>(app[i]);
        if (!(std::isalnum(c) || c == '.' || c == '_' || c == '-')) return false;
    }
    return true;
}
static bool valid_device(const char* dev) {
    if (!dev || std::char_traits<char>::length(dev) != 36) return false;
    for (int i=0; i<36; ++i) {
        const char c = dev[i];
        if (i==8 || i==13 || i==18 || i==23) { if (c!='-') return false; }
        else if (!std::isxdigit(static_cast<unsigned char>(c))) return false;
    }
    return true;
}

// 1 = validated, 0 = rejected by server, -1 = request / response failure,
// -2 = Android JNI not loaded, -3 = invalid arguments.
// Returned by public API only: no Admin functionality is exposed to customers.
extern "C" __attribute__((visibility("default")))
int eri_login_check(const char* app, const char* key, const char* device, int activate) {
    if (!valid_app(app) || !valid_device(device) || !key ||
        std::char_traits<char>::length(key) < 15 ||
        std::char_traits<char>::length(key) > 128) return -3;
    if (!g_vm) return -2;
    JNIEnv* e = nullptr;
    bool attached = false;
    if (g_vm->GetEnv(reinterpret_cast<void**>(&e), JNI_VERSION_1_6) != JNI_OK) {
        if (g_vm->AttachCurrentThread(&e, nullptr) != JNI_OK) return -2;
        attached = true;
    }

    int result = -1;
    jobject connection = nullptr;
    jobject output = nullptr;
    jobject input = nullptr;
    jbyteArray bytes = nullptr;

    do {
        const char* uri = activate
            ? "https://eri-login-api.onrender.com/api/key/activate"
            : "https://eri-login-api.onrender.com/api/key/verify";
        jclass urlClass = e->FindClass("java/net/URL");
        if (!urlClass || clear_exception(e)) break;
        jmethodID urlCtor = e->GetMethodID(urlClass, "<init>", "(Ljava/lang/String;)V");
        jmethodID openConnection = e->GetMethodID(urlClass, "openConnection", "()Ljava/net/URLConnection;");
        if (!urlCtor || !openConnection || clear_exception(e)) break;
        jstring urlText = e->NewStringUTF(uri);
        jobject url = e->NewObject(urlClass, urlCtor, urlText);
        if (!url || clear_exception(e)) break;
        connection = e->CallObjectMethod(url, openConnection);
        if (!connection || clear_exception(e)) break;

        jclass connClass = e->FindClass("java/net/HttpURLConnection");
        if (!connClass || clear_exception(e)) break;
        jmethodID setMethod = e->GetMethodID(connClass, "setRequestMethod", "(Ljava/lang/String;)V");
        jmethodID setHeader = e->GetMethodID(connClass, "setRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V");
        jmethodID setDoOutput = e->GetMethodID(connClass, "setDoOutput", "(Z)V");
        jmethodID setConnectTimeout = e->GetMethodID(connClass, "setConnectTimeout", "(I)V");
        jmethodID setReadTimeout = e->GetMethodID(connClass, "setReadTimeout", "(I)V");
        jmethodID getOutput = e->GetMethodID(connClass, "getOutputStream", "()Ljava/io/OutputStream;");
        jmethodID getStatus = e->GetMethodID(connClass, "getResponseCode", "()I");
        jmethodID getInput = e->GetMethodID(connClass, "getInputStream", "()Ljava/io/InputStream;");
        if (!setMethod || !setHeader || !setDoOutput || !setConnectTimeout ||
            !setReadTimeout || !getOutput || !getStatus || !getInput || clear_exception(e)) break;

        e->CallVoidMethod(connection, setConnectTimeout, 15000);
        e->CallVoidMethod(connection, setReadTimeout, 30000);
        e->CallVoidMethod(connection, setDoOutput, JNI_TRUE);
        jstring post = e->NewStringUTF("POST");
        e->CallVoidMethod(connection, setMethod, post);
        jstring header = e->NewStringUTF("Content-Type");
        jstring value = e->NewStringUTF("application/json");
        e->CallVoidMethod(connection, setHeader, header, value);
        if (clear_exception(e)) break;

        std::string body = "{\"app_id\":\"" + json_escape(app) +
            "\",\"key\":\"" + json_escape(key) +
            "\",\"device_id\":\"" + json_escape(device) + "\"}";
        output = e->CallObjectMethod(connection, getOutput);
        if (!output || clear_exception(e)) break;
        jclass outClass = e->FindClass("java/io/OutputStream");
        jmethodID write = e->GetMethodID(outClass, "write", "([B)V");
        jmethodID closeOutput = e->GetMethodID(outClass, "close", "()V");
        if (!write || !closeOutput || clear_exception(e)) break;
        bytes = e->NewByteArray(static_cast<jsize>(body.size()));
        if (!bytes || clear_exception(e)) break;
        e->SetByteArrayRegion(bytes, 0, static_cast<jsize>(body.size()),
                              reinterpret_cast<const jbyte*>(body.data()));
        e->CallVoidMethod(output, write, bytes);
        e->CallVoidMethod(output, closeOutput);
        if (clear_exception(e)) break;

        const jint http = e->CallIntMethod(connection, getStatus);
        if (clear_exception(e)) break;
        if (http != 200) { result = 0; break; }

        input = e->CallObjectMethod(connection, getInput);
        if (!input || clear_exception(e)) break;
        jclass inClass = e->FindClass("java/io/InputStream");
        jmethodID read = e->GetMethodID(inClass, "read", "([B)I");
        jmethodID closeInput = e->GetMethodID(inClass, "close", "()V");
        if (!read || !closeInput || clear_exception(e)) break;
        jbyteArray buffer = e->NewByteArray(4096);
        if (!buffer || clear_exception(e)) break;
        std::string payload;
        while (payload.size() < 32768) {
            const jint n = e->CallIntMethod(input, read, buffer);
            if (clear_exception(e)) break;
            if (n <= 0) break;
            std::string tmp(static_cast<size_t>(n), '\0');
            e->GetByteArrayRegion(buffer, 0, n, reinterpret_cast<jbyte*>(&tmp[0]));
            payload += tmp;
        }
        e->CallVoidMethod(input, closeInput);
        if (clear_exception(e)) break;
        // Parse the server's JSON boolean rather than trusting HTTP status alone.
        jclass objectClass = e->FindClass("org/json/JSONObject");
        if (!objectClass || clear_exception(e)) break;
        jmethodID objCtor = e->GetMethodID(objectClass, "<init>", "(Ljava/lang/String;)V");
        jmethodID optBoolean = e->GetMethodID(objectClass, "optBoolean", "(Ljava/lang/String;Z)Z");
        if (!objCtor || !optBoolean || clear_exception(e)) break;
        jstring jsonText = e->NewStringUTF(payload.c_str());
        jobject jsonObj = e->NewObject(objectClass, objCtor, jsonText);
        if (!jsonObj || clear_exception(e)) break;
        jstring valid = e->NewStringUTF("valid");
        const jboolean accepted = e->CallBooleanMethod(jsonObj, optBoolean, valid, JNI_FALSE);
        if (clear_exception(e)) break;
        result = accepted ? 1 : 0;
    } while (false);

    if (connection) {
        jclass connClass = e->FindClass("java/net/HttpURLConnection");
        if (connClass && !clear_exception(e)) {
            jmethodID disconnect = e->GetMethodID(connClass, "disconnect", "()V");
            if (disconnect) e->CallVoidMethod(connection, disconnect);
            clear_exception(e);
        }
    }
    if (attached) g_vm->DetachCurrentThread();
    return result;
}
