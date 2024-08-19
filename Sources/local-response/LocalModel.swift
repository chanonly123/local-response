//
//  File.swift
//  
//
//  Created by Chandan on 17/08/24.
//

import Foundation

struct LocalModel: Codable {
    let subUrl: String?
    let method: String?
    let body: String?
    let statusCode: Int?
    let resHeaders: [String: String]?
}
