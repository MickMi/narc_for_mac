import Combine
import Foundation
import Security
import LocalAuthentication

enum InstantQuestionCredentialFailure: LocalizedError, Equatable {
    case missingDeepSeekKey
    case authorizationRequired
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingDeepSeekKey:
            return "请先在偏好设置中保存 DeepSeek API Key。"
        case .authorizationRequired:
            return "请在设置 → 即时问答中点击“授权读取密钥”，再发送问题。"
        case .keychain(let status):
            if status == errSecUserCanceled { return "已取消密钥读取授权。可在设置中再次点击“授权读取密钥”。" }
            return "暂时无法读取钥匙串中的密钥。请确认登录钥匙串已解锁；若出现授权提示，可选择“始终允许”。"
        }
    }
}

protocol InstantQuestionSecretStore: Sendable {
    func containsValue(for account: String) throws -> Bool
    func value(for account: String) throws -> String?
    func valueWithoutInteraction(for account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func removeValue(for account: String) throws
}

extension InstantQuestionSecretStore {
    // Unknown stores must opt in rather than silently showing authentication UI.
    func valueWithoutInteraction(for account: String) throws -> String? {
        throw InstantQuestionCredentialFailure.authorizationRequired
    }
    // Production overrides this with a noninteractive metadata-only query.
    func containsValue(for account: String) throws -> Bool {
        try value(for: account) != nil
    }
}

struct KeychainInstantQuestionSecretStore: InstantQuestionSecretStore {
    private static let service = "com.narc.instant-question"

    func containsValue(for account: String) throws -> Bool {
        let query = Self.readQuery(for: account, secret: false)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw InstantQuestionCredentialFailure.keychain(status)
        }
        return true
    }

    static func readQuery(for account: String, secret: Bool, allowInteraction: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if secret {
            query[kSecReturnData as String] = true
        } else {
            query[kSecReturnAttributes as String] = true
        }
        if !secret || !allowInteraction {
            // This app uses the macOS login keychain. A passive status check
            // must fail instead of presenting an authentication sheet.
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    func value(for account: String) throws -> String? {
        try readValue(for: account, allowInteraction: true)
    }

    func valueWithoutInteraction(for account: String) throws -> String? {
        try readValue(for: account, allowInteraction: false)
    }

    private func readValue(for account: String, allowInteraction: Bool) throws -> String? {
        let query = Self.readQuery(for: account, secret: true, allowInteraction: allowInteraction)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw InstantQuestionCredentialFailure.keychain(status)
        }
        return value
    }

    func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw InstantQuestionCredentialFailure.keychain(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw InstantQuestionCredentialFailure.keychain(addStatus)
        }
    }

    func removeValue(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw InstantQuestionCredentialFailure.keychain(status)
        }
    }
}

@MainActor
final class InstantQuestionCredentialManager: ObservableObject {
    static let deepSeekAccount = "deepseek-api-key"

    @Published private(set) var hasDeepSeekKey = false
    @Published private(set) var lastError: String?
    @Published private(set) var isAuthorized = false
    @Published private(set) var isAuthorizing = false

    private let secretStore: InstantQuestionSecretStore
    private var cachedDeepSeekKey: String?
    static let automaticReadConsentKey = "narc.instantQuestion.automaticKeyReadConsented"
    private let consentDefaults: UserDefaults?
    private var attemptedAutomaticRead = false

    init(secretStore: InstantQuestionSecretStore = KeychainInstantQuestionSecretStore(), defaults: UserDefaults? = nil) {
        self.secretStore = secretStore
        // Injected stores never change real preferences during tests/previews.
        consentDefaults = defaults ?? (secretStore is KeychainInstantQuestionSecretStore ? .standard : nil)
        refreshStatus()
    }

    var isReady: Bool { isAuthorized }

    func refreshStatus() {
        do {
            hasDeepSeekKey = try secretStore.containsValue(for: Self.deepSeekAccount)
            if !hasDeepSeekKey { cachedDeepSeekKey = nil; isAuthorized = false }
            lastError = nil
        } catch {
            hasDeepSeekKey = cachedDeepSeekKey != nil
            lastError = error.localizedDescription
        }
    }

    func saveDeepSeekKey(_ value: String) -> Bool {
        save(value, account: Self.deepSeekAccount)
    }

    func removeDeepSeekKey() -> Bool {
        remove(account: Self.deepSeekAccount)
    }

    func credentials() throws -> InstantQuestionCredentials {
        if let cachedDeepSeekKey {
            return InstantQuestionCredentials(deepSeekAPIKey: cachedDeepSeekKey)
        }
        // Sending and connection tests must never initiate Keychain UI.
        throw hasDeepSeekKey ? InstantQuestionCredentialFailure.authorizationRequired : .missingDeepSeekKey
    }

    /// Restore only previously consented access, once per process, without UI.
    /// System trust is checked by the actual read; the preference alone is not authorization.
    func restoreAccessIfConsented() async {
        guard !isReady, !isAuthorizing, !attemptedAutomaticRead, hasDeepSeekKey,
              consentDefaults?.bool(forKey: Self.automaticReadConsentKey) == true else { return }
        attemptedAutomaticRead = true
        _ = await read(allowInteraction: false)
    }

    /// Only the explicit settings action may initiate system authentication UI.
    /// Runs away from the main thread while the OS authentication UI waits.
    @discardableResult func authorizeRead() async -> Bool {
        await read(allowInteraction: true)
    }

    private func read(allowInteraction: Bool) async -> Bool {
        guard !isAuthorizing else { return false }
        if isReady { return true }
        isAuthorizing = true
        lastError = nil
        let store = secretStore
        let account = Self.deepSeekAccount
        let result: Result<String?, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Result {
                    try allowInteraction ? store.value(for: account) : store.valueWithoutInteraction(for: account)
                })
            }
        }
        defer { isAuthorizing = false }
        switch result {
        case .success(let value):
            guard let value, !value.isEmpty else {
                cachedDeepSeekKey = nil
                hasDeepSeekKey = false
                isAuthorized = false
                lastError = InstantQuestionCredentialFailure.missingDeepSeekKey.localizedDescription
                return false
            }
            cachedDeepSeekKey = value
            hasDeepSeekKey = true
            isAuthorized = true
            consentDefaults?.set(true, forKey: Self.automaticReadConsentKey)
            return true
        case .failure(let error):
            lastError = allowInteraction ? error.localizedDescription
                : "密钥暂时无法自动读取。请在此点击“授权读取密钥”，由系统确认访问。"
            return false
        }
    }

    private func save(_ value: String, account: String) -> Bool {
        guard !isAuthorizing else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            lastError = "API Key 不能为空。"
            return false
        }
        do {
            try secretStore.set(normalized, for: account)
            cachedDeepSeekKey = normalized
            isAuthorized = true
            hasDeepSeekKey = true
            consentDefaults?.set(true, forKey: Self.automaticReadConsentKey)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func remove(account: String) -> Bool {
        guard !isAuthorizing else { return false }
        do {
            try secretStore.removeValue(for: account)
            cachedDeepSeekKey = nil
            isAuthorized = false
            hasDeepSeekKey = false
            consentDefaults?.removeObject(forKey: Self.automaticReadConsentKey)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
