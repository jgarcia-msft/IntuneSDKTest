import IntuneMAMSwift
import MSAL
import OSLog
import SwiftUI
import UIKit

@MainActor
final class AuthenticationService: ObservableObject {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(username: String, accountID: String)
        case failed(String)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var enrollmentID: String?

    private var msalApplication: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?
    private let scopes = ["User.Read"]
    private let enrollmentDelegate = EnrollmentDelegate()

    init() {
        // The delegate receives asynchronous enrollment results from Intune.
        // Swift imports the Objective-C status callback as enrollmentRequest(with:).
        IntuneMAMEnrollmentManager.instance().delegate = enrollmentDelegate
        configureMSAL()
        restoreCachedAccount()
        refreshEnrollment()
    }

    var isConfigured: Bool { msalApplication != nil }

    // MSAL owns interactive sign-in and returns an access token plus the account
    // metadata needed by Intune. The view controller is the host for the MSAL web UI.
    func signIn() {
        guard let msalApplication else { return }
        guard let presenter = UIApplication.shared.topViewController else {
            state = .failed("No presentation window is available for sign-in.")
            return
        }

        state = .signingIn
        let webParameters = MSALWebviewParameters(authPresentationViewController: presenter)
        webParameters.webviewType = .wkWebView
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParameters)
        parameters.promptType = .selectAccount

        msalApplication.acquireToken(with: parameters) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard let result else {
                    self.state = .failed("MSAL returned no authentication result.")
                    return
                }

                self.currentAccount = result.account
                // Intune uses the Entra object ID from the tenant profile as its
                // account identity. This links the authenticated user to MAM policy.
                guard let accountID = result.tenantProfile.identifier else {
                    self.state = .failed("MSAL did not return an Entra account identifier.")
                    return
                }
                self.state = .signedIn(
                    username: result.account.username ?? "Microsoft account",
                    accountID: accountID
                )
                self.registerWithIntune(accountID: accountID)
            }
        }
    }

    // Intune must be deregistered before MSAL removes its account tokens. The SDK
    // needs those tokens to complete unenrollment and optional selective wipe.
    func signOut(deleteLocalData: @escaping () -> Void) {
        guard let msalApplication, let currentAccount else {
            state = .signedOut
            return
        }

        if case let .signedIn(_, accountID) = state {
            IntuneMAMEnrollmentManager.instance()
                .deRegisterAndUnenrollAccountId(accountID, withWipe: true)
        }
        deleteLocalData()

        guard let presenter = UIApplication.shared.topViewController else {
            state = .failed("No presentation window is available for sign-out.")
            return
        }
        let webParameters = MSALWebviewParameters(authPresentationViewController: presenter)
        let parameters = MSALSignoutParameters(webviewParameters: webParameters)
        parameters.signoutFromBrowser = false

        msalApplication.signout(with: currentAccount, signoutParameters: parameters) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.state = .failed(error.localizedDescription)
                } else if success {
                    self.currentAccount = nil
                    self.enrollmentID = nil
                    self.state = .signedOut
                } else {
                    self.state = .failed("MSAL sign-out was not completed.")
                }
            }
        }
    }

    func refreshEnrollment() {
        // Enrollment is asynchronous. Querying this property when the account
        // screen opens shows the current Intune state instead of a stale snapshot.
        enrollmentID = IntuneMAMEnrollmentManager.instance().enrolledAccountId()
    }

    func showIntuneDiagnosticConsole() {
        IntuneMAMDiagnosticConsole.display()
    }

    private func configureMSAL() {
        guard let settings = Bundle.main.object(forInfoDictionaryKey: "IntuneMAMSettings") as? [String: Any],
              let clientID = settings["ADALClientId"] as? String,
              let authorityString = settings["ADALAuthority"] as? String,
              let redirectURI = settings["ADALRedirectUri"] as? String,
              !clientID.contains("YOUR_"), !authorityString.contains("YOUR_") else {
            state = .failed("Set YOUR_CLIENT_ID and YOUR_TENANT_ID in Info.plist first.")
            return
        }

        do {
            guard let authorityURL = URL(string: authorityString) else { throw ConfigurationError.invalidAuthority }
            let authority = try MSALAADAuthority(url: authorityURL)
            let expandedRedirectURI = redirectURI.replacingOccurrences(
                of: "$(PRODUCT_BUNDLE_IDENTIFIER)",
                with: Bundle.main.bundleIdentifier ?? ""
            )
            let configuration = MSALPublicClientApplicationConfig(
                clientId: clientID,
                redirectUri: expandedRedirectURI,
                authority: authority
            )
            // "protapp" tells Entra/MSAL that Intune App Protection Conditional
            // Access remediation may be required before a protected token is issued.
            configuration.clientApplicationCapabilities = ["protapp"]
            msalApplication = try MSALPublicClientApplication(configuration: configuration)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func restoreCachedAccount() {
        guard let msalApplication else { return }
        do {
            guard let account = try msalApplication.allAccounts().first else { return }
            currentAccount = account
            let accountID = enrollmentID ?? account.homeAccountId?.objectId
            if let accountID {
                state = .signedIn(username: account.username ?? "Microsoft account", accountID: accountID)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func registerWithIntune(accountID: String) {
        // This starts Intune MAM enrollment. Policy is applied asynchronously;
        // the SDK may display a restart prompt when the first policy is received.
        IntuneMAMEnrollmentManager.instance().registerAndEnrollAccountId(accountID)
        refreshEnrollment()
    }

    private enum ConfigurationError: LocalizedError {
        case invalidAuthority
        var errorDescription: String? { "The configured authority URL is invalid." }
    }
}

private final class EnrollmentDelegate: NSObject, IntuneMAMEnrollmentDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "IntuneSDKTest",
        category: "IntuneMAM"
    )

    func enrollmentRequest(with status: IntuneMAMEnrollmentStatus) {
        logger.info("Enrollment status: \(status.statusCode), error: \(status.errorString ?? "none", privacy: .public)")
    }

    func policyRequest(with status: IntuneMAMEnrollmentStatus) {
        logger.info("Policy status: \(status.statusCode), error: \(status.errorString ?? "none", privacy: .public)")
    }

    func unenrollRequest(with status: IntuneMAMEnrollmentStatus) {
        logger.info("Unenrollment status: \(status.statusCode), error: \(status.errorString ?? "none", privacy: .public)")
    }
}

private extension UIApplication {
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
