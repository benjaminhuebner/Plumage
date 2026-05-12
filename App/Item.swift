//
//  Item.swift
//  Plumage
//
//  Created by Benjamin Hübner on 12.05.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
