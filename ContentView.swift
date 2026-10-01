// -------------------------------------------------------------------------------------------------
// @file       ContentView.swift
// @brief      Manage the app token and retrieve Plenact API data
// @details    Exercise the public health endpoint and authenticated database bootstrap
//
// @notes      The health test is public; bootstrap retrieval uses the stored app token
//
// @section    Opens
//      Installation-status upload is not integrated yet
//
// -------------------------------------------------------------------------------------------------
import SwiftUI
import Foundation


// --------------------------------------- MARK: - Models --------------------------------------- //

///
/// Health endpoint response contract
///
/// @section    Purpose
///     Decode the service identifier and health flag returned by health.php
///
private struct HealthResponse: Decodable {

    let service: String    /* Server-provided service identifier */
    let ok:      Bool      /* Health flag reported by the script */
}

///
/// Bootstrap endpoint response contract
///
/// @section    Purpose
///     Decode the database-backed configuration and optional active notice
///
private struct BootstrapResponse: Decodable {

    let configuration: AppConfiguration
    let notice:        BootstrapNotice?
}

///
/// Required configuration returned by bootstrap.php
///
private struct AppConfiguration: Decodable {

    let welcomeMessage: String
    let version:        Int

    enum CodingKeys: String, CodingKey {
        case welcomeMessage = "welcome_message"
        case version
    }
}

///
/// Optional active notice returned by bootstrap.php
///
private struct BootstrapNotice: Decodable {

    let id:      Int        /* Notice identifier   */
    let message: String     /* Notice message text */
}


// --------------------------------------- MARK: - View ----------------------------------------- //

///
/// Foreground presentation and request handling for the API test
///
/// @section    Purpose
///     Keep request feedback visible and prevent repeated taps while a request is pending
///
/// @note   UI state is isolated to the main actor; awaiting networking does not block the UI
///
@MainActor
struct ContentView: View {

    @State private var result          = "Ready to test."               /* Latest request feedback              */
    @State private var isLoading       = false                          /* Request-in-progress flag             */
    @State private var tokenInput      = ""                             /* Token being entered, never logged    */
    @State private var tokenMessage    = ""                             /* Keychain operation feedback          */
    @State private var bootstrapResult = "Database data not loaded."    /* Latest bootstrap response feedback   */

    @State private var tokenIsStored: Bool?                             /* nil means Keychain status is unknown */
    @State private var bootstrapData: BootstrapResponse?


