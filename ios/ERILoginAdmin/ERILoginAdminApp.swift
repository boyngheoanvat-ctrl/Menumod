import SwiftUI
import Foundation
import Security
import UIKit

// ERI ADMIN for Menumod — native iPhone app.
// Admin secret is entered on-device, never embedded into the distributable IPA.
private enum ERIVault {
    static let service = "vn.eri.menumod.admin"
    static let name = "eri-admin-key"

    static func read() -> String {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name
        ]
        if value.isEmpty { _ = SecItemDelete(q as CFDictionary); return }
        let data = Data(value.utf8)
        let updated = SecItemUpdate(q as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
            var created = q
            created[kSecValueData as String] = data
            created[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            _ = SecItemAdd(created as CFDictionary, nil)
        }
    }
}

private struct APIError: Decodable { let error: String? }
private struct KeyList: Decodable { let keys: [LicenseKey] }
private struct UserList: Decodable { let users: [LicenseUser] }
private struct IssuedKey: Decodable { let key: String }
private struct LicenseKey: Decodable, Identifiable {
    let id: String
    let label: String
    let key_suffix: String
    let expires_at: String
    let disabled: Bool
    let device_bound: Bool
    let expired: Bool
}
private struct LicenseUser: Decodable, Identifiable {
    var id: String { username }
    let username: String
    let expires_at: String
    let disabled: Bool
    let expired: Bool
}

@MainActor private final class ERIAdmin: ObservableObject {
    @Published var secret = ERIVault.read()
    @Published var isSecretSaved = !ERIVault.read().isEmpty
    @Published var users: [LicenseUser] = []
    @Published var keys: [LicenseKey] = []
    @Published var issuedKey = ""
    @Published var message = "Nhập khóa quản trị, chọn mục và tạo tài khoản hoặc key."
    @Published var busy = false
    private let origin = "https://eri-login-api.onrender.com"

    func forgetSecret() {
        ERIVault.save("")
        secret = ""
        isSecretSaved = false
        message = "Đã xóa khóa Admin trên thiết bị. Nhập khóa mới để tiếp tục."
    }

    private func request(_ route: String, body: [String: Any]? = nil) async throws -> Data {
        let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 32 else {
            throw NSError(domain: "ERI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cần nhập ERI_ADMIN_KEY hợp lệ."])
        }
        guard let url = URL(string: origin + route) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 95
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-ERI-ADMIN-KEY")
        if let body = body {
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if !(200...299).contains(http.statusCode) {
            let cause = (try? JSONDecoder().decode(APIError.self, from: data).error)
                        ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "ERI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: cause])
        }
        // Save ONLY after the server accepts this Admin key, never before validation.
        if ERIVault.read() != token {
            ERIVault.save(token)
        }
        isSecretSaved = (ERIVault.read() == token)
        return data
    }

