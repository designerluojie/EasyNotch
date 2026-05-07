import Foundation
import Security

nonisolated struct CredentialAccount: Codable, Hashable {
    let providerID: String
    let purpose: String?

    init(providerID: String, purpose: String? = nil) {
        self.providerID = providerID
        self.purpose = purpose
    }
}

nonisolated enum SecureCredentialStoreError: Error, Equatable {
    case decodingFailed
    case unexpectedStatus(OSStatus)
}

protocol SecureCredentialStore {
    func save(_ secret: String, for account: CredentialAccount) throws
    func load(for account: CredentialAccount) throws -> String?
    func delete(for account: CredentialAccount) throws
}

final class InMemorySecureCredentialStore: SecureCredentialStore {
    private var secrets: [CredentialAccount: String]

    init(secrets: [CredentialAccount: String] = [:]) {
        self.secrets = secrets
    }

    func save(_ secret: String, for account: CredentialAccount) throws {
        secrets[account] = secret
    }

    func load(for account: CredentialAccount) throws -> String? {
        secrets[account]
    }

    func delete(for account: CredentialAccount) throws {
        secrets.removeValue(forKey: account)
    }
}

final class KeychainCredentialStore: SecureCredentialStore {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "NotchToolbox") {
        self.service = service
    }

    func save(_ secret: String, for account: CredentialAccount) throws {
        try delete(for: account)

        var query = baseQuery(for: account)
        query[kSecValueData as String] = Data(secret.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureCredentialStoreError.unexpectedStatus(status)
        }
    }

    func load(for account: CredentialAccount) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecureCredentialStoreError.unexpectedStatus(status)
        }

        guard
            let data = item as? Data,
            let secret = String(data: data, encoding: .utf8)
        else {
            throw SecureCredentialStoreError.decodingFailed
        }

        return secret
    }

    func delete(for account: CredentialAccount) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for account: CredentialAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.identifier
        ]
    }
}

private extension CredentialAccount {
    var identifier: String {
        guard let purpose else {
            return providerID
        }

        return "\(providerID):\(purpose)"
    }
}