    ///
    /// @fcn        ContentView.body
    /// @brief      Render the test button, progress indicator, and result
    /// @details    The button starts an asynchronous task and is disabled during the request
    ///
    /// @return     (some View) current screen content
    ///
    var body: some View {
        
        VStack(spacing: 20) {
            
            Text("Plenact API Test")
                .font(.title)

            GroupBox("App Token") {

                VStack(alignment: .leading, spacing: 12) {

                    SecureField("64-character app token", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !tokenInput.isEmpty && !tokenInputIsValid {

                        Text("Enter exactly 64 ASCII letters or digits.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {

                        Button("Save Token", action: saveToken)
                            .buttonStyle(.borderedProminent)
                            .disabled(!tokenInputIsValid)

                        Button("Delete Token", role: .destructive, action: deleteToken)
                            .disabled(tokenIsStored != true)
                    }

                    Text(tokenStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !tokenMessage.isEmpty {

                        Text(tokenMessage)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }

            Button("Test API") {
                Task {
                    await testAPI()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if isLoading {
                ProgressView("Contacting server…")
            }

            Text(result)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            GroupBox("Database Bootstrap") {

                VStack(alignment: .leading, spacing: 12) {

                    Button("Load Database Data") {

                        Task {
                            await loadBootstrap()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Text(bootstrapResult)
                        .font(.footnote)
                        .textSelection(.enabled)

                    if let bootstrapData {

                        Text(bootstrapData.configuration.welcomeMessage)
                            .font(.body)
                            .textSelection(.enabled)

                        Text("Configuration version: \(bootstrapData.configuration.version)")
                            .font(.footnote)

                        if let notice = bootstrapData.notice {

                            Text("Notice: \(notice.message)")
                                .font(.footnote)
                                .textSelection(.enabled)

                        } else {
                            Text("No active notice.")
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear(perform: loadTokenStatus)
    }


    ///
    /// @brief      Check token format without converting or normalizing its contents
    /// @return     (Bool) true only for 64 ASCII alphanumeric bytes
    ///
    private var tokenInputIsValid: Bool {

        isValidToken(tokenInput)
    }


    ///
    /// @brief      Check the server's required app-token format
    /// 
    /// @param[in]  token - Candidate token to validate without normalization
    /// @return     (Bool) true only for 64 ASCII alphanumeric bytes
    ///
    private func isValidToken(_ token: String) -> Bool {

        let tokenBytes = token.utf8

        return tokenBytes.count == 64 && tokenBytes.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
        }
    }


    ///
    /// @brief      Describe whether a token is stored without revealing its value
    /// @return     (String) non-sensitive Keychain status for the token panel
    ///
    private var tokenStatusMessage: String {

        guard let tokenIsStored else {
            return "Keychain status unavailable."
        }

        return tokenIsStored
            ? "Token is stored in Keychain. Server validation has not been performed."
            : "No token is stored in Keychain."
    }


    ///
    /// @brief      Read only whether a token exists; never place it in the field
    /// @post       tokenIsStored is true, false, or nil when Keychain access fails
    ///
    private func loadTokenStatus() {

        do {
            tokenIsStored = try TokenStore.load() != nil
            tokenMessage  = ""
        } catch {
            tokenIsStored = nil
            tokenMessage  = "Could not read Keychain status: \(error.localizedDescription)"
        }
    }


    ///
    /// @brief      Save a format-checked app token to Keychain
    /// @note       Local storage does not validate the token with the server
    ///
    private func saveToken() {

        guard tokenInputIsValid else {

            tokenMessage = "Enter exactly 64 ASCII letters or digits."

            return
        }

        do {
            try TokenStore.save(tokenInput)
            
            tokenInput    = ""
            tokenIsStored = true
            tokenMessage  = "Token saved to Keychain. Server validation has not been performed."
        } catch {
            tokenMessage  = "Could not save token: \(error.localizedDescription)"
        }
    }


    ///
    /// @brief      Delete the stored app token from Keychain
    ///
    private func deleteToken() {

        do {
            try TokenStore.delete()

            tokenIsStored = false
            tokenMessage  = "Stored token deleted from Keychain."

        } catch {
            tokenMessage = "Could not delete token: \(error.localizedDescription)"
        }
    }


    ///
    /// @fcn        ContentView.loadBootstrap
    /// @brief      Fetch authenticated configuration and the optional active notice
    /// @details    Load the app token from Keychain, require HTTP 200, and decode the response
    ///
    /// @return     (Void) updates bootstrap data or a safe failure message
    /// @post       isLoading is false and no credential is included in UI feedback
    ///
    private func loadBootstrap() async {

        isLoading       = true
        bootstrapData   = nil
        bootstrapResult = "Loading database data…"

        defer { isLoading = false }

        let token: String

        do {
            guard let storedToken = try TokenStore.load() else {

                bootstrapResult = "No app token is stored. Save the app token before loading database data."
                
                return
            }

            guard isValidToken(storedToken) else {

                bootstrapResult = "The stored token has an invalid format. Replace it before continuing."
               
                return
            }

            token = storedToken

        } catch {

            bootstrapResult = "Could not read the app token from Keychain: \(error.localizedDescription)"
           
            return
        }

        guard let url = URL(

            string: "https://plenact.com/api-dev/bootstrap.php"

        ) else {

            bootstrapResult = "Invalid bootstrap API URL."

            return
        }

        var request             = URLRequest(url: url)
        request.httpMethod      = "GET"
        request.timeoutInterval = 20
        request.cachePolicy     = .reloadIgnoringLocalCacheData

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {

                bootstrapResult = "Failed: bootstrap response was not HTTP."

                return
            }

            switch httpResponse.statusCode {

                case 200:
                    break

                case 401:

                    bootstrapResult = "Authentication failed (HTTP 401). The stored app token was rejected."
                    
                    return

                case 403:

                    bootstrapResult = "Access denied (HTTP 403). This endpoint requires the app token."
                    
                    return

                case 500...599:

                    bootstrapResult = "Server error (HTTP \(httpResponse.statusCode)). Try again later."
                    
                    return

                default:

                    bootstrapResult = "Bootstrap request failed with HTTP \(httpResponse.statusCode)."
                    
                    return

            }

            bootstrapData   = try JSONDecoder().decode(BootstrapResponse.self, from: data)
            bootstrapResult = "Database data loaded successfully."

        } catch is DecodingError {

            bootstrapResult = "Could not decode the bootstrap response. Its JSON does not match the expected format."
       
        } catch let error as URLError {

            switch error.code {

                case .notConnectedToInternet, .networkConnectionLost:

                    bootstrapResult = "Network unavailable. Check the connection and try again."
                
                case .timedOut:
                 
                    bootstrapResult = "The bootstrap request timed out. Try again."
               
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
               
                    bootstrapResult = "Could not reach the API host. Check the connection and try again."
              
                default:
               
                    bootstrapResult = "Network request failed: \(error.localizedDescription)"
            }
        } catch {

            bootstrapResult = "Bootstrap request failed: \(error.localizedDescription)"
        }
    }


    ///
    /// @fcn        ContentView.testAPI
    /// @brief      Fetch and decode the public health response
    /// @details    Require HTTP 200 before decoding; display transport, HTTP, and decoding failures
    ///
    /// @return     (Void) updates the view state in place
    ///
    /// @pre        Invoked on the main actor
    /// @post       isLoading is false and result describes the completed attempt
    ///
    /// @note   This request contains no credentials and does not query the database
    ///
    private func testAPI() async {

        isLoading = true                       /* Begin request feedback */
        result    = "Waiting for response…"
        
        defer { isLoading = false }            /* Restore controls on every exit path */

        guard let url = URL(
            
            string: "https://plenact.com/api-dev/health.php"
            
        ) else {
            
            result = "Invalid API URL."
            
            return
        }

        // Configure an explicit foreground GET request.
        var request = URLRequest(url: url)
        
        request.httpMethod      = "GET"
        request.timeoutInterval = 20
        request.cachePolicy     = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                
                result = "Failed: response was not HTTP."
                
                return
            }

            // A completed transfer can still carry an HTTP error.
            guard httpResponse.statusCode == 200 else {
                
                result = "Server returned HTTP \(httpResponse.statusCode)."
                
                return
            }

            let health = try JSONDecoder().decode(HealthResponse.self, from: data)

            if health.ok {
                
                result = "Success: \(health.service) responded."
                
            } else {
                
                result = "Server responded, but reported ok = false."
                
            }
        } catch {
            result = "Request failed: \(error.localizedDescription)"
        }
    }
}

// --------------------------------------- MARK: - Preview -------------------------------------- //

#Preview {
    ContentView()
}
