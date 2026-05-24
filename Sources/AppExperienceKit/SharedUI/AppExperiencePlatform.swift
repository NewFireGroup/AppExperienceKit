import Foundation

#if canImport(UIKit)
import UIKit
#endif

public enum AppExperiencePlatform {
    public static var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    public static var isMac: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .mac
        #else
        false
        #endif
    }
}
