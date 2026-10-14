//
//  APNSJWTManager.swift
//  InforapServiceKit
//
//  Created for Loop APNS Response feature.
//  Manages JWT tokens for APNS authentication.
//

import Foundation
import OSLog
import SwiftJWT

class APNSJWTManager {
    static let shared = APNSJWTManager()
    
    private init() {}
    
    private struct JWTCacheKey: Hashable {
        let keyId: String
        let teamId: String
    }
    
    private struct CachedJWT {
        let token: String
        let expirationDate: Date
    }
    
    private var jwtCache: [JWTCacheKey: CachedJWT] = [:]
    private let cacheQueue = DispatchQueue(label: "com.loop.apnsjwtmanager.cache", attributes: .concurrent)
    
    func getOrGenerateJWT(keyId: String, teamId: String, apnsKey: String) -> String? {
        let cacheKey = JWTCacheKey(keyId: keyId, teamId: teamId)
        
        if let cachedJWT = getCachedJWT(for: cacheKey) {
            return cachedJWT
        }
        
        do {
            let signedJWT = try generateJWT(keyId: keyId, teamId: teamId, apnsKey: apnsKey)
            
            let expirationDate = Date().addingTimeInterval(3300)
            cacheJWT(signedJWT, for: cacheKey, expirationDate: expirationDate)
            
            return signedJWT
        } catch {
            os_log("Failed to sign JWT: %{public}@", log: .default, type: .error, error.localizedDescription)
            return nil
        }
    }
    
    private func generateJWT(keyId: String, teamId: String, apnsKey: String) throws -> String {
        let header = Header(kid: keyId)
        let claims = APNSJWTClaims(iss: teamId, iat: Date())
        var jwt = JWT(header: header, claims: claims)
        
        let privateKey = Data(apnsKey.utf8)
        let jwtSigner = JWTSigner.es256(privateKey: privateKey)
        let signedJWT = try jwt.sign(using: jwtSigner)
        
        return signedJWT
    }
    
    private struct APNSJWTClaims: Claims {
        let iss: String
        let iat: Date
    }
    
    private func getCachedJWT(for key: JWTCacheKey) -> String? {
        cacheQueue.sync {
            guard let cached = jwtCache[key],
                  Date() < cached.expirationDate
            else {
                return nil
            }
            return cached.token
        }
    }
    
    private func cacheJWT(_ token: String, for key: JWTCacheKey, expirationDate: Date) {
        cacheQueue.async(flags: .barrier) {
            self.jwtCache[key] = CachedJWT(token: token, expirationDate: expirationDate)
        }
    }
    
    func invalidateCache() {
        cacheQueue.async(flags: .barrier) {
            self.jwtCache.removeAll()
        }
    }
}

