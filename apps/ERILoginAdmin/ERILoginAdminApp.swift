import SwiftUI
import Security

// Native iOS administrator: one license key per device, for IPA and APK.
private struct License: Codable, Identifiable {
    let id: String
    let key_value: String
    let platform: String
    let device_id: String?
    let locked: Int
    let expires_at: Int
    let created_at: Int
    let updated_at: Int
    var expiryText: String {
        Date(timeIntervalSince1970: TimeInterval(expires_at))
            .formatted(date: .abbreviated, time: .shortened)
    }
}
private struct LicenseList: Decodable {
    let ok: Bool
    let items: [License]
}
private struct LicenseCreated: Decodable {
    let ok: Bool
    let item: License
}
private struct SimpleResult: Decodable { let ok: Bool }

private enum AdminError: LocalizedError {
    case setup, invalidURL, server(String)
    var errorDescription: String? {
        switch self {
        case .setup: return "Nhập URL API HTTPS và ERI_ADMIN_KEY trước."
        case .invalidURL: return "URL API phải bắt đầu bằng https://."
        case .server(let message): return message
        }
    }
}
private enum SecureStore {
    static let service = "vn.eringuyen.eriloginadmin"
    static let account = "ERI_ADMIN_KEY"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

private struct APIClient {
    let endpoint: String
    let adminKey: String

    private func call<T: Decodable>(_ path: String, method: String = "GET",
                                     jsonBody: [String: Any]? = nil) async throws -> T {
        let host = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty && !adminKey.isEmpty else { throw AdminError.setup }
        guard host.hasPrefix("https://"), let url = URL(string: host + path) else {
            throw AdminError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(adminKey, forHTTPHeaderField: "X-ERI-ADMIN-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        if let body = jsonBody {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AdminError.server("Không nhận được phản hồi HTTP.")
        }
        if !(200...299).contains(http.statusCode) {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = payload?["error"] as? String ?? "HTTP \(http.statusCode)"
            throw AdminError.server("API: \(code)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func health() async throws {
        let _: SimpleResult = try await call("/api/health")
    }
    func list() async throws -> [License] {
        let response: LicenseList = try await call("/api/admin/keys")
        return response.items
    }
    func create(platform: String, days: Int) async throws -> License {
        let response: LicenseCreated = try await call(
            "/api/admin/keys", method: "POST",
            jsonBody: ["platform": platform, "days": days])
        return response.item
    }
    func extend(_ id: String, days: Int) async throws {
        let _: SimpleResult = try await call(
            "/api/admin/keys/\(id)/extend", method: "POST", jsonBody: ["days": days])
    }
    func lock(_ id: String, locked: Bool) async throws {
        let _: SimpleResult = try await call(
            "/api/admin/keys/\(id)/lock", method: "POST", jsonBody: ["locked": locked])
    }
    func unbind(_ id: String) async throws {
        let _: SimpleResult = try await call(
            "/api/admin/keys/\(id)/unbind", method: "POST", jsonBody: [:])
    }
    func delete(_ id: String) async throws {
        let _: SimpleResult = try await call("/api/admin/keys/\(id)", method: "DELETE")
    }
}

@MainActor
private final class AdminModel: ObservableObject {
    @Published var items: [License] = []
    @Published var isBusy = false
    @Published var message = ""
    @Published var showMessage = false
    func notify(_ value: String) {
        message = value
        showMessage = true
    }
    func run(_ work: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await work() } catch { notify(error.localizedDescription) }
    }
}

struct ERILoginAdminView: View {
    @AppStorage("eri_api_url") private var apiURL = ""
    @State private var adminKey = SecureStore.load()
    @State private var selectedPlatform = "ios"
    @State private var days = 30
    @StateObject private var model = AdminModel()

    private var client: APIClient {
        APIClient(endpoint: apiURL, adminKey: adminKey)
    }
    private func reload() async throws {
        model.items = try await client.list()
    }
    private func refresh() async {
        await model.run { try await reload() }
    }
    private func action(_ operation: @escaping () async throws -> Void) {
        Task { await model.run {
            try await operation()
            try await reload()
        }}
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kết nối máy chủ") {
                    TextField("https://api.example.workers.dev", text: $apiURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("ERI_ADMIN_KEY", text: $adminKey)
                        .textInputAutocapitalization(.never)
                    Button("Lưu cấu hình") {
                        SecureStore.save(adminKey)
                        model.notify("Đã lưu API và Admin Key vào thiết bị.")
                    }
                    Button("Kiểm tra API") {
                        action {
                            try await client.health()
                            model.notify("API hoạt động.")
                        }
                    }
                }
                Section("Tạo key thiết bị") {
                    Picker("Nền tảng", selection: $selectedPlatform) {
                        Text("iOS / IPA").tag("ios")
                        Text("Android / APK").tag("android")
                    }
                    .pickerStyle(.segmented)
                    Stepper("Thời hạn: \(days) ngày", value: $days, in: 1...3650)
                    Button("Tạo key mới") {
                        let platform = selectedPlatform
                        let validDays = days
                        action {
                            let row = try await client.create(platform: platform, days: validDays)
                            model.notify("Đã tạo: \(row.key_value)")
                        }
                    }
                    .disabled(model.isBusy)
                }
                Section("Danh sách key (\(model.items.count))") {
                    if model.items.isEmpty {
                        Text("Chưa có key hoặc chưa kết nối API.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: item.platform == "ios" ? "iphone" : "apps.iphone")
                                Text(item.platform.uppercased()).bold()
                                Spacer()
                                Text(item.locked == 1 ? "Đã khóa" : "Hoạt động")
                                    .foregroundStyle(item.locked == 1 ? .red : .green)
                            }
                            Text(item.key_value)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Hết hạn: \(item.expiryText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.device_id == nil ? "Chưa gắn thiết bị" : "Đã gắn thiết bị")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("+7 ngày") {
                                    action { try await client.extend(item.id, days: 7) }
                                }
                                .buttonStyle(.bordered)
                                Button(item.locked == 1 ? "Mở khóa" : "Khóa") {
                                    action { try await client.lock(item.id, locked: item.locked == 0) }
                                }
                                .buttonStyle(.bordered)
                                if item.device_id != nil {
                                    Button("Gỡ máy") {
                                        action { try await client.unbind(item.id) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            Button("Xóa key", role: .destructive) {
                                action { try await client.delete(item.id) }
                            }
                            .font(.footnote)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("ERI Login Admin")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)
                }
            }
            .refreshable { await refresh() }
            .overlay {
                if model.isBusy {
                    ProgressView().controlSize(.large)
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("ERI Login Admin", isPresented: $model.showMessage) {
                Button("OK") {}
            } message: {
                Text(model.message)
            }
            .task {
                if !apiURL.isEmpty && !adminKey.isEmpty {
                    await refresh()
                }
            }
        }
    }
}

@main
struct ERILoginAdminApp: App {
    var body: some Scene {
        WindowGroup { ERILoginAdminView() }
    }
}