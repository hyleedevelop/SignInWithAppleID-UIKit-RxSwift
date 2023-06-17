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

final class HomeViewController: UIViewController {

    //MARK: - IB outlet
    
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var emailLabel: UILabel!
    @IBOutlet weak var withdrawalButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    //MARK: - Property
    
    // UI binding
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
    
    // Rx
    private let authorizationCode = PublishSubject<String>()
    
    //MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupLabel()
        self.setupButton()
        self.setupMembershipWithdrawalProcess()
    }
    
    //MARK: - Method called by viewDidLoad
    
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
        
        // See Main.storyboard for other settings.
    }
    
    // This is a method implemented using RxSwift to handle the membership withdrawal process.
    private func setupMembershipWithdrawalProcess() {
        /*
         ------------------------------------------------------------------------------------------
         ✅ Each step waits for the completion of the previous step before executing.
         ✅ "flatMap" does not guarantee the order of event emission from the sequence,
             whereas "concatMap" ensures the order of event emission as it does not allow interleaving.
         ✅ In this code, "concatMap" is used to chain observables sequentially.
         ------------------------------------------------------------------------------------------
         */

        // 📌 Step 1: When the button is tapped, request authorization to API server.
        self.withdrawalButton.rx.tap.asObservable()
            .subscribe { [weak self] _ in
                guard let self = self else { return }
                print("\(#function): Step 1")
                self.requestAuthorization()
            }
            .disposed(by: rx.disposeBag)

        // 📌 Step 2: If the user is authorizaed, proceed to get Apple refresh token with authorization code.
        self.authorizationCode.asObservable()
            .filter { !$0.isEmpty }
            .subscribe(onNext: {
                print("\(#function): Step 2")
                AuthorizationService.shared.getAppleRefreshToken(code: $0)
            })
            .disposed(by: rx.disposeBag)

        // 📌 Step 3: If Step 2 has successfully done, we receive some response data from Apple ID server.
        //            Then, we need to decode it to get Apple refresh token which is necessary for revoking the Apple token.
        //            If both client secret and refresh token are ready, we will request revocation of the token.
        let clientSecret = Observable
            .just(UserDefaults.standard.string(forKey: Constant.UserDefaults.clientSecret) ?? "")
        let refreshToken = AuthorizationService.shared.decodedData.asObservable()
            .map { ($0?.refresh_token ?? "") as String }
        
        Observable
            .combineLatest(clientSecret, refreshToken)
            .subscribe(onNext: {
                print("\(#function): Step 3")
                AuthorizationService.shared.revokeAppleToken(clientSecret: $0, token: $1)
            })
            .disposed(by: rx.disposeBag)
        
        // 📌 Step 4: If Apple refresh token has successfully revoked,
        //            display the animating activity indicator and go back to the LoginViewController.
        AuthorizationService.shared.isAppleTokenRevoked.asObservable()
            .filter { $0 == true }
            .delay(.milliseconds(500), scheduler: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                guard let self = self else { return }
                print("\(#function): Step 4")
                self.activityIndicator.stopAnimating()
                self.goToLoginViewController()
                print("Membership withdrawal completed!")
            })
            .disposed(by: rx.disposeBag)
    }

    //MARK: - Child method
    
    // Request authorization for sign-in.
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
    
    // If login process has successfully done, let's go to the HomeViewController.
    private func goToLoginViewController() {
        self.performSegue(withIdentifier: "ToLoginViewController", sender: self)
    }
    
}

//MARK: - Delegate method for Authorization

extension HomeViewController: ASAuthorizationControllerDelegate {

    // When the authorization has completed
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        self.activityIndicator.startAnimating()
        
        // The information provided after successful authentication
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        
        // ⭐️ The authorization code is disposable and valid for only 5 minutes after authentication.
        if let authorizationCode = appleIDCredential.authorizationCode {
            let code = String(decoding: authorizationCode, as: UTF8.self)
            self.authorizationCode.onNext(code)
        }
    }

    // When the authorization has failed
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print(error.localizedDescription)
    }

}
