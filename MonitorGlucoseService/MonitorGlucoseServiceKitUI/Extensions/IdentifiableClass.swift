//
//  IdentifiableClass.swift
//  MonitorGlucoseServiceKitUI
//
//  Created by Darin Krauss on 6/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

protocol IdentifiableClass: AnyObject {

    static var className: String { get }

}

extension IdentifiableClass {

    static var className: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }

}
