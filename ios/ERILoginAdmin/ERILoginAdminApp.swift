import SwiftUI
import Foundation
import Security
import UIKit

// ERI LOGIN ADMIN • MOD BY ERI NGUYỄN
// Key-only licensing manager. No customer password or legacy-account UI.
// Keep existing iOS Keychain service to preserve the saved Admin secret.
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
private struct DeleteTarget: Identifiable {
    let id: String
    let label: String
}

@MainActor private final class ERIKeyManager: ObservableObject {
    @Published var secret = ERIVault.read()
    @Published var saved = !ERIVault.read().isEmpty
    @Published var keys: [LicenseKey] = []
    @Published var issuedKey = ""
    @Published var message = "Sẵn sàng quản lý key thiết bị."
    @Published var busy = false
    private let origin = "https://eri-login-api.onrender.com"

    func clearSecret() {
        ERIVault.save("")
        secret = ""
        saved = false
        keys = []
        message = "Đã xóa khóa quản trị khỏi iPhone."
    }

    private func request(_ route: String, body: [String: Any]? = nil) async throws -> Data {
        let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 32 else {
            throw NSError(domain: "ERI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nhập ERI_ADMIN_KEY để quản lý key."])
        }
        guard let url = URL(string: origin + route) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 95
        req.setValue(token, forHTTPHeaderField: "X-ERI-ADMIN-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let payload = body {
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 403 {
                if ERIVault.read() == token { ERIVault.save("") }
                saved = false
                keys = []
                throw NSError(domain: "ERI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Khóa Admin không hợp lệ (403). Kiểm tra lại ERI_ADMIN_KEY."])
            }
            let cause = (try? JSONDecoder().decode(APIError.self, from: data).error)
                        ?? "Lỗi máy chủ HTTP \(http.statusCode)"
            throw NSError(domain: "ERI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: cause])
        }
        if ERIVault.read() != token { ERIVault.save(token) }
        saved = ERIVault.read() == token
        return data
    }

    private func validate(_ app: String, days: Int? = nil) throws {
        guard app.range(of: "^[A-Za-z0-9_.-]{2,128}$", options: .regularExpression) != nil else {
            throw NSError(domain: "ERI", code: 2, userInfo: [NSLocalizedDescriptionKey: "App ID không hợp lệ."])
        }
        if let d = days, !(1...3650).contains(d) {
            throw NSError(domain: "ERI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Số ngày phải từ 1–3650."])
        }
    }
    private func fetchKeys(_ app: String) async throws {
        var c = URLComponents()
        c.queryItems = [URLQueryItem(name: "app_id", value: app)]
        let route = "/api/admin/key/list?" + (c.percentEncodedQuery ?? "")
        keys = try JSONDecoder().decode(KeyList.self, from: try await request(route)).keys
    }
    private func perform(_ work: () async throws -> String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { message = try await work() }
        catch { message = error.localizedDescription }
    }
    func refresh(app: String) async {
        await perform {
            try validate(app)
            try await fetchKeys(app)
            return "Đã đồng bộ \(keys.count) key từ máy chủ."
        }
    }
    func create(app: String, buyer: String, days: Int) async {
        await perform {
            try validate(app, days: days)
            issuedKey = ""
            let data = try await request("/api/admin/key/create", body: [
                "app_id": app, "label": String(buyer.prefix(96)), "days": days
            ])
            issuedKey = try JSONDecoder().decode(IssuedKey.self, from: data).key
            try await fetchKeys(app)
            return "Tạo key thành công. Sao chép key mới để gửi khách!"
        }
    }
    func action(_ name: String, app: String, id: String, days: Int) async {
        await perform {
            try validate(app, days: name == "extend" ? days : nil)
            guard ["extend", "disable", "enable", "reset-device", "delete"].contains(name) else {
                throw NSError(domain: "ERI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Lệnh không hợp lệ."])
            }
            var body: [String: Any] = ["app_id": app, "id": id]
            if name == "extend" { body["days"] = days }
            let data = try await request("/api/admin/key/" + name, body: body)
            if name == "delete" {
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard payload?["deleted"] as? Bool == true else {
                    throw NSError(domain: "ERI", code: 502, userInfo: [NSLocalizedDescriptionKey: "Máy chủ chưa xác nhận xóa key."])
                }
            }
            try await fetchKeys(app)
            if name == "delete" && keys.contains(where: { $0.id == id }) {
                throw NSError(domain: "ERI", code: 502, userInfo: [NSLocalizedDescriptionKey: "Key vẫn tồn tại sau yêu cầu xóa."])
            }
            switch name {
            case "extend": return "Đã gia hạn thêm \(days) ngày."
            case "disable": return "Đã khóa key."
            case "enable": return "Đã mở khóa key."
            case "reset-device": return "Đã reset liên kết thiết bị."
            default: return "Đã xóa key khỏi máy chủ."
            }
        }
    }
}

