//
//  SecondNightscoutServiceKitPlugin.swift
//  SecondNightscoutServiceKitPlugin
//
//  Created by Darin Krauss on 9/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKitUI
import SecondNightscoutServiceKit
import SecondNightscoutServiceKitUI

class SecondNightscoutServiceKitPlugin: NSObject, ServiceUIPlugin {
    private let log = OSLog(category: "SecondNightscoutServiceKitPlugin")

    public var serviceType: ServiceUI.Type? {
        return SecondNightscoutService.self
    }

    override init() {
        super.init()
        log.default("Instantiated")
    }
}
