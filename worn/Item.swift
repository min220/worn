//
//  Item.swift
//  worn
//
//  Created by min rungsinaporn on 25/5/2569 BE.
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
