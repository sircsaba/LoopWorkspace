//
//  NibLoadable.swift
//  InforapServiceKitUI
//
//  Created by Darin Krauss on 6/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit

protocol NibLoadable: IdentifiableClass {

    static func nib() -> UINib

}

extension NibLoadable {

    static func nib() -> UINib {
        return UINib(nibName: className, bundle: Bundle(for: self))
    }

}
