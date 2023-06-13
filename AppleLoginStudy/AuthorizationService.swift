//
//  CryptoService.swift
//  AppleLoginStudy
//
//  Created by Eric on 2023/06/12.
//

import UIKit
import RxSwift
import AuthenticationServices
import CryptoKit
import SwiftJWT
import Alamofire

final class AuthorizationService {
    
    static let shared = AuthorizationService()
    private init() {}
    
    let decodedData = BehaviorSubject<AppleTokenResponse?>(value: nil)
    let isAppleTokenRevoked = BehaviorSubject<Bool>(value: false)
    
    var currentNonce: String?
    
    var appleIDRequest: ASAuthorizationAppleIDRequest {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        let nonce = self.randomNonceString()
        
        request.requestedScopes = [.fullName, .email]
        request.nonce = self.sha256(nonce)
        self.currentNonce = nonce
        
        return request
    }
    
    func decode(jwtToken jwt: String) -> [String: Any] {
        let segments = jwt.components(separatedBy: ".")
        return decodeJWTPart(segments[1]) ?? [:]
    }
    
    func decodeJWTPart(_ value: String) -> [String: Any]? {
        guard let bodyData = base64UrlDecode(value),
              let json = try? JSONSerialization.jsonObject(with: bodyData, options: []),
              let payload = json as? [String: Any] else {
            return nil
        }
        
        return payload
    }
    
    func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 = base64 + padding
        }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
    
    // Create random nonce string.
    func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: Array<Character> =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    // Get hash string.
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // Create JWT(JSON Web Token) string.
    func createJWT() -> String {
        let myHeader = Header(kid: Constant.Authorization.appleKeyID)  // ⭐️ write your own apple key ID (xxxxxxxxxx)
        struct MyClaims: Claims {
            let iss: String
            let iat: Int
            let exp: Int
            let aud: String
            let sub: String
        }
        
        var dateComponent = DateComponents()
        dateComponent.month = 6
        let iat = Int(Date().timeIntervalSince1970)
        let exp = iat + 3600
        
        let myClaims = MyClaims(iss: Constant.App.appTeamID,  // ⭐️ write your own app team ID (xxxxxxxxxx)
                                iat: iat,
                                exp: exp,
                                aud: "https://appleid.apple.com",
                                sub: Constant.App.appBundleID)  // ⭐️ write your own app bundle ID (com.xxx.xxx)
        var myJWT = JWT(header: myHeader, claims: myClaims)
        
        // JWT 발급을 요청값의 암호화 과정에서 다운받아두었던 Key File(.p8 파일)이 필요함
        guard let url = Bundle.main.url(forResource: Constant.Authorization.keyFileName, withExtension: "p8") else { return "" }  // ⭐️ write your own key file name (AuthKey_xxxxxxxxxx)
        let privateKey: Data = try! Data(contentsOf: url, options: .alwaysMapped)
        
        let jwtSigner = JWTSigner.es256(privateKey: privateKey)
        let signedJWT = try! myJWT.sign(using: jwtSigner)
        
        UserDefaults.standard.set(signedJWT, forKey: Constant.UserDefaults.clientSecret)
        
        print("🗝 signedJWT - \(signedJWT)")
        return signedJWT
    }
    
    //MARK: - Method for membership withdrawal
    
    // 1. Apple Refresh Token 받기
    //func getAppleRefreshToken(code: String, completion: @escaping (AppleTokenResponse) -> Void) {
    func getAppleRefreshToken(code: String) {
        guard let secret = UserDefaults.standard.string(forKey: Constant.UserDefaults.clientSecret) else { return }
        
        let url = "https://appleid.apple.com/auth/token?" +
                  "client_id=\(Constant.App.appBundleID)&" +
                  "client_secret=\(secret)&" +
                  "code=\(code)&" +
                  "grant_type=authorization_code"
        let header: HTTPHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        print("🗝 clientSecret - \(secret)")
        print("🗝 authCode - \(code)")
        
        AF.request(url,
                   method: .post,
                   encoding: JSONEncoding.default,
                   headers: header)
        .validate(statusCode: 200..<300)
        .responseData { response in
            switch response.result {
            case .success(let output):
                if let decodedData = try? JSONDecoder().decode(AppleTokenResponse.self, from: output) {
                    if decodedData.refresh_token == nil{
                        print("Failed to withdraw from membership.")
                    } else {
                        //completion(decodedData)
                        print("decodedData.refresh_token: \(decodedData.refresh_token ?? "no refresh token")")
                        self.decodedData.onNext(decodedData)
                    }
                }
                
            case .failure(_):
                print("Failed to withdraw from membership: \(response.error.debugDescription)")
            }
        }
    }
    
    // 2. Apple Token 삭제
    //func revokeAppleToken(clientSecret: String, token: String, completion: @escaping () -> Void) {
    func revokeAppleToken(clientSecret: String, token: String) {
        let url = "https://appleid.apple.com/auth/revoke?" +
                  "client_id=\(Constant.App.appBundleID)&" +
                  "client_secret=\(clientSecret)&" +
                  "token=\(token)&" +
                  "token_type_hint=refresh_token"
        let header: HTTPHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        AF.request(url,
                   method: .post,
                   headers: header)
        .validate(statusCode: 200..<300)
        .responseData { response in
            guard let statusCode = response.response?.statusCode else {
                print("Status code is not 200.")
                return
            }
            
            if statusCode == 200 {
                print("Apple token has successfully revoked.")
                self.isAppleTokenRevoked.onNext(true)
            }
        }
    }
    
}
