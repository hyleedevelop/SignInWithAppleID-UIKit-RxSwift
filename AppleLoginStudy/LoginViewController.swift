//
//  ViewController.swift
//  AppleLoginStudy
//
//  Created by Eric on 2023/06/12.
//

import UIKit
import RxSwift
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
    
    // Rx
    private let isSignInAllowed = PublishSubject<Bool>()
    
    //MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupButton()
        self.setupSignInProcess()
    }
    
    //MARK: - Method called by viewDidLoad
    
    private func setupButton() {
        // Set corner radius of the view.
        // (we call it as "button", but it is basically UIView)
        self.signInButton.layer.cornerRadius = 5
        self.signInButton.clipsToBounds = true
        
        // Refer to the Main.storyboard for other settings.
    }
    
    private func setupSignInProcess() {
        /*
         ------------------------------------------------------------------------------------------
         ✅ Since signInButton is not a button, but a view, it needs tapGesture to act like a button.
         ✅ "when" operator is required as the event is automatically emitted at the time of binding.
         ------------------------------------------------------------------------------------------
         */
        
        // 📌 Step 1: When the button is tapped, request authorization to API server.
        self.signInButton.rx.tapGesture()
            .when(.recognized)
            .subscribe(onNext: { [weak self] _ in
                guard let self = self else { return }
                print("\(#function): Step 1")
                self.requestAuthorization()
            })
            .disposed(by: rx.disposeBag)
        
        // 📌 Step 2: If step 1 has successfully done and "true" is emitted,
        //            display the animating activity indicator to the user and go to the HomeViewController.
        self.isSignInAllowed.asObservable()
            .filter { $0 == true }
            .delay(.milliseconds(500), scheduler: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                guard let self = self else { return }
                print("\(#function): Step 2")
                self.activityIndicator.stopAnimating()
                self.goToHomeViewController()
                print("Sign-in Completed!")
            })
            .disposed(by: rx.disposeBag)
    }

    //MARK: - Child method
    
    // Request authorization for sign-in or sign-up.
    private func requestAuthorization() {
        // Create an instance of ASAuthorizationAppleIDRequest.
        let request = AuthorizationService.shared.appleIDRequest
        
        // Preparing to display the sign-in view in LoginViewController.
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self as? ASAuthorizationControllerPresentationContextProviding
        
        // Present the sign-in(or sign-up) view.
        authorizationController.performRequests()
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
        
        // 📌 Step 1: After success of authorization, retrieve user information from Apple ID Server.
        // (https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/authenticating_users_with_sign_in_with_apple#3383773)
        
        // "appleIdCredential" contains user information.
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        
        // Info #1: Identifier (unique to the user and never changing)
        let userIdentifier = appleIDCredential.user
        
        // Info #2: Name
        if let fullName = appleIDCredential.fullName {
            if let givenName = fullName.givenName,
               let familyName = fullName.familyName {
                UserDefaults.standard.setValue("\(givenName) \(familyName)", forKey: Constant.UserDefaults.userName)
                print("user name: \(givenName) \(familyName)")
            }
        }
        
        // Info #3: Email
        if let userEmail = appleIDCredential.email {
            UserDefaults.standard.setValue(userEmail, forKey: Constant.UserDefaults.userEmail)
            print("user email: \(userEmail)")
        } else {
            guard let tokenString = String(data: appleIDCredential.identityToken ?? Data(), encoding: .utf8) else { return }
            let userEmail = AuthorizationService.shared.decode(jwtToken: tokenString)["email"] as? String ?? ""
            print("user email: \(userEmail)")
        }
        
        // ⭐️ The authorization code is disposable and valid for only 5 minutes after authentication.
        if let authorizationCode = appleIDCredential.authorizationCode,
           let identityToken = appleIDCredential.identityToken,
           let authCodeString = String(data: authorizationCode, encoding: .utf8),
           let identifyTokenString = String(data: identityToken, encoding: .utf8) {
            print("🗝 authrizationCode - \(authCodeString)")
            print("🗝 identifyToken - \(identifyTokenString)")
        }
        
        // 📌 Step 2: Returns the credential state for the given user to handle in a completion handler.
        // (https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/verifying_a_user#3383776)
        ASAuthorizationAppleIDProvider()
            .getCredentialState(forUserID: userIdentifier) { credentialState, error in
                switch credentialState {
                case .authorized:
                    // Create and save client secret (JWT) in UserDefaults for later token revocation.
                    AuthorizationService.shared.createJWT()
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
