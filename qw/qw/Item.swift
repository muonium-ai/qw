//
//  Item.swift
//  qw
//
//  Created by Senthil Nayagam on 10/01/26.
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
