//
//  RemoteCommandSource.swift
//  InforapServiceKit
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol RemoteCommandSource {
    func remoteNotificationWasReceived(_ notification: [String: AnyObject]) async
}