    private func validate(_ app: String, days: Int? = nil) throws {
        guard app.range(of: "^[A-Za-z0-9_.-]{2,128}$", options: .regularExpression) != nil else {
            throw NSError(domain: "ERI", code: 2, userInfo: [NSLocalizedDescriptionKey: "App ID không hợp lệ."])
        }
        if let days = days, !(1...3650).contains(days) {
            throw NSError(domain: "ERI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Số ngày phải từ 1 đến 3650."])
        }
    }

    private func query(_ path: String, app: String) -> String {
        var c = URLComponents()
        c.queryItems = [URLQueryItem(name: "app_id", value: app)]
        return path + "?" + (c.percentEncodedQuery ?? "")
    }

    private func listUsers(_ app: String) async throws {
        let data = try await request(query("/api/admin/list", app: app))
        users = try JSONDecoder().decode(UserList.self, from: data).users
    }
    private func listKeys(_ app: String) async throws {
        let data = try await request(query("/api/admin/key/list", app: app))
        keys = try JSONDecoder().decode(KeyList.self, from: data).keys
    }

    func refreshUsers(app: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try validate(app); try await listUsers(app); message = "Đã tải \(users.count) tài khoản." }
        catch { message = error.localizedDescription }
    }
    func refreshKeys(app: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try validate(app); try await listKeys(app); message = "Đã tải \(keys.count) key." }
        catch { message = error.localizedDescription }
    }

    func createUser(app: String, username: String, password: String, days: Int) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try validate(app, days: days)
            guard username.range(of: "^[A-Za-z0-9_.@-]{3,64}$", options: .regularExpression) != nil else {
                message = "Tài khoản phải dài 3–64 ký tự: chữ, số, _, ., @, -."; return
            }
            guard password.count >= 8 && password.count <= 256 else {
                message = "Mật khẩu phải dài 8–256 ký tự."; return
            }
            _ = try await request("/api/admin/create", body: [
                "app_id": app, "username": username, "password": password, "days": days
            ])
            try await listUsers(app)
            message = "Đã tạo TK \(username). Hãy gửi mật khẩu riêng cho khách."
        } catch { message = error.localizedDescription }
    }

    func editUser(_ operation: String, app: String, username: String, days: Int) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try validate(app, days: operation == "extend" ? days : nil)
            guard ["extend", "disable", "enable", "delete"].contains(operation) else { return }
            var body: [String: Any] = ["app_id": app, "username": username]
            if operation == "extend" { body["days"] = days }
            _ = try await request("/api/admin/" + operation, body: body)
            try await listUsers(app)
            message = "Đã cập nhật tài khoản \(username): \(operation)."
        } catch { message = error.localizedDescription }
    }

    func createKey(app: String, buyer: String, days: Int) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try validate(app, days: days)
            issuedKey = ""
            let data = try await request("/api/admin/key/create", body: [
                "app_id": app, "label": buyer, "days": days
            ])
            issuedKey = try JSONDecoder().decode(IssuedKey.self, from: data).key
            try await listKeys(app)
            message = "Đã cấp key 1 thiết bị. Hãy sao chép key ngay."
        } catch { message = error.localizedDescription }
    }

    func editKey(_ operation: String, app: String, id: String, days: Int) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try validate(app, days: operation == "extend" ? days : nil)
            guard ["extend", "disable", "enable", "reset-device", "delete"].contains(operation) else { return }
            var body: [String: Any] = ["app_id": app, "id": id]
            if operation == "extend" { body["days"] = days }
            _ = try await request("/api/admin/key/" + operation, body: body)
            try await listKeys(app)
            message = "Đã cập nhật key: \(operation)."
        } catch { message = error.localizedDescription }
    }
}

private struct ERIHome: View {
    @StateObject private var m = ERIAdmin()
    @AppStorage("eri-menumod-app-id") private var app = "com.garena.game.kgvo"
    @State private var mode = 0
    @State private var username = ""
    @State private var password = ""
    @State private var buyer = ""
    @State private var daysText = "30"
    @State private var pendingDeleteUser: String?
    @State private var pendingDeleteKey: String?

