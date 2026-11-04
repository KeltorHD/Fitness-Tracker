import Foundation
import Security

actor KeychainAccountTokenStore: AccountTokenStoring {
  private let service: String
  private let account: String

  init(service: String, account: String) {
    self.service = service
    self.account = account
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
    ]
  }

  func load() throws -> AccountTokens? {
    var query = query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw ServerError.credentialStorage
    }
    do { return try JSONDecoder().decode(AccountTokens.self, from: data) } catch {
      // Never silently discard a malformed credential item.
      throw ServerError.credentialStorage
    }
  }

  func save(_ tokens: AccountTokens) throws {
    let data = try JSONEncoder().encode(tokens)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      guard
        SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
          == errSecSuccess
      else {
        throw ServerError.credentialStorage
      }
    } else if status != errSecSuccess {
      throw ServerError.credentialStorage
    }
  }

  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ServerError.credentialStorage
    }
  }
}
