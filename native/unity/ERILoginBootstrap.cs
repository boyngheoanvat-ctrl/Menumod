using System;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.SceneManagement;

// Add ONLY to a project you own / are authorized to modify.
// Put this behaviour into a bootstrap scene that contains NO gameplay.
// Set the nextScene field to the actual gameplay scene added to Build Settings.
// Requires Assets/Plugins/Android/arm64-v8a/libERILogin.so.
public sealed class ERILoginBootstrap : MonoBehaviour
{
    [SerializeField] private string nextScene = "Game";
    private const string KeyPref = "ERI_LOGIN_KEY";
    private const string DevicePref = "ERI_LOGIN_DEVICE_UUID";
    private string enteredKey = "";
    private string deviceId = "";
    private string message = "Nhập key đã được ERI ADMIN cấp.";
    private bool busy;
    private bool authenticated;
    private Task<int> running;
    private string checkedKey;
    private GUIStyle titleStyle, brandStyle, subtitleStyle, hintStyle, keyStyle, actionStyle;
    private Texture2D backgroundTexture, panelTexture, fieldTexture, buttonTexture, badgeTexture;

#if UNITY_ANDROID && !UNITY_EDITOR
    [DllImport("ERILogin", CallingConvention = CallingConvention.Cdecl)]
    private static extern int eri_login_check(string appId, string key, string deviceId, int activate);
#endif

    private void Awake()
    {
        DontDestroyOnLoad(gameObject);
        Time.timeScale = 0f;
        deviceId = PlayerPrefs.GetString(DevicePref, "");
        if (!Guid.TryParse(deviceId, out _))
        {
            deviceId = Guid.NewGuid().ToString("D").ToLowerInvariant();
            PlayerPrefs.SetString(DevicePref, deviceId);
            PlayerPrefs.Save();
        }
        enteredKey = PlayerPrefs.GetString(KeyPref, "");
#if UNITY_ANDROID && !UNITY_EDITOR
        try
        {
            // Ensures Android runtime calls JNI_OnLoad so the .so can use HTTPS via JNI.
            using (var sys = new AndroidJavaClass("java.lang.System"))
                sys.CallStatic("loadLibrary", "ERILogin");
        }
        catch (Exception)
        {
            message = "Không nạp được libERILogin.so. Kiểm tra thư mục Plugins/Android.";
        }
#else
        message = "Hãy build dự án Unity cho Android để dùng libERILogin.so.";
#endif
    }

    private void Start()
    {
        if (!string.IsNullOrWhiteSpace(enteredKey))
            StartCheck(false);
    }

    private void StartCheck(bool activate)
    {
        if (busy || authenticated) return;
        string key = enteredKey.Trim().ToUpperInvariant();
        if (!Regex.IsMatch(key, @"^ERI-[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){5}$"))
        {
            message = "Sai định dạng. Nhập key ERI-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX, không nhập tên tài khoản.";
            return;
        }

#if UNITY_ANDROID && !UNITY_EDITOR
        busy = true;
        checkedKey = key;
        message = "Đang xác minh key và thiết bị qua HTTPS...";
        string appId = Application.identifier;
        string id = deviceId;
        running = Task.Run(() =>
        {
            try { return eri_login_check(appId, key, id, activate ? 1 : 0); }
            catch (Exception) { return -2; }
        });
#else
        message = "Bản này chỉ dùng khi build Android.";
#endif
    }

    private void Update()
    {
        if (!busy || running == null || !running.IsCompleted) return;
        busy = false;
        int result;
        try { result = running.Result; }
        catch { result = -1; }
        running = null;
        if (result == 1)
        {
            authenticated = true;
            PlayerPrefs.SetString(KeyPref, checkedKey);
            PlayerPrefs.Save();
            Time.timeScale = 1f;
            if (string.IsNullOrWhiteSpace(nextScene))
            {
                message = "Đã xác thực nhưng chưa cấu hình scene game.";
                return;
            }
            SceneManager.LoadScene(nextScene, LoadSceneMode.Single);
            Destroy(gameObject);
            return;
        }
        message = result == 0
            ? "Key không hợp lệ, đã hết hạn, bị khóa hoặc gắn máy khác."
            : result == -3
                ? "Bundle ID, key hoặc mã thiết bị không hợp lệ."
                : "Không thể xác minh với máy chủ. Kiểm tra Internet và thư viện native.";
    }

    private static Texture2D MakePixel(Color color)
    {
        var texture = new Texture2D(1, 1, TextureFormat.RGBA32, false);
        texture.SetPixel(0, 0, color);
        texture.Apply();
        texture.wrapMode = TextureWrapMode.Clamp;
        return texture;
    }

