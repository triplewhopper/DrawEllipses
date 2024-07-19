//
//  AppDelegate.swift
//  DrawEllipses
//
//  Created by jsr on 2024/7/19.
//

import UIKit
import SwiftUI
import os

let logger = Logger()

struct EllipseState: Equatable {
    var a: CGFloat
    var b: CGFloat
    var color: UIColor
    var center = CGPoint.zero
    var translation = CGPoint.zero
    var angle = Angle(degrees: 0.0)
    var deltaAngle = Angle(degrees: 0.0)
    var deltaA = CGFloat.zero
    var deltaB = CGFloat.zero
    var currentAngle: Angle { angle + deltaAngle }
    var size: CGSize { CGSize(width: (a + deltaA) * 2, height: (b + deltaB) * 2) }
    
    var velocityMajorAxis: CGPoint {
        return CGPoint(x: cos(self.currentAngle.radians), y: sin(self.currentAngle.radians))
    }
    
    var velocityMinorAxis: CGPoint {
        return CGPoint(x: -sin(self.currentAngle.radians), y: cos(self.currentAngle.radians))
    }
    
    init(center: CGPoint, a: CGFloat, b: CGFloat, color: UIColor, angle: Angle = .zero) {
        self.center = center
        self.a = a
        self.b = b
        self.color = color
        self.angle = angle
    }
    
    func applyTranslation() -> EllipseState {
        var res = self
        res.center.x += translation.x
        res.center.y += translation.y
        res.translation = .zero
        return res
    }
    func applyRotation() -> EllipseState {
        var res = self
        res.angle += deltaAngle
        res.deltaAngle = .zero
        return res
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

