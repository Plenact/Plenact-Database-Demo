// -------------------------------------------------------------------------------------------------
// @file       TokenStore.swift
// @brief      Store, retrieve, and remove the development app token in Keychain
// @details    Wrap Security framework status codes in Swift errors for the calling UI
//
// @notes      Never log token values or place real credentials in source code
//
// @section    Opens
//      Installation-status upload is not integrated yet
//
// -------------------------------------------------------------------------------------------------
import Foundation
import Security


// --------------------------------------- MARK: - Credential Storage --------------------------- //

///
/// Native Keychain access for one development app credential
///
/// @section    Purpose
///     Persist the credential separately from application source and preferences
///
/// @note   The item is accessible while unlocked and is restricted to this device
///

enum TokenStore {

    ///
    /// @fcn        TokenStore.query
    /// @brief      Identify the Keychain item used by this app
    ///
    /// @return     ([String: Any]) item class, service, and account search attributes
    ///
    /// @note   Service and account strings are non-secret lookup labels
    ///
    private static var query: [String: Any] {
        [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.plenact.DatabaseDemo.api",
            kSecAttrAccount as String: "development-app-token"
        ]
    }

    ///
    /// Keychain failure expressed as a Swift error
    ///
    /// @note   Diagnostics contain only the status code, never the credential
    ///
    struct Failure: LocalizedError {

        let status: OSStatus    /* Result returned by the Security framework */

        ///
        /// @fcn        TokenStore.Failure.errorDescription
        /// @brief      Describe the failure without disclosing credential data
        ///
        /// @return     (String?) status-based diagnostic message
        ///
        var errorDescription: String? {
            
            "Keychain operation failed (status \(status))."
        }
    }

    ///
    /// @fcn        TokenStore.save
    /// @brief      Create or replace the saved app token
    /// @details    Attempt an update first; add an item only when no matching item exists
    ///
    /// @param[in]  token       App credential to encode as UTF-8 data
    /// @return     (Void) stores the supplied credential
    /// @throws     Failure when the Keychain update or insertion fails
    ///
    /// @pre        Caller validates token format before saving
    /// @post       On success, the item contains token with unlocked/device-only accessibility
    ///
    /// @note   Saving does not validate the credential with the server
    ///
    static func save(_ token: String) throws {

        let attributes: [String: Any] =
        [
            kSecValueData      as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Preserve the existing item unless it needs to be created.
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound
        {
            var newItem = query
            
            newItem.merge(attributes) { _, new in new }

            let status = SecItemAdd(newItem as CFDictionary, nil)
                                               
            guard status == errSecSuccess else {
                throw Failure(status: status)
            }
            
        } else if updateStatus != errSecSuccess {
            
            throw Failure(status: updateStatus)
        }
    }

    ///
    /// @fcn        TokenStore.load
    /// @brief      Retrieve the saved credential, if present
    /// @details    Request one matching item and decode its stored UTF-8 bytes
    ///
    /// @return     (String?) saved credential, or nil when the item does not exist
    /// @throws     Failure when access fails or stored data cannot be decoded
    ///
    /// @note   Absence is a normal state; access and decoding errors remain explicit
    ///
    static func load() throws -> String? {

        var search                       = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        
        let status = SecItemCopyMatching(search as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            
            throw Failure(status: status)
        }

        guard let data = item as? Data,
              
              let token = String(data: data, encoding: .utf8) else {

            throw Failure(status: errSecDecode)
        }

        return token
    }

    ///
    /// @fcn        TokenStore.delete
    /// @brief      Remove the stored credential
    ///
    /// @return     (Void) leaves no matching item after a successful operation
    /// @throws     Failure when Keychain deletion fails
    ///
    /// @note   Deleting an already-absent item is treated as success
    ///
    static func delete() throws {

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            
            throw Failure(status: status)
        }
    }
}