    private void CreateTheme()
    {
        if (titleStyle != null) return;
        backgroundTexture = MakePixel(new Color(0.03f, 0.05f, 0.12f));
        panelTexture = MakePixel(new Color(0.07f, 0.13f, 0.24f));
        fieldTexture = MakePixel(new Color(0.04f, 0.08f, 0.17f));
        buttonTexture = MakePixel(new Color(0.14f, 0.45f, 0.98f));
        badgeTexture = MakePixel(new Color(0.08f, 0.22f, 0.40f));

        titleStyle = new GUIStyle(GUI.skin.label);
        titleStyle.alignment = TextAnchor.MiddleCenter;
        titleStyle.fontSize = 38;
        titleStyle.fontStyle = FontStyle.Bold;
        titleStyle.normal.textColor = Color.white;

        brandStyle = new GUIStyle(titleStyle);
        brandStyle.fontSize = 16;
        brandStyle.normal.textColor = new Color(0.48f, 0.90f, 1f);

        subtitleStyle = new GUIStyle(titleStyle);
        subtitleStyle.fontSize = 15;
        subtitleStyle.normal.textColor = new Color(0.68f, 0.80f, 0.96f);

        hintStyle = new GUIStyle(subtitleStyle);
        hintStyle.fontSize = 14;
        hintStyle.wordWrap = true;
        hintStyle.normal.textColor = new Color(0.72f, 0.82f, 0.91f);

        keyStyle = new GUIStyle(GUI.skin.textField);
        keyStyle.fontSize = 17;
        keyStyle.alignment = TextAnchor.MiddleCenter;
        keyStyle.normal.textColor = Color.white;
        keyStyle.focused.textColor = Color.white;
        keyStyle.normal.background = fieldTexture;
        keyStyle.focused.background = fieldTexture;

        actionStyle = new GUIStyle(GUI.skin.button);
        actionStyle.fontSize = 18;
        actionStyle.fontStyle = FontStyle.Bold;
        actionStyle.alignment = TextAnchor.MiddleCenter;
        actionStyle.normal.textColor = Color.white;
        actionStyle.hover.textColor = Color.white;
        actionStyle.active.textColor = Color.white;
        actionStyle.normal.background = buttonTexture;
        actionStyle.hover.background = buttonTexture;
        actionStyle.active.background = buttonTexture;
    }

    private void OnGUI()
    {
        if (authenticated) return;
        CreateTheme();

        // Uniform canvas scale keeps the screen readable on Android phone sizes.
        const float width = 420f, height = 760f;
        float scale = Mathf.Min(Screen.width / width, Screen.height / height);
        Matrix4x4 saved = GUI.matrix;
        GUI.matrix = Matrix4x4.TRS(new Vector3(
            (Screen.width - width * scale) * 0.5f,
            (Screen.height - height * scale) * 0.5f, 0f),
            Quaternion.identity, new Vector3(scale, scale, 1f));

        GUI.DrawTexture(new Rect(0f, 0f, width, height), backgroundTexture);
        GUI.DrawTexture(new Rect(30f, 80f, 360f, 48f), badgeTexture);
        GUI.Label(new Rect(35f, 84f, 350f, 42f), "✦ MOD BY ERI NGUYỄN ✦", brandStyle);

        GUI.Label(new Rect(30f, 170f, 360f, 60f), "ERI LOGIN", titleStyle);
        GUI.Label(new Rect(30f, 225f, 360f, 34f), "KÍCH HOẠT QUYỀN TRUY CẬP", subtitleStyle);
        GUI.Label(new Rect(30f, 265f, 360f, 34f), "01 KEY  •  01 THIẾT BỊ", brandStyle);

        GUI.DrawTexture(new Rect(30f, 338f, 360f, 285f), panelTexture);
        GUI.Label(new Rect(50f, 358f, 320f, 32f), "MÃ KÍCH HOẠT CỦA BẠN", subtitleStyle);
        enteredKey = GUI.TextField(new Rect(49f, 404f, 322f, 54f), enteredKey, 64, keyStyle);
        if (!busy && GUI.Button(new Rect(49f, 475f, 322f, 60f), "KÍCH HOẠT KEY  ›", actionStyle))
        {
            StartCheck(true);
        }
        string status = busy ? "Đang xác minh key và thiết bị qua HTTPS..." : message;
        GUI.Label(new Rect(49f, 549f, 322f, 59f), status, hintStyle);
        GUI.Label(new Rect(35f, 654f, 350f, 65f),
                  "XÁC MINH ONLINE • LIÊN KẾT THIẾT BỊ\nMOD BY ERI NGUYỄN",
                  hintStyle);
        GUI.matrix = saved;
    }

    private void OnDestroy()
    {
        if (backgroundTexture != null) Destroy(backgroundTexture);
        if (panelTexture != null) Destroy(panelTexture);
        if (fieldTexture != null) Destroy(fieldTexture);
        if (buttonTexture != null) Destroy(buttonTexture);
        if (badgeTexture != null) Destroy(badgeTexture);
    }
}
