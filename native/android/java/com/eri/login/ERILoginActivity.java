package com.eri.login;

import android.app.Activity;
import android.os.Bundle;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Locale;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * ERI LOGIN • MOD BY ERI NGUYỄN
 *
 * Standalone Android Activity for applications the owner may modify.
 * Requires libERILogin.so with matching JNI export and Manifest configuration.
 * Does NOT bypass game signature, anti-tamper or integrity checks.
 */
public final class ERILoginActivity extends Activity {
    private static final String PREFS = "eri.login.device.v1";
    private static final String KEY_PREF = "key";
    private static final String DEVICE_PREF = "device-id";
    private static final String NEXT_ACTIVITY = "eri.login.next_activity";
    private static final Pattern KEY_PATTERN = Pattern.compile(
        "^ERI-[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){5}$");

    // Compatibility with a menu-style Smali call:
    // invoke-static {p0}, Lcom/eri/login/ERILoginActivity;->Start(Landroid/content/Context;)V
    // When the Login finishes, we start the original Activity once without
    // relaunching the Login. This guard is process-local, not license state.
    private static boolean returningFromVerifiedLogin = false;

    public static void Start(Context context) {
        StartAndGate(context);
    }

    /**
     * Smali gate: returns true when the caller MUST return from onCreate
     * without constructing Unity or showing a mod menu.
     *
     * Returns false exactly once when a validated Login has reopened the game
     * Activity in the same app process. This is an app-start gate only.
     */
    public static boolean StartAndGate(Context context) {
        if (context == null || context instanceof ERILoginActivity) return true;
        synchronized (ERILoginActivity.class) {
            if (returningFromVerifiedLogin) {
                returningFromVerifiedLogin = false;
                return false;
            }
        }
        try {
            Intent login = new Intent(context, ERILoginActivity.class);
            if (!(context instanceof Activity)) {
                login.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            }
            context.startActivity(login);
        } catch (RuntimeException error) {
            // Fail closed: callers must not start Unity when Login did not open.
            android.util.Log.e("ERILogin", "Cannot open Login Activity", error);
        }
        if (context instanceof Activity) {
            ((Activity) context).finish();
        }
        return true;
    }

    // The matching JNI function is exported by libERILogin.so.
    private static native int nativeCheck(String appId, String key,
                                           String deviceId, int activate);

    private EditText keyField;
    private Button actionButton;
    private TextView statusView;
    private volatile boolean running = false;
    private boolean libReady = false;

