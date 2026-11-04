import CryptoKit
import Foundation
import Security

struct AppleServerCryptography: ServerCryptography {
  func authorizationAttempt() throws -> OAuthAttempt {
    let verifier = try random()
    return OAuthAttempt(
      verifier: verifier, state: try random(),
      challenge: base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))))
  }

  func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func random() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw ServerError.credentialStorage
    }
    return base64URL(Data(bytes))
  }

  private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}