private enum ERIStyle {
    static let background = Color(red: 0.035, green: 0.057, blue: 0.115)
    static let card = Color(red: 0.080, green: 0.111, blue: 0.197)
    static let blue = Color(red: 0.24, green: 0.56, blue: 1)
    static let cyan = Color(red: 0.28, green: 0.89, blue: 0.97)
    static let muted = Color(red: 0.65, green: 0.71, blue: 0.82)
    static let border = Color.white.opacity(0.085)
}
private struct ERICard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ERIStyle.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ERIStyle.border))
    }
}
private struct ERIAdminHome: View {
    @StateObject private var model = ERIKeyManager()
    @AppStorage("eri-menumod-app-id") private var appID = "com.garena.game.kgvo"
    @State private var buyer = ""
    @State private var daysText = "30"
    @State private var target: DeleteTarget?
    @State private var showActionResult = false
    private var days: Int { Int(daysText) ?? 0 }
    private var activeCount: Int { model.keys.filter { !$0.disabled && !$0.expired }.count }
    private var boundCount: Int { model.keys.filter { $0.device_bound }.count }

    private func inputField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(Color.white)
            .padding(13)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
    }
    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [ERIStyle.blue, Color(red: 0.35, green: 0.37, blue: 0.91)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 13)
                )
        }.buttonStyle(.plain).disabled(model.busy)
    }
    private func actionButton(_ title: String, color: Color = .white, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(model.busy)
    }
    private func lineHeading(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MOD BY ERI NGUYỄN")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(ERIStyle.cyan)
                        Text("ERI LOGIN").font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        HStack {
                            Text("KEY ADMIN").font(.system(size: 12, weight: .bold)).tracking(1)
                            Image(systemName: "shield.lefthalf.filled")
                        }.foregroundStyle(ERIStyle.muted)
                    }.padding(.top, 16).padding(.bottom, 6)

                    HStack(spacing: 10) {
                        metric("TỔNG KEY", value: model.keys.count, icon: "key.fill")
                        metric("ĐANG DÙNG", value: activeCount, icon: "checkmark.shield.fill")
                        metric("ĐÃ GẮN MÁY", value: boundCount, icon: "iphone")
                    }
                    ERICard {
                        lineHeading("Cấu hình quản trị", symbol: "lock.shield")
                        if model.saved {
                            Label("Đã lưu Admin Key trong iPhone Keychain", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(ERIStyle.cyan)
                        }
                        SecureField("ERI_ADMIN_KEY (chỉ nhập 1 lần)", text: $model.secret)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .padding(13)
                            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
                        inputField("App ID (Bundle ID / Package)", text: $appID)
                        Text("App ID phải giống mục APP ID hiển thị trong ERI LOGIN của khách. Nếu IPA đổi Bundle ID khi ký, hãy dùng App ID được hiển thị ở đó.")
                            .font(.caption)
                            .foregroundStyle(ERIStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        primary("XÁC THỰC & ĐỒNG BỘ", symbol: "arrow.triangle.2.circlepath") {
                            Task { await model.refresh(app: appID) }
                        }
                        if model.saved {
                            actionButton("Đổi / xóa khóa Admin đã lưu", color: ERIStyle.muted) {
                                model.clearSecret()
                            }
                        }
                    }
                    ERICard {
                        lineHeading("Tạo key 1 thiết bị", symbol: "plus.square.on.square")
                        inputField("Tên khách hàng (không bắt buộc)", text: $buyer)
                        HStack {
                            Text("Thời hạn sử dụng").foregroundStyle(ERIStyle.muted).font(.subheadline)
                            Spacer()
                            TextField("30", text: $daysText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.white)
                                .frame(width: 64)
                            Text("ngày").foregroundStyle(ERIStyle.muted)
                        }
                        primary("TẠO KEY MỚI", symbol: "key.horizontal.fill") {
                            Task { await model.create(app: appID, buyer: buyer, days: days) }
                        }
                        if !model.issuedKey.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("KEY VỪA TẠO • SAO CHÉP NGAY")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ERIStyle.cyan)
                                Text(model.issuedKey)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                                actionButton("Sao chép key", color: ERIStyle.cyan) {
                                    UIPasteboard.general.string = model.issuedKey
                                }
                                actionButton("Ẩn key") { model.issuedKey = "" }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    ERICard {
                        HStack {
                            lineHeading("Key của khách hàng", symbol: "person.2.fill")
                            Spacer()
                            Button("Làm mới") { Task { await model.refresh(app: appID) } }
                                .font(.subheadline.bold()).foregroundStyle(ERIStyle.cyan)
                                .disabled(model.busy)
                        }
                        if model.keys.isEmpty {
                            Text("Chưa có key trong danh sách. Bấm Xác thực & Đồng bộ để tải.")
                                .font(.subheadline).foregroundStyle(ERIStyle.muted)
                                .padding(.vertical, 12)
                        }
                        ForEach(model.keys) { key in
                            VStack(alignment: .leading, spacing: 11) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(key.label.isEmpty ? "Khách hàng ERI" : key.label)
                                            .font(.headline).foregroundStyle(.white)
                                        Text("KEY ••••" + key.key_suffix)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(ERIStyle.muted)
                                    }
                                    Spacer()
                                    Text(key.disabled ? "ĐÃ KHÓA" : key.expired ? "HẾT HẠN" : "ĐANG DÙNG")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(key.disabled || key.expired ? .orange : ERIStyle.cyan)
                                        .padding(.horizontal, 9).padding(.vertical, 6)
                                        .background(Color.white.opacity(0.07), in: Capsule())
                                }
                                Text("Hạn: " + String(key.expires_at.prefix(10))
                                     + "  •  " + (key.device_bound ? "Đã liên kết thiết bị" : "Chưa kích hoạt"))
                                    .font(.caption).foregroundStyle(ERIStyle.muted)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    actionButton("+\(days) ngày", color: ERIStyle.cyan) {
                                        Task { await model.action("extend", app: appID, id: key.id, days: days) }
                                    }
                                    actionButton(key.disabled ? "Mở khóa" : "Khóa key") {
                                        Task { await model.action(key.disabled ? "enable" : "disable", app: appID, id: key.id, days: days) }
                                    }
                                    actionButton("Reset máy") {
                                        Task { await model.action("reset-device", app: appID, id: key.id, days: days) }
                                    }
                                    actionButton("Xóa key", color: .red) {
                                        target = DeleteTarget(id: key.id, label: key.label.isEmpty ? "••••" + key.key_suffix : key.label)
                                    }
                                }
                            }
                            .padding(.vertical, 12)
                            if key.id != model.keys.last?.id {
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                    if model.busy { ProgressView().tint(ERIStyle.cyan).frame(maxWidth: .infinity) }
                    Text(model.message).font(.subheadline)
                        .foregroundStyle(ERIStyle.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                        .textSelection(.enabled)
                    Text("MOD BY ERI NGUYỄN  •  1 KEY / 1 THIẾT BỊ")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1).foregroundStyle(ERIStyle.muted)
                        .frame(maxWidth: .infinity).padding(.bottom, 30)
                }
                .padding(.horizontal, 17)
            }
            .background(ERIStyle.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .task { if model.saved { await model.refresh(app: appID) } }
            .sheet(item: $target) { chosen in
                VStack(alignment: .leading, spacing: 18) {
                    Text("XÓA KEY VĨNH VIỄN").font(.title3.bold())
                    Text("Khách: " + chosen.label)
                    Text("Key sẽ không thể dùng lại. Hành động này không thể hoàn tác.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    primary("XÁC NHẬN XÓA", symbol: "trash.fill") {
                        let captured = chosen
                        target = nil
                        Task {
                            await model.action("delete", app: appID, id: captured.id, days: days)
                            showActionResult = true
                        }
                    }
                    Button("Hủy") { target = nil }.frame(maxWidth: .infinity)
                }
                .padding(24)
                .presentationDetents([.height(300)])
                .preferredColorScheme(.dark)
            }
            .alert("Phản hồi máy chủ", isPresented: $showActionResult) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(model.message)
            }
        }
    }
    private func metric(_ name: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundStyle(ERIStyle.cyan)
            Text("\(value)").font(.system(size: 23, weight: .heavy))
                .foregroundStyle(.white)
            Text(name).font(.system(size: 9, weight: .bold))
                .foregroundStyle(ERIStyle.muted)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(ERIStyle.card, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(ERIStyle.border))
    }
}

@main struct ERILoginAdminApp: App {
    var body: some Scene { WindowGroup { ERIAdminHome() } }
}
