//
//  InforapService+UI.swift
//  InforapServiceKitUI
//
//  Created by Darin Krauss on 6/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import InforapServiceKit

extension InforapService: ServiceUI {
    public static var image: UIImage? {
        UIImage(named: "glucosemonitor", in: Bundle(for: ServiceUICoordinator.self), compatibleWith: nil)!
    }

    public static func setupViewController(colorPalette: LoopUIColorPalette, pluginHost: PluginHost) -> SetupUIResult<ServiceViewController, ServiceUI> {
        return .userInteractionRequired(ServiceUICoordinator(colorPalette: colorPalette))
    }

    public func settingsViewController(colorPalette: LoopUIColorPalette) -> ServiceViewController {
        return ServiceUICoordinator(service: self, colorPalette: colorPalette)
    }
}
