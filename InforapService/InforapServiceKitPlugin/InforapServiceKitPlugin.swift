//
//  InforapServiceKitPlugin.swift
//  InforapServiceKitPlugin
//
//  Created by Darin Krauss on 9/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKitUI
import InforapServiceKit
import InforapServiceKitUI

class InforapServiceKitPlugin: NSObject, ServiceUIPlugin {
    private let log = OSLog(category: "InforapServiceKitPlugin")

    public var serviceType: ServiceUI.Type? {
        return InforapService.self
    }

    override init() {
        super.init()
        log.default("Instantiated")
    }
}
