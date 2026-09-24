import CoreGraphics
import Foundation

let ownerName = CommandLine.arguments.dropFirst().first ?? "Video to Live Turbo"

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}

for window in windows {
    guard
        let owner = window[kCGWindowOwnerName as String] as? String,
        owner == ownerName,
        let layer = window[kCGWindowLayer as String] as? Int,
        layer == 0,
        let number = window[kCGWindowNumber as String] as? Int
    else { continue }

    print(number)
    exit(0)
}

exit(1)
