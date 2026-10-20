import Cocoa
import FlutterMacOS
import CryptoTokenKit
import Security
import CryptoKit

class MainFlutterWindow: NSWindow {
  private static let webClassID = "it.giancarloezza.CIEID.FlutterPrototype.WebToken"
  private static let webPublicCache = "cie.prototype.web.public-certificates.v1"
  private var webChannel: FlutterMethodChannel?
  private var fileChannel: FlutterMethodChannel?
  private var applicationChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let files = FlutterMethodChannel(name: "cie.id/file-dialogs", binaryMessenger: flutterViewController.engine.binaryMessenger)
    fileChannel = files
    files.setMethodCallHandler { call, result in
      if call.method == "desktopDirectory" {
        result(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path)
      } else { result(FlutterMethodNotImplemented) }
    }
    let application = FlutterMethodChannel(name: "cie.id/application", binaryMessenger: flutterViewController.engine.binaryMessenger)
    applicationChannel = application
    application.setMethodCallHandler { call, result in
      if call.method == "systemLanguage" {
        result(AppDelegate.systemLanguage())
      } else if call.method == "setTheme", let theme = call.arguments as? String, ["system", "light", "dark"].contains(theme) {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
        result(nil)
      } else if call.method == "setLanguage", let language = call.arguments as? String, ["it", "en"].contains(language) {
        (NSApp.delegate as? AppDelegate)?.applyLanguage(language)
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    MainFlutterWindow.restoreWebCertificates()
    let channel = FlutterMethodChannel(name: "cie.prototype/web", binaryMessenger: flutterViewController.engine.binaryMessenger)
    webChannel = channel
    channel.setMethodCallHandler { call, result in
      let classID = "it.giancarloezza.CIEID.FlutterPrototype.WebToken"
      if call.method == "activateComponent" {
        // Fixed command and our embedded extension only. No path, identifier,
        // certificate or credential is accepted from the Flutter caller.
        guard call.arguments == nil,
              let plugins = Bundle.main.builtInPlugInsURL,
              let bundle = Bundle(url: plugins.appendingPathComponent("CIEPrototypeToken.appex")),
              bundle.bundleIdentifier == classID,
              let ext = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
              ext["NSExtensionPointIdentifier"] as? String == "com.apple.ctk-tokens" else {
          result(["ok": false, "code": "web_component_missing"]); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let activated = WebComponentActivation.activate(bundled: true)
          let election = WebComponentActivation.election()
          DispatchQueue.main.async {
            let driverPresent = TKTokenDriver.Configuration.driverConfigurations[classID] != nil
            let state = WebComponentActivation.state(bundled: true, driverPresent: driverPresent, election: election)
            result(["ok": activated && state == "enabled", "activationState": state,
              "code": activated && state == "enabled" ? "web_component_enabled" : "web_component_activation_failed"])
          }
        }
        return
      }
      if call.method == "openSystemSettings" {
        let target: String
        if #available(macOS 13.0, *) {
          target = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        } else {
          target = "x-apple.systempreferences:com.apple.preferences.extensions"
        }
        let opened = NSWorkspace.shared.open(URL(string: target)!)
        result(opened || NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")))
        return
      }
      if call.method == "test" {
        MainFlutterWindow.restoreWebCertificates()
        guard let args = call.arguments as? [String: String], let id = args["card"],
              id.range(of: "^[A-Za-z0-9]{1,63}$", options: .regularExpression) != nil else {
          result(FlutterError(code: "web_invalid_id", message: "Identificativo CIE non valido.", details: nil)); return
        }
        let saved = UserDefaults.standard.dictionary(forKey: MainFlutterWindow.webPublicCache) as? [String: Data] ?? [:]
        guard let der = saved[id] else {
          result(FlutterError(code: "web_not_configured", message: "Configura prima il certificato della CIE.", details: nil)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let outcome = MainFlutterWindow.testWebToken(id: id, der: der)
          DispatchQueue.main.async { result(outcome) }
        }
        return
      }
      // Status/removal also work when the extension is absent or disabled.
      // Observe references only: never test/sign or request a PIN in the monitor.
      if call.method == "status" {
        let saved = UserDefaults.standard.dictionary(forKey: MainFlutterWindow.webPublicCache) as? [String: Data] ?? [:]
        var published = [String](), observed = [String](), certificateHex = [String: String]()
        for (id, der) in saved where id.range(of: "^[A-Za-z0-9]{1,63}$", options: .regularExpression) != nil && !der.isEmpty && der.count <= 8192 {
          certificateHex[id] = der.map { String(format: "%02x", $0) }.joined()
          if let file = MainFlutterWindow.publicCertificateURL(id: id), let bytes = try? Data(contentsOf: file), bytes == der { published.append(id) }
          let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(id.utf8),
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitAll, kSecUseAuthenticationUI: kSecUseAuthenticationUIFail]
          var values: CFTypeRef?
          if SecItemCopyMatching(query as CFDictionary, &values) == errSecSuccess,
             let keys = values as? [[CFString: Any]], keys.contains(where: { ($0[kSecAttrTokenID] as? String)?.hasPrefix(classID + ":") == true }) { observed.append(id) }
        }
        let driverPresent = TKTokenDriver.Configuration.driverConfigurations[classID] != nil
        let bundled = Bundle.main.builtInPlugInsURL.map {
          FileManager.default.fileExists(atPath: $0.appendingPathComponent("CIEPrototypeToken.appex").path)
        } ?? false
        let certificates = certificateHex, publishedIDs = published.sorted(), observedIDs = observed.sorted()
        DispatchQueue.global(qos: .utility).async {
          let state = WebComponentActivation.state(bundled: bundled, driverPresent: driverPresent,
            election: bundled ? WebComponentActivation.election() : nil)
          let available = state == "enabled" || (state == "unknown" && driverPresent)
          let needsSettings = state == "disabled" || state == "unavailable"
          DispatchQueue.main.async {
            result(["available": available, "activationState": state,
              "canActivateComponent": needsSettings && bundled,
              "canOpenSystemSettings": needsSettings, "certificateHexByCard": certificates,
              "configuredCards": Array(certificates.keys).sorted(), "publishedCards": publishedIDs,
              "observedCards": available ? observedIDs : []])
          }
        }
        return
      }
      guard let args = call.arguments as? [String: String], let id = args["card"],
            id.range(of: "^[A-Za-z0-9]{1,63}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "web_invalid_id", message: "Identificativo CIE non valido.", details: nil)); return
      }
      if call.method == "forget" {
        TKTokenDriver.Configuration.driverConfigurations[classID]?.removeTokenConfiguration(for: id)
        if let file = MainFlutterWindow.publicCertificateURL(id: id), FileManager.default.fileExists(atPath: file.path) {
          do { try FileManager.default.removeItem(at: file) } catch {
            result(FlutterError(code: "web_remove_failed", message: "Impossibile rimuovere la configurazione pubblica di questa applicazione.", details: nil)); return
          }
        }
        var saved = UserDefaults.standard.dictionary(forKey: MainFlutterWindow.webPublicCache) as? [String: Data] ?? [:]
        saved.removeValue(forKey: id)
        UserDefaults.standard.set(saved, forKey: MainFlutterWindow.webPublicCache)
        result(true); return
      }
      guard let driver = TKTokenDriver.Configuration.driverConfigurations[classID] else {
        result(FlutterError(code: "web_extension_unavailable", message: "Il componente per l’accesso ai siti non è disponibile. L’abbinamento per firmare è conservato; completa la configurazione senza reinserire il PIN.", details: nil)); return
      }
      guard call.method == "configure", let hex = args["certificateHex"],
            hex.count <= 16384, hex.count % 2 == 0,
            hex.range(of: "^[a-f0-9]+$", options: .regularExpression) != nil else {
        result(FlutterError(code: "web_invalid_certificate", message: "Certificato non valido.", details: nil)); return
      }
      var bytes = [UInt8](); bytes.reserveCapacity(hex.count / 2)
      var index = hex.startIndex
      while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else { result(false); return }
        bytes.append(byte); index = next
      }
      let der = Data(bytes)
      guard let certificate = SecCertificateCreateWithData(nil, der as CFData), let key = SecCertificateCopyKey(certificate),
            let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
            attrs[kSecAttrKeyType] as? String == kSecAttrKeyTypeRSA as String,
            attrs[kSecAttrKeySizeInBits] as? Int == 2048 else {
        result(FlutterError(code: "web_invalid_certificate", message: "È richiesto il certificato RSA della CIE.", details: nil)); return
      }
      var saved = UserDefaults.standard.dictionary(forKey: MainFlutterWindow.webPublicCache) as? [String: Data] ?? [:]
      saved[id] = der
      UserDefaults.standard.set(saved, forKey: MainFlutterWindow.webPublicCache)
      guard MainFlutterWindow.publishWebCertificate(driver: driver, id: id, der: der, certificate: certificate) else {
        result(FlutterError(code: "web_public_store_unavailable", message: "Il certificato pubblico è salvato nell’app, ma il contenitore condiviso non è disponibile. Verifica la firma dei componenti; non occorre ripetere il PIN.", details: nil)); return
      }
      result(true)
    }

    super.awakeFromNib()
    // Fixed logical content size; closing, moving and minimizing stay available.
    self.isRestorable = false
    self.styleMask.remove(.resizable)
    self.collectionBehavior.remove(.fullScreenPrimary)
    self.collectionBehavior.insert(.fullScreenNone)
    let contentSize = NSSize(width: 1080, height: 760)
    self.setContentSize(contentSize)
    self.contentMinSize = contentSize
    self.contentMaxSize = contentSize
    self.standardWindowButton(.zoomButton)?.isEnabled = false
    self.center()
    self.title = "CIE ID"
    self.titleVisibility = .hidden
    if let close = self.standardWindowButton(.closeButton), let titlebar = close.superview, let content = self.contentView {
      let label = NSTextField(labelWithString: self.title)
      label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
      label.alignment = .center
      label.translatesAutoresizingMaskIntoConstraints = false
      label.setAccessibilityIdentifier("CIEWindowTitle")
      titlebar.addSubview(label)
      NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: close.centerYAnchor)
      ])
    }
  }
  private static func publicCertificateURL(id: String) -> URL? {
    guard let plugins = Bundle.main.builtInPlugInsURL,
          let bundle = Bundle(url: plugins.appendingPathComponent("CIEPrototypeToken.appex")),
          let group = bundle.object(forInfoDictionaryKey: "CIEWebPublicAppGroup") as? String,
          group.range(of: "^[A-Z0-9]{10}\\.it\\.giancarloezza\\.CIEID\\.FlutterPrototype\\.web-public$", options: .regularExpression) != nil,
          let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
    let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    return root.appendingPathComponent("public-certificates", isDirectory: true).appendingPathComponent(name + ".der")
  }
  private static func publishWebCertificate(driver: TKTokenDriver.Configuration, id: String, der: Data, certificate: SecCertificate) -> Bool {
    // Public data only; the extension binds it to the physical card's SOD.
    // Do not create configured software tokens or inject keys into a live token.
    guard let file = publicCertificateURL(id: id) else { return false }
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try der.write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      return true
    } catch { return false }
  }
  private static func restoreWebCertificates() {
    guard let driver = TKTokenDriver.Configuration.driverConfigurations[webClassID],
          let saved = UserDefaults.standard.dictionary(forKey: webPublicCache) as? [String: Data], saved.count <= 256 else { return }
    let migration = "cie.prototype.web.physical-token-migration.v1"
    if !UserDefaults.standard.bool(forKey: migration) {
      // Remove only the prototype's old synthetic token registrations; retain
      // authenticated public DER so no PIN is needed to publish it again.
      for id in saved.keys { driver.removeTokenConfiguration(for: id) }
      UserDefaults.standard.set(true, forKey: migration)
    }
    for (id, der) in saved {
      guard id.range(of: "^[A-Za-z0-9]{1,63}$", options: .regularExpression) != nil,
            !der.isEmpty, der.count <= 8192,
            let certificate = SecCertificateCreateWithData(nil, der as CFData),
            let key = SecCertificateCopyKey(certificate),
            let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
            attrs[kSecAttrKeyType] as? String == kSecAttrKeyTypeRSA as String,
            attrs[kSecAttrKeySizeInBits] as? Int == 2048 else { continue }
      _ = publishWebCertificate(driver: driver, id: id, der: der, certificate: certificate)
    }
  }
  private static func webFailureReason(_ error: CFError?) -> String {
    // Only known fixed provider messages may cross into this UI. Never echo
    // arbitrary userInfo containing token IDs, certificates or other data.
    guard let error = error else { return "" }
    let text = CFErrorCopyDescription(error) as String
    let reasons = [
      "La richiesta di firma è cambiata.",
      "La firma della richiesta locale non è riuscita dopo l’autenticazione.",
      "La sessione della carta è cambiata.",
      "Sessione di autenticazione terminata.",
      "La carta ha rifiutato il PIN.",
      "PIN bloccato.",
      "La sessione CIE non ha completato l’autenticazione o il controllo del certificato.",
      "La carta è stata rimossa."
    ]
    return reasons.first(where: { text.contains($0) }) ?? "La causa non è ancora distinguibile dal codice restituito dal sistema."
  }
  private static func testWebToken(id: String, der: Data) -> [String: Any] {
    let failed: [String: Any] = ["ok": false, "code": "web_system_test_failed", "message": "Prova CryptoTokenKit non riuscita. Consulta la diagnostica del componente. Nessun tentativo automatico viene eseguito."]
    let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(id.utf8),
      kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
      kSecMatchLimit: kSecMatchLimitOne, kSecReturnRef: true]
    var item: CFTypeRef?
    let lookup = SecItemCopyMatching(query as CFDictionary, &item)
    guard lookup == errSecSuccess, let item = item,
          CFGetTypeID(item) == SecKeyGetTypeID() else {
      return ["ok": false, "code": "web_system_test_failed", "nativeCode": lookup,
        "message": "macOS non ha reso disponibile la chiave di questa applicazione (codice \(lookup)). La prova si è fermata prima del PIN; non occorre riconfigurare il certificato."]
    }
    let key = item as! SecKey
    guard let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
          let token = attrs[kSecAttrTokenID] as? String,
          token.contains("it.giancarloezza.CIEID.FlutterPrototype.WebToken"),
          let certificate = SecCertificateCreateWithData(nil, der as CFData),
          let publicKey = SecCertificateCopyKey(certificate) else { return failed }
    let challenge = Data("CIE ID Flutter local web-authentication challenge v1".utf8)
    let digest = Data(SHA256.hash(data: challenge))
    var error: Unmanaged<CFError>?
    defer { if let error = error { _ = error.takeRetainedValue() } }
    // One explicit local signature through the OS token; PIN entry is owned by
    // CryptoTokenKit. No document, external site, PIN parameter or automatic retry.
    guard let signature = SecKeyCreateSignature(key, .rsaSignatureDigestPKCS1v15SHA256, digest as CFData, &error) else {
      let code = error.map { CFErrorGetCode($0.takeUnretainedValue()) } ?? 0
      return ["ok": false, "code": "web_system_test_failed", "nativeCode": code,
        "message": "CryptoTokenKit non ha completato la firma locale (codice \(code)). \(webFailureReason(error?.takeUnretainedValue())) Nessun tentativo automatico viene eseguito."]
    }
    guard SecKeyVerifySignature(publicKey, .rsaSignatureDigestPKCS1v15SHA256, digest as CFData, signature, &error) else { return failed }
    return ["ok": true, "message": "Firma della richiesta locale verificata tramite CryptoTokenKit. Il login a un sito resta una prova separata."]
  }
}
