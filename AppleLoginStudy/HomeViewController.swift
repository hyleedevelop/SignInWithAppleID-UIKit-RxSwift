//
//  HomeViewController.swift
//  AppleLoginStudy
//
//  Created by Eric on 2023/06/12.
//

import UIKit
import RxSwift
import RxCocoa
import NSObject_Rx
import AuthenticationServices
import Alamofire

final class HomeViewController: UIViewController {

    //MARK: - IB outlet
    
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var emailLabel: UILabel!
    @IBOutlet weak var withdrawalButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    //MARK: - Property
    
    private var userName: Observable<String> {
        let name = UserDefaults.standard.string(forKey: Constant.UserDefaults.userName) ?? "?"
        let nameString = "\(name)"
        return Observable.just(nameString)
    }
    private var userEmail: Observable<String> {
        let email = UserDefaults.standard.string(forKey: Constant.UserDefaults.userEmail) ?? "?"
        let emailString = "(\(email))"
        return Observable.just(emailString)
    }
    private let isWithdrawalAllowed = PublishSubject<Bool>()
    private let authorizationCode = PublishSubject<String>()
    
    //MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupLabel()
        self.setupButton()
        self.setupMembershipWithdrawalProcess()
    }
    
    //MARK: - Main process
    
    private func setupLabel() {
        // Bind user name.
        self.userName
            .bind(to: self.nameLabel.rx.text)
            .disposed(by: rx.disposeBag)
            
        // Bind user email address.
        self.userEmail
            .bind(to: self.emailLabel.rx.text)
            .disposed(by: rx.disposeBag)
    }
    
    private func setupButton() {
        // Set corner radius of the button.
        self.withdrawalButton.layer.cornerRadius = 5
        self.withdrawalButton.clipsToBounds = true
        
        // Refer to the Main.storyboard for other settings.
    }
    
    private func setupMembershipWithdrawalProcess() {
        /*
         (1) 버튼이 눌리는 것을 관찰합니다.
         (2)
         (3)
         (4)
         (5)
         (6)
         (7) clientService와 refreshToken의 Observable 전달
         (8) 위에서 전달받은 두 값을 파라미터로 사용해 revokeAppleToken 함수 실행
         (9)
         (10) Check whether the element is true or not.
         (11) If apple token has been successfully revoked, wait for 0.7 seconds. (this code is optional)
         (12) Make sure that main scheduler is required for UI updates.
         (13) Stop activity indicator and go to the LoginViewController.
         */
        
        // ⭐️ Each step waits for the completion of the previous step before executing.
        // ⭐️ "flatMap" does not guarantee the order of event emission from the sequence,
        //    whereas "concatMap" ensures the order of event emission.
        self.withdrawalButton.rx.tap.asObservable()  // tap event -> Observable<Void>
        
        // Step 1: Request authorization.
            .concatMap { _ -> Observable<Void> in
                return Observable.create { observer in
                    self.requestAuthorization()
                    observer.onNext(())
                    observer.onCompleted()
                    return Disposables.create()
                }  // Observable<Void> -> Observable<Void>
            }

        // Step 2: Get Apple refresh token.
            .concatMap { _ -> Observable<String> in
                return self.authorizationCode.asObservable()  // Observable<String>
                    .filter { !$0.isEmpty }  // Observable<String> -> Observable<String>
                    .flatMap { authorizationCode -> Observable<String> in
                        return AuthorizationService.shared.getAppleRefreshToken(code: authorizationCode)
                    }  // Observable<String> -> Observable<String>
            }
        
        // Step 3: ...
            .concatMap { clientSecret -> Observable<Void> in
                let clientSecret = Observable.just(clientSecret)  // Observable<String>
                let refreshToken = AuthorizationService.shared.decodedData.asObservable()  // Observable<AppleTokenResponse?>
                    .flatMap { decoddedData -> Observable<String> in
                        return Observable.just((decoddedData?.refresh_token ?? "") as String)
                    }  // Observable<String> -> Observable<String>
                
                return Observable
                    .zip(clientSecret, refreshToken)  // Observable<String>, Observable<String> -> Observable<String>, Observable<String>
                    .map { AuthorizationService.shared.revokeAppleToken(clientSecret: $0, token: $1) }  // Observable<String>, Observable<String> -> Observable<Void>
            }
        
        // Step 4: ...
            .concatMap { _ -> Observable<Void> in
                return AuthorizationService.shared.isAppleTokenRevoked.asObservable()  // Observable<Bool>
                    .filter { $0 == true }  // Observable<Bool> -> Observable<Bool>
                    .flatMap { _ -> Observable<Void> in
                        return Observable.create { observer in
                            observer.onNext(())
                            observer.onCompleted()
                            return Disposables.create()
                        }
                    }  // Observable<Bool> -> Observable<Void>
            }
        
        // Step 5: ...
            .delay(.milliseconds(500), scheduler: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: {
                self.activityIndicator.stopAnimating()
                self.goToLoginViewController()
                print("Memberwhip withdrawal completed!")
            })
            .disposed(by: rx.disposeBag)
    }

    //MARK: - Method used in the main process
    
    // Request authorization for sign-in(or sign-up).
    @discardableResult
    private func requestAuthorization() -> Observable<String> {
        // 1. Create an instance of ASAuthorizationAppleIDRequest.
        let request = AuthorizationService.shared.appleIDRequest
        
        // 2. Preparing to display the sign-in view in LoginViewController.
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self as? ASAuthorizationControllerPresentationContextProviding
        
        // 3. Present the sign-in(or sign-up) view.
        authorizationController.performRequests()
        
        return Observable.just("")
    }
    
    // If login process has successfully done, let's go to the HomeViewController
    private func goToLoginViewController() {
        self.performSegue(withIdentifier: "ToLoginViewController", sender: self)
    }
    
}

//MARK: - Delegate method for Authorization

extension HomeViewController: ASAuthorizationControllerDelegate {

    // When the authorization has completed
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        self.activityIndicator.startAnimating()
        
        // 인증 성공 이후 제공되는 정보
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        
        // 회원탈퇴가 허용되었을 경우 true 이벤트 방출
        // ⭐️ authorizationCode는 일회용이고 인증 후 5분간만 유효함
        if let authorizationCode = appleIDCredential.authorizationCode {
            let code = String(decoding: authorizationCode, as: UTF8.self)
            UserDefaults.standard.setValue(code, forKey: Constant.UserDefaults.authorizationCode)
            self.authorizationCode.onNext(code)
        }
    }

    // When the authorization has failed
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print(error.localizedDescription)
    }

}
