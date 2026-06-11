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
    // Core info
    var name: String
    var imageData: Data?
    var dateAdded: Date
    
    // Tags (we'll let AI fill these in later, but the fields exist now)
    var category: String       // e.g. "top", "bottom", "dress", "outerwear", "shoes", "accessory"
    var colors: [String]       // e.g. ["black", "white"]
    var formality: Int         // 1–5 scale: loungewear → black tie
    var vibeTags: [String]     // e.g. ["coquette", "going out", "preppy"]
    var occasionTags: [String] // e.g. ["work", "date", "party"]
    var weatherTags: [String]   // e.g. ["summer", "warm weather"]
    
    // Wear tracking — these get updated later when user marks worn
    var wearCount: Int
    var lastWorn: Date?        // optional! starts as nil, set when first worn
    
    // Borrowing (for later, but reserve the field now)
    var isOpenToBorrow: Bool
    
    init(
        name: String,
        imageData: Data? = nil,
        category: String = "",
        colors: [String] = [],
        formality: Int = 3,
        vibeTags: [String] = [],
        occasionTags: [String] = [],
        weatherTags: [String] = [],
        isOpenToBorrow: Bool = false
    ) {
        self.name = name
        self.imageData = imageData
        self.dateAdded = Date()
        self.category = category
        self.colors = colors
        self.formality = formality
        self.vibeTags = vibeTags
        self.occasionTags = occasionTags
        self.weatherTags = weatherTags
        self.wearCount = 0          // starts at 0
        self.lastWorn = nil         // never worn yet
        self.isOpenToBorrow = isOpenToBorrow
    }
    
    // Call this when user taps "mark worn"
    func markWorn() {
        wearCount += 1
        lastWorn = Date()
    }
}
