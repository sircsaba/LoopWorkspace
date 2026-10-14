//
//  MonitorGlucoseServiceKitPlugin.swift
//  MonitorGlucoseServiceKitPlugin
//
//  Created by Darin Krauss on 9/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKitUI
import MonitorGlucoseServiceKit
import MonitorGlucoseServiceKitUI

class MonitorGlucoseServiceKitPlugin: NSObject, ServiceUIPlugin {
    private let log = OSLog(category: "MonitorGlucoseServiceKitPlugin")

    public var serviceType: ServiceUI.Type? {
        return MonitorGlucoseService.self
    }

    override init() {
        super.init()
        log.default("Instantiated")
    }
}
