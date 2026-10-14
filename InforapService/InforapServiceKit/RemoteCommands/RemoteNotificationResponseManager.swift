//
//  RemoteNotificationResponseManager.swift
//  InforapServiceKit
//
//  Created for Loop APNS Response feature.
//  Manages sending response notifications back via APNS.
//

import Foundation
import OSLog

class RemoteNotificationResponseManager {
    static let shared = RemoteNotificationResponseManager()
    
    private let log = OSLog(category: "RemoteNotificationResponseManager")
    
    private init() {}
    
    struct NotificationPayload: Encodable {
        let aps: APSPayload
        let commandStatus: String
        let commandType: String
        let timestamp: TimeInterval
        
        enum CodingKeys: String, CodingKey {
            case aps
            case commandStatus = "command_status"
            case commandType = "command_type"
            case timestamp
        }
    }
    
    struct APSPayload: Encodable {
        let alert: Alert
        let sound: String = "default"
    }
    
    struct Alert: Encodable {
        let title: String
        let body: String
    }
    
    enum CommandType: String {
        case bolus = "bolus"
        case carbs = "carbs"
        case override = "override"
        case cancelOverride = "cancel_override"
    }
    
    func sendResponseNotification(
        to returnInfo: ReturnNotificationInfo?,
        commandType: CommandType,
        success: Bool,
        message: String
    ) async {
        guard let returnInfo = returnInfo else {
            os_log("No return notification info provided, skipping response", log: log, type: .info)
            return
        }
        
        guard !returnInfo.deviceToken.isEmpty else {
            os_log("Return notification info has empty device token, skipping response", log: log, type: .error)
            return
        }
        
        os_log("Sending response notification - Type: %{public}@, Status: %{public}@, Message: %{public}@, DeviceToken: %{public}@", log: log, type: .info, commandType.rawValue, success ? "success" : "failed", message, returnInfo.deviceToken)
        
        let payload = NotificationPayload(
            aps: APSPayload(
                alert: Alert(
                    title: success ? "Command Successful" : "Command Failed",
                    body: message
                )
            ),
            commandStatus: success ? "success" : "failed",
            commandType: commandType.rawValue,
            timestamp: Date().timeIntervalSince1970
        )
        
        await sendPushNotification(
            payload: payload,
            to: returnInfo.deviceToken,
            using: returnInfo
        )
    }
    
    private func sendPushNotification(
        payload: NotificationPayload,
        to deviceToken: String,
        using returnInfo: ReturnNotificationInfo
    ) async {
        guard let jwt = APNSJWTManager.shared.getOrGenerateJWT(
            keyId: returnInfo.keyId,
            teamId: returnInfo.teamId,
            apnsKey: returnInfo.apnsKey
        ) else {
            os_log("Failed to generate JWT for response notification", log: log, type: .error)
            return
        }
        
        let host = returnInfo.productionEnvironment ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(deviceToken)") else {
            os_log("Failed to construct APNs URL", log: log, type: .error)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("0", forHTTPHeaderField: "apns-expiration")
        request.setValue(returnInfo.bundleId, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        
        do {
            let jsonData = try JSONEncoder().encode(payload)
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    os_log("Response notification sent successfully", log: log, type: .info)
                } else {
                    os_log("Failed to send response notification: %d", log: log, type: .error, httpResponse.statusCode)
                }
            }
        } catch {
            os_log("Error sending response notification: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }
}

