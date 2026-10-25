//
//  OTPSecureMessenger.swift
//  SecondNightscoutServiceKit
//
//  Created for Loop APNS Response feature.
//  Uses OTP code for encryption/decryption instead of shared secret.
//

import Foundation
import CryptoKit

struct OTPSecureMessenger {
    private let encryptionKey: SymmetricKey
    
    init?(otpCode: String) {
        guard let otpData = otpCode.data(using: .utf8) else {
            return nil
        }
        let hashed = SHA256.hash(data: otpData)
        encryptionKey = SymmetricKey(data: hashed)
    }
    
    func encrypt<T: Encodable>(_ object: T) throws -> String {
        let dataToEncrypt = try JSONEncoder().encode(object)
        
        let nonce = AES.GCM.Nonce()
        
        let sealedBox = try AES.GCM.seal(dataToEncrypt, using: encryptionKey, nonce: nonce)
        
        let nonceData = Data(nonce)
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag
        let combinedData = nonceData + ciphertext + tag
        
        return combinedData.base64EncodedString()
    }
    
    func decrypt(base64EncodedString: String) throws -> ReturnNotificationInfo {
        guard let combinedData = Data(base64Encoded: base64EncodedString) else {
            throw NSError(
                domain: "OTPSecureMessenger",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Base64 string"]
            )
        }
        
        let nonceSize = 12
        let tagSize = 16
        guard combinedData.count > nonceSize + tagSize else {
            throw NSError(
                domain: "OTPSecureMessenger",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "Encrypted data is too short"]
            )
        }
        
        let nonceData = combinedData.prefix(nonceSize)
        let tag = combinedData.suffix(tagSize)
        let ciphertext = combinedData.dropFirst(nonceSize).dropLast(tagSize)
        
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        let returnInfo = try JSONDecoder().decode(ReturnNotificationInfo.self, from: decryptedData)
        
        return returnInfo
    }
}

struct ReturnNotificationInfo: Codable {
    let productionEnvironment: Bool
    let deviceToken: String
    let bundleId: String
    let teamId: String
    let keyId: String
    let apnsKey: String
    
    enum CodingKeys: String, CodingKey {
        case productionEnvironment = "production_environment"
        case deviceToken = "device_token"
        case bundleId = "bundle_id"
        case teamId = "team_id"
        case keyId = "key_id"
        case apnsKey = "apns_key"
    }
}

