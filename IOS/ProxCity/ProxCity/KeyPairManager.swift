import Foundation
import CryptoKit

class KeyPairManager: ObservableObject {
    static let shared = KeyPairManager()

    @Published var publicKey: String = ""
    private var privateKey: Curve25519.Signing.PrivateKey?

    init() {
        loadOrGenerateKey()
    }

    private func loadOrGenerateKey() {
        // For testing: always generate a new keypair on each launch
        UserDefaults.standard.removeObject(forKey: "privateKey")
        let key = Curve25519.Signing.PrivateKey()
        privateKey = key
        UserDefaults.standard.set(key.rawRepresentation, forKey: "privateKey")

        // Update publicKey from freshly generated key
        let pubData = key.publicKey.rawRepresentation
        publicKey = pubData.base64EncodedString()
    }

    func sign(message: String) -> String? {
        guard let key = privateKey else { return nil }
        let data = Data(message.utf8)
        let signature = try? key.signature(for: data)
        return signature?.base64EncodedString()
    }
}