    private var days: Int { Int(daysText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cấu hình Admin") {
                    SecureField("ERI_ADMIN_KEY", text: $m.secret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if m.isSecretSaved {
                        Label("Đã lưu khóa Admin trên iPhone", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Button("Xóa khóa đã lưu / đổi khóa") { m.forgetSecret() }
                    } else {
                        Text("Nhập ERI_ADMIN_KEY một lần. Bấm tải danh sách hoặc tạo tài khoản/key để xác thực; sau khi thành công, app tự lưu khóa trong Keychain. Những lần sau tự điền.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("App ID (Bundle ID / Package)", text: $app)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Quản lý") {
                    Picker("Chế độ", selection: $mode) {
                        Text("TK / Mật khẩu").tag(0)
                        Text("Key 1 thiết bị").tag(1)
                    }.pickerStyle(.segmented)
                    TextField("Số ngày dùng / gia hạn", text: $daysText)
                        .keyboardType(.numberPad)
                }
                if mode == 0 { accountsView } else { keysView }
                Section("Phản hồi máy chủ") {
                    Text(m.message).font(.footnote).textSelection(.enabled)
                }
                Section {
                    Text("TK/mật khẩu và key thiết bị là 2 phương thức khác nhau. ERI LOGIN gắn bằng dylib hiện kiểm tra key thiết bị, không kiểm tra TK/MK. Mật khẩu đã cấp không thể đọc lại từ máy chủ.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ERI LOGIN ADMIN")
            .toolbar {
                if m.busy { ProgressView() }
            }
            .alert("Xóa tài khoản?", isPresented: Binding(
                get: { pendingDeleteUser != nil },
                set: { if !$0 { pendingDeleteUser = nil } }
            )) {
                Button("Hủy", role: .cancel) { pendingDeleteUser = nil }
                Button("Xóa", role: .destructive) {
                    if let user = pendingDeleteUser {
                        Task { await m.editUser("delete", app: app, username: user, days: days) }
                    }
                    pendingDeleteUser = nil
                }
            } message: {
                Text("Tài khoản sẽ không thể đăng nhập.")
            }
            .alert("Xóa key?", isPresented: Binding(
                get: { pendingDeleteKey != nil },
                set: { if !$0 { pendingDeleteKey = nil } }
            )) {
                Button("Hủy", role: .cancel) { pendingDeleteKey = nil }
                Button("Xóa", role: .destructive) {
                    if let id = pendingDeleteKey {
                        Task { await m.editKey("delete", app: app, id: id, days: days) }
                    }
                    pendingDeleteKey = nil
                }
            } message: {
                Text("Key sẽ không thể kích hoạt hoặc xác minh.")
            }
        }
    }

    @ViewBuilder private var accountsView: some View {
        Section("Tạo tài khoản / mật khẩu") {
            TextField("Tài khoản khách (ví dụ khach001)", text: $username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Mật khẩu (ít nhất 8 ký tự)", text: $password)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Tạo TK + MK") {
                Task { await m.createUser(app: app, username: username, password: password, days: days) }
            }.disabled(m.busy)
            Button("Sao chép TK + MK") {
                UIPasteboard.general.string = "TK: \(username)\nMK: \(password)"
            }.disabled(username.isEmpty || password.isEmpty)
            Text("TK/MK chỉ được cấp bởi Admin. Không lưu mật khẩu thô trên máy chủ.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Quản lý tài khoản online") {
            Button("Tải danh sách TK") { Task { await m.refreshUsers(app: app) } }
                .disabled(m.busy)
            ForEach(m.users) { user in
                VStack(alignment: .leading, spacing: 8) {
                    Text(user.username).font(.headline).textSelection(.enabled)
                    Text("Hạn: \(user.expires_at)").font(.caption).foregroundStyle(.secondary)
                    Text(user.disabled ? "Đã khóa" : user.expired ? "Hết hạn" : "Đang dùng")
                        .font(.caption)
                    HStack {
                        Button("+\(days) ngày") {
                            Task { await m.editUser("extend", app: app, username: user.username, days: days) }
                        }
                        Button(user.disabled ? "Mở" : "Khóa") {
                            Task { await m.editUser(user.disabled ? "enable" : "disable", app: app, username: user.username, days: days) }
                        }
                        Button("Xóa", role: .destructive) { pendingDeleteUser = user.username }
                    }.buttonStyle(.bordered).font(.caption).disabled(m.busy)
                }.padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder private var keysView: some View {
        Section("Cấp key — 1 key / 1 thiết bị") {
            TextField("Tên khách mua", text: $buyer)
            Button("Tạo key mới") {
                Task { await m.createKey(app: app, buyer: buyer, days: days) }
            }.disabled(m.busy)
            if !m.issuedKey.isEmpty {
                Text("Key đầy đủ chỉ hiển thị ngay sau khi tạo").font(.caption)
                Text(m.issuedKey).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button("Sao chép key") { UIPasteboard.general.string = m.issuedKey }
                Button("Ẩn key") { m.issuedKey = "" }
            }
        }
        Section("Quản lý key online") {
            Button("Tải danh sách key") { Task { await m.refreshKeys(app: app) } }
                .disabled(m.busy)
            ForEach(m.keys) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.label.isEmpty ? "Khách chưa có tên" : item.label).font(.headline)
                    Text("••••\(item.key_suffix) • \(item.device_bound ? "Đã kích hoạt máy" : "Chưa kích hoạt")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Hạn: \(item.expires_at)").font(.caption)
                    Text(item.disabled ? "Đã khóa" : item.expired ? "Hết hạn" : "Đang dùng")
                        .font(.caption)
                    HStack {
                        Button("+\(days) ngày") {
                            Task { await m.editKey("extend", app: app, id: item.id, days: days) }
                        }
                        Button(item.disabled ? "Mở" : "Khóa") {
                            Task { await m.editKey(item.disabled ? "enable" : "disable", app: app, id: item.id, days: days) }
                        }
                        Button("Reset máy") {
                            Task { await m.editKey("reset-device", app: app, id: item.id, days: days) }
                        }
                        Button("Xóa", role: .destructive) { pendingDeleteKey = item.id }
                    }.buttonStyle(.bordered).font(.caption).disabled(m.busy)
                }.padding(.vertical, 5)
            }
        }
    }
}

@main struct ERILoginAdminApp: App {
    var body: some Scene {
        WindowGroup { ERIHome() }
    }
}