    private static int color(String value) { return Color.parseColor(value); }
    private GradientDrawable shape(int base, float corner) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(base);
        g.setCornerRadius(dp(corner));
        return g;
    }
    private GradientDrawable gradient() {
        GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                new int[] {color("#178CFF"), color("#6558E8")});
        g.setCornerRadius(dp(14));
        return g;
    }
    private int dp(float value) {
        return (int) (getResources().getDisplayMetrics().density * value + 0.5f);
    }
    private TextView line(String message, int sp, int tint, boolean bold) {
        TextView v = new TextView(this);
        v.setText(message);
        v.setTextColor(tint);
        v.setTextSize(sp);
        v.setGravity(Gravity.CENTER);
        if (bold) v.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return v;
    }
    private void gap(LinearLayout root, int dp) {
        View space = new View(this);
        root.addView(space, new LinearLayout.LayoutParams(1, dp(dp)));
    }
    private String normalizedKey() {
        return keyField.getText().toString().trim().toUpperCase(Locale.ROOT);
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(color("#071025"));
        getWindow().setNavigationBarColor(color("#071025"));

        ScrollView scroller = new ScrollView(this);
        scroller.setFillViewport(true);
        scroller.setBackgroundColor(color("#071025"));
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(24), dp(42), dp(24), dp(32));
        scroller.addView(root);
        setContentView(scroller);

        TextView brand = line("✦  MOD BY ERI NGUYỄN  ✦", 13, color("#82DBFF"), true);
        brand.setBackground(shape(color("#17365D"), 15));
        brand.setPadding(dp(6), dp(12), dp(6), dp(12));
        root.addView(brand, new LinearLayout.LayoutParams(-1, -2));
        gap(root, 55);
        root.addView(line("◆", 65, color("#67D7FE"), true));
        gap(root, 13);
        root.addView(line("ERI LOGIN", 36, Color.WHITE, true));
        gap(root, 8);
        root.addView(line("KÍCH HOẠT QUYỀN TRUY CẬP", 13,
                color("#B5C6E0"), false));
        gap(root, 16);
        root.addView(line("01 KEY  •  01 THIẾT BỊ", 13,
                color("#72E0EF"), true));
        gap(root, 40);

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(22), dp(16), dp(18));
        panel.setBackground(shape(color("#14233E"), 19));
        root.addView(panel, new LinearLayout.LayoutParams(-1, -2));

        TextView title = line("MÃ KÍCH HOẠT CỦA BẠN", 13,
                color("#D5E2FF"), true);
        title.setGravity(Gravity.LEFT);
        panel.addView(title);
        gap(panel, 12);

        keyField = new EditText(this);
        keyField.setSingleLine(true);
        keyField.setTextSize(14);
        keyField.setTextColor(Color.WHITE);
        keyField.setHintTextColor(color("#7E92B1"));
        keyField.setHint("ERI-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX");
        keyField.setInputType(InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        keyField.setPadding(dp(12), dp(12), dp(8), dp(12));
        keyField.setBackground(shape(color("#0B152B"), 12));
        panel.addView(keyField, new LinearLayout.LayoutParams(-1, dp(56)));
        keyField.setText(prefs().getString(KEY_PREF, ""));
        gap(panel, 12);

        Button paste = new Button(this);
        paste.setAllCaps(false);
        paste.setText("DÁN KEY");
        paste.setTextColor(color("#89DCFF"));
        paste.setBackground(shape(color("#132D4D"), 10));
        panel.addView(paste, new LinearLayout.LayoutParams(-1, dp(43)));
        paste.setOnClickListener(v -> {
            ClipboardManager clipboard = (ClipboardManager)
                    getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null && clipboard.hasPrimaryClip()) {
                ClipData data = clipboard.getPrimaryClip();
                if (data != null && data.getItemCount() > 0) {
                    CharSequence text = data.getItemAt(0).coerceToText(this);
                    keyField.setText(text);
                    status("Đã dán key. Bấm KÍCH HOẠT KEY.", false);
                }
            }
        });
        gap(panel, 13);

        actionButton = new Button(this);
        actionButton.setText("KÍCH HOẠT KEY  ›");
        actionButton.setTextColor(Color.WHITE);
        actionButton.setAllCaps(false);
        actionButton.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        actionButton.setTextSize(16);
        actionButton.setBackground(gradient());
        panel.addView(actionButton, new LinearLayout.LayoutParams(-1, dp(55)));
        actionButton.setOnClickListener(v -> check(true));
        gap(panel, 13);

        statusView = line("Nhập key do ERI ADMIN cấp.", 12,
                color("#AFC5E1"), false);
        panel.addView(statusView);
        gap(panel, 13);

        TextView packageId = line("ANDROID APP ID: " + getPackageName(), 11,
                color("#8CA8C9"), false);
        panel.addView(packageId);
        packageId.setOnClickListener(v -> {
            ClipboardManager clipboard = (ClipboardManager)
                    getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null) {
                clipboard.setPrimaryClip(ClipData.newPlainText("ERI Android App ID",
                        getPackageName()));
                status("Đã sao chép Package ID.", false);
            }
        });

        gap(root, 35);
        root.addView(line("XÁC MINH ONLINE  •  MOD BY ERI NGUYỄN", 11,
                color("#7B93B4"), false));

        try {
            System.loadLibrary("ERILogin");
            libReady = true;
        } catch (Throwable failure) {
            libReady = false;
            status("Không nạp được libERILogin.so: "
                    + failure.getClass().getSimpleName(), true);
        }
        if (libReady && KEY_PATTERN.matcher(normalizedKey()).matches()) {
            check(false);
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
    private String deviceId() {
        String id = prefs().getString(DEVICE_PREF, "");
        try {
            UUID.fromString(id);
            return id;
        } catch (Exception ignored) {
            id = UUID.randomUUID().toString();
            prefs().edit().putString(DEVICE_PREF, id).apply();
            return id;
        }
    }
    private void status(String message, boolean error) {
        statusView.setText(message);
        statusView.setTextColor(color(error ? "#FFAAA8" : "#81DEEF"));
    }
    private void check(boolean activate) {
        if (running) return;
        if (!libReady) {
            status("Thư viện Android chưa sẵn sàng. Kiểm tra kiến trúc APK.", true);
            return;
        }
        final String key = normalizedKey();
        if (!KEY_PATTERN.matcher(key).matches()) {
            status("Sai định dạng key. Không nhập tên tài khoản.", true);
            return;
        }
        final String appId = getPackageName();
        final String id = deviceId();
        running = true;
        actionButton.setEnabled(false);
        status("Đang xác minh key và thiết bị qua HTTPS...", false);
        new Thread(() -> {
            int result;
            try { result = nativeCheck(appId, key, id, activate ? 1 : 0); }
            catch (Throwable e) { result = -2; }
            final int code = result;
            runOnUiThread(() -> {
                running = false;
                if (isFinishing() || isDestroyed()) return;
                actionButton.setEnabled(true);
                if (code == 1) {
                    prefs().edit().putString(KEY_PREF, key).apply();
                    openGame();
                } else if (code == 0) {
                    status("Key bị từ chối. Kiểm tra hạn dùng, trạng thái và Package ID.", true);
                } else if (code == -3) {
                    status("App ID, key hoặc mã thiết bị không hợp lệ.", true);
                } else {
                    status("Không thể xác minh. Kiểm tra Internet và logcat.", true);
                }
            });
        }, "eri-license-check").start();
    }
    private void openGame() {
        try {
            ApplicationInfo info = getPackageManager().getApplicationInfo(
                    getPackageName(), PackageManager.GET_META_DATA);
            Bundle meta = info.metaData;
            String target = meta == null ? null : meta.getString(NEXT_ACTIVITY);
            if (target == null || target.isEmpty()) {
                status("Thiếu meta-data eri.login.next_activity trong Manifest.", true);
                return;
            }
            Class<?> clazz = Class.forName(target);
            if (!Activity.class.isAssignableFrom(clazz)) {
                status("Activity đích không hợp lệ: " + target, true);
                return;
            }
            Intent intent = new Intent(this, clazz);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
            // Avoid a Start(Context) -> Login -> game -> Start(Context) loop.
            // This is only set after the backend has validated the key.
            synchronized (ERILoginActivity.class) {
                returningFromVerifiedLogin = true;
            }
            try {
                startActivity(intent);
            } catch (RuntimeException error) {
                synchronized (ERILoginActivity.class) {
                    returningFromVerifiedLogin = false;
                }
                throw error;
            }
            finish();
        } catch (Exception ex) {
            status("Không mở được Activity gốc: " + ex.getClass().getSimpleName(), true);
        }
    }
}
