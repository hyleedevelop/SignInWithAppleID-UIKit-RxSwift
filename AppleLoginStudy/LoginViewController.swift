//
//  ViewController.swift
//  AppleLoginStudy
//
//  Created by Eric on 2023/06/12.
//

import UIKit
import RxSwift
import RxCocoa
import RxGesture
import NSObject_Rx
import AuthenticationServices

final class LoginViewController: UIViewController {

    //MARK: - IB outlet and action

    @IBOutlet weak var signInButton: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBAction func unwindToHome(_ unwindSegue: UIStoryboardSegue) {
        print("Unwind to LoginViewController.")
    }
    
    //MARK: - Property
    
    private let isSignInAllowed = PublishSubject<Bool>()
    
    //MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupButton()
        self.setupSignInProcess()
    }
    
    //MARK: - Main process
    
    private func setupButton() {
        // Set corner radius of the button.
        self.signInButton.layer.cornerRadius = 5
        self.signInButton.clipsToBounds = true
        
        // Refer to the Main.storyboard for other settings.
    }
    
    private func setupSignInProcess() {
        /*
         (1) Since signInButton is not a button, but a view, it needs tapGesture to act like a button.
         (2) It is required because the event is automatically emitted when binding.
         (3) This emits an observable of false.
         (4) Wait until the element is changed. Current element is false.
         (5) When the authorization has completed, true is emitted.
             In other words, element has been changed and continue returning an observable of true.
         (6) Check whether the element is true or not.
         (7) If sign-in is allowed, wait for 0.5 seconds. (this code is optional)
         (8) Make sure that main scheduler is required for UI updates.
         (9) Stop activity indicator and go to the HomeViewController.
         */
        
        self.signInButton.rx.tapGesture()                                  // (1)
            .when(.recognized)                                             // (2)
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { _ in self.requestAuthorization() }                  // (3)
            .distinctUntilChanged()                                        // (4)
            .flatMap { _ in self.isSignInAllowed }                         // (5)
            .filter { $0 == true }                                         // (6)
            .delay(.milliseconds(500), scheduler: MainScheduler.instance)  // (7)
            .observe(on: MainScheduler.instance)                         // (8)
            .subscribe(onNext: { [weak self] _ in                          // (9)
                guard let self = self else { return }
                print("Login Completed!")
                self.activityIndicator.stopAnimating()
                self.goToHomeViewController()
            })
            .disposed(by: rx.disposeBag)
    }

    //MARK: - Method used in the main process
    
    // Request authorization for sign-in(or sign-up).
    private func requestAuthorization() -> Observable<Bool> {
        // 1. Create an instance of ASAuthorizationAppleIDRequest.
        let request = AuthorizationService.shared.appleIDRequest
        
        // 2. Preparing to display the sign-in view in LoginViewController.
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self as? ASAuthorizationControllerPresentationContextProviding
        
        // 3. Present the sign-in(or sign-up) view.
        authorizationController.performRequests()
        
        return Observable.just(false)
    }
    
    // If login process has successfully done, let's go to the HomeViewController
    private func goToHomeViewController() {
        guard let nextVC = self.storyboard?.instantiateViewController(withIdentifier: "HomeViewController") as? HomeViewController else { return }
        nextVC.modalPresentationStyle = .fullScreen
        self.present(nextVC, animated: true, completion: nil)
    }
    
}

//MARK: - Delegate method for Authorization

extension LoginViewController: ASAuthorizationControllerDelegate {
    
    // When the authorization has completed
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        DispatchQueue.main.async {
            self.activityIndicator.startAnimating()
        }
        
        // 1. 사용자의 정보 가져오기
        
        // authorization: controller로부터 받은 인증 성공 정보에 대한 캡슐화된 객체
        var userIdentifier: String = ""
        
        // 인증 성공 이후 제공되는 정보
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        // (1) 사용자에 대한 고유 식별자 (항상 변하지 않는 값)
        userIdentifier = appleIDCredential.user
        
        // (2) 사용자의 이름
        if let fullName = appleIDCredential.fullName {
            if let givenName = fullName.givenName,
               let familyName = fullName.familyName {
                UserDefaults.standard.setValue("\(givenName) \(familyName)", forKey: Constant.UserDefaults.userName)
                print("user name: \(givenName) \(familyName)")
            }
        }
        
        // (3) 사용자의 이메일
        // (3-1) 최초로 이메일 가져오기
        if let userEmail = appleIDCredential.email {
            UserDefaults.standard.setValue(userEmail, forKey: Constant.UserDefaults.userEmail)
            print("user email: \(userEmail)")
            // (3-2) 두번째 부터 이메일 가져오는 방법
        } else {
            // credential.identityToken은 jwt로 되어있고, 해당 토큰을 decode 후 email에 접근해야함
            guard let tokenString = String(data: appleIDCredential.identityToken ?? Data(), encoding: .utf8) else { return }
            let userEmail = AuthorizationService.shared.decode(jwtToken: tokenString)["email"] as? String ?? ""
            print("user email: \(userEmail)")
        }
        
        // ⭐️ The authorizationCode is one-time use and only valid for 5 minutes after authentication
        if let authorizationCode = appleIDCredential.authorizationCode,
           let identityToken = appleIDCredential.identityToken,
           let authCodeString = String(data: authorizationCode, encoding: .utf8),
           let identifyTokenString = String(data: identityToken, encoding: .utf8) {
            let code = String(decoding: authorizationCode, as: UTF8.self)
            UserDefaults.standard.setValue(code, forKey: Constant.UserDefaults.authorizationCode)
            print(authorizationCode)
            print(identityToken)
            print(authCodeString)
            print(identifyTokenString)
        }
        
        // 2. 사용자의 식별자를 이용해 경우에 따른 로그인 처리
        ASAuthorizationAppleIDProvider()
            .getCredentialState(forUserID: userIdentifier) { credentialState, error in
                switch credentialState {
                case .authorized:
                    // If sign-in is allowed, emit true element.
                    self.isSignInAllowed.onNext(true)
                    print("credentialState: authorized")
                    
                case .revoked:
                    print("credentialState: revoked")
                    
                case .notFound:
                    print("credentialState: notFound")
                    
                default:
                    break
                }
            }
        
    }
    
    // When the authorization has failed
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print(error.localizedDescription)
    }
    
}
