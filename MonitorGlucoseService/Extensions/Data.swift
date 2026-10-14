//
//  Data.swift
//  MonitorGlucoseServiceKit
//
//  Created by Pete Schwamb on 2/21/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

extension Data {
    var hexadecimalString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
