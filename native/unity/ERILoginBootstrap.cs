using System;
using System.Runtime.InteropServices;
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
        if (key.Length < 15)
        {
            message = "Bạn chưa nhập key ERI hợp lệ.";
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

    private void OnGUI()
    {
        if (authenticated) return;
        int w = Mathf.Min(Screen.width - 24, 580);
        int h = 360;
        Rect area = new Rect((Screen.width - w) / 2f, (Screen.height - h) / 2f, w, h);
        GUILayout.BeginArea(area, GUI.skin.box);
        GUILayout.Space(12);
        GUILayout.Label("ERI LOGIN — 1 KEY / 1 THIẾT BỊ");
        GUILayout.Space(15);
        enteredKey = GUILayout.TextField(enteredKey, 64, GUILayout.Height(54));
        GUILayout.Space(10);
        GUI.enabled = !busy;
        if (GUILayout.Button("KÍCH HOẠT KEY", GUILayout.Height(56)))
            StartCheck(true);
        GUI.enabled = true;
        GUILayout.Space(18);
        GUILayout.Label(message);
        GUILayout.Space(12);
        GUILayout.Label("Ứng dụng chỉ mở scene game sau khi máy chủ xác minh key thành công.");
        GUILayout.EndArea();
    }
}
