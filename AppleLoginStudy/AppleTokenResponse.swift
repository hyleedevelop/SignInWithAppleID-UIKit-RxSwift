//
//  AppleTokenResponse.swift
//  AppleLoginStudy
//
//  Created by Eric on 2023/06/12.
//

import Foundation

struct AppleTokenResponse: Codable {
    
    //var access_token: String?
    //var token_type: String?
    //var expires_in: Int?
    var refresh_token: String?  // ⭐️ This is what we need.
    //var id_token: String?

    enum CodingKeys: String, CodingKey {
        case refresh_token = "refresh_token"
    }
    
}
