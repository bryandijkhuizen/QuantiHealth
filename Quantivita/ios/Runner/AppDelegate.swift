import Flutter
import CoreLocation
import Foundation
import HealthKit
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let healthStore = HKHealthStore()
  private var stravaAuthResult: FlutterResult?
  private var pendingStravaClientId: String?
  private var pendingStravaClientSecret: String?
  private var progressaAuthResult: FlutterResult?
  private var pendingProgressaState: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    configureHealthKitChannel()
    configureStravaChannel()
    configureProgressaChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if handleProgressaCallback(url) {
      return true
    }

    if handleStravaCallback(url) {
      return true
    }

    return super.application(app, open: url, options: options)
  }

  private func configureHealthKitChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "quantivita/healthkit",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "HealthKit bridge is unavailable.", details: nil))
        return
      }

      switch call.method {
      case "requestAuthorization":
        self.requestHealthAuthorization(result: result)
      case "exportMergedWorkout":
        self.exportMergedWorkout(arguments: call.arguments, result: result)
      case "createStravaTcx":
        self.createStravaTcx(arguments: call.arguments, result: result)
      case "loadWorkoutHistory":
        self.loadWorkoutHistory(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureStravaChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "quantivita/strava",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Strava bridge is unavailable.", details: nil))
        return
      }

      switch call.method {
      case "authorizeStrava":
        self.authorizeStrava(arguments: call.arguments, result: result)
      case "saveStravaTokens":
        self.saveStravaTokens(arguments: call.arguments, result: result)
      case "loadStravaTokens":
        self.loadStravaTokens(result: result)
      case "clearStravaTokens":
        self.clearStravaTokens(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureProgressaChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "quantivita/progressa",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Progressa bridge is unavailable.", details: nil))
        return
      }

      switch call.method {
      case "authorizeProgressa":
        self.authorizeProgressa(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func authorizeProgressa(arguments: Any?, result: @escaping FlutterResult) {
    guard progressaAuthResult == nil else {
      result(FlutterError(code: "auth_in_progress", message: "Progressa authorization is already in progress.", details: nil))
      return
    }

    guard let payload = arguments as? [String: Any],
          let authUrl = payload["authUrl"] as? String,
          let fallbackAuthUrl = payload["fallbackAuthUrl"] as? String,
          let state = payload["state"] as? String,
          let url = URL(string: fallbackAuthUrl.isEmpty ? authUrl : fallbackAuthUrl),
          !state.isEmpty else {
      result(FlutterError(code: "invalid_config", message: "Progressa authorization configuration is incomplete.", details: nil))
      return
    }

    progressaAuthResult = result
    pendingProgressaState = state
    UIApplication.shared.open(url) { [weak self] opened in
      guard let self else { return }
      if !opened {
        if let appUrl = URL(string: authUrl) {
          UIApplication.shared.open(appUrl) { [weak self] fallbackOpened in
            guard let self else { return }
            if !fallbackOpened {
              self.progressaAuthResult = nil
              self.pendingProgressaState = nil
              result(FlutterError(code: "auth_open_failed", message: "Could not open Progressa authorization.", details: nil))
            }
          }
          return
        }

        self.progressaAuthResult = nil
        self.pendingProgressaState = nil
        result(FlutterError(code: "auth_open_failed", message: "Could not open Progressa authorization.", details: nil))
      }
    }
  }

  private func handleProgressaCallback(_ url: URL) -> Bool {
    guard url.scheme == "quantivita",
          url.host == "quantivita.app",
          url.path == "/progressa-auth",
          let result = progressaAuthResult else {
      return false
    }

    progressaAuthResult = nil
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryItems = components?.queryItems ?? []

    if let error = queryItems.first(where: { $0.name == "error" })?.value {
      pendingProgressaState = nil
      result(FlutterError(code: "auth_denied", message: "Progressa authorization failed: \(error)", details: nil))
      return true
    }

    let state = queryItems.first(where: { $0.name == "state" })?.value
    guard state == pendingProgressaState else {
      pendingProgressaState = nil
      result(FlutterError(code: "state_mismatch", message: "Progressa authorization state did not match.", details: nil))
      return true
    }

    guard let code = queryItems.first(where: { $0.name == "code" })?.value,
          !code.isEmpty else {
      pendingProgressaState = nil
      result(FlutterError(code: "missing_code", message: "Progressa did not return an authorization code.", details: nil))
      return true
    }

    pendingProgressaState = nil
    result(["code": code])
    return true
  }

  private func authorizeStrava(arguments: Any?, result: @escaping FlutterResult) {
    guard stravaAuthResult == nil else {
      result(FlutterError(code: "auth_in_progress", message: "Strava authorization is already in progress.", details: nil))
      return
    }

    guard let payload = arguments as? [String: Any],
          let clientId = payload["clientId"] as? String,
          let clientSecret = payload["clientSecret"] as? String,
          let redirectUri = payload["redirectUri"] as? String,
          !clientId.isEmpty,
          !clientSecret.isEmpty,
          !redirectUri.isEmpty else {
      result(FlutterError(code: "invalid_config", message: "Strava OAuth configuration is incomplete.", details: nil))
      return
    }

    var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")
    components?.queryItems = [
      URLQueryItem(name: "client_id", value: clientId),
      URLQueryItem(name: "redirect_uri", value: redirectUri),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "approval_prompt", value: "auto"),
      URLQueryItem(name: "scope", value: "activity:write")
    ]

    guard let url = components?.url else {
      result(FlutterError(code: "invalid_auth_url", message: "Could not create Strava authorization URL.", details: nil))
      return
    }

    stravaAuthResult = result
    pendingStravaClientId = clientId
    pendingStravaClientSecret = clientSecret
    UIApplication.shared.open(url) { [weak self] opened in
      guard let self else { return }
      if !opened {
        self.stravaAuthResult = nil
        self.pendingStravaClientId = nil
        self.pendingStravaClientSecret = nil
        result(FlutterError(code: "auth_open_failed", message: "Could not open Strava authorization.", details: nil))
      }
    }
  }

  private func handleStravaCallback(_ url: URL) -> Bool {
    guard url.scheme == "quantivita",
          let result = stravaAuthResult else {
      return false
    }

    stravaAuthResult = nil
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryItems = components?.queryItems ?? []

    if let error = queryItems.first(where: { $0.name == "error" })?.value {
      pendingStravaClientId = nil
      pendingStravaClientSecret = nil
      result(FlutterError(code: "auth_denied", message: "Strava authorization failed: \(error)", details: nil))
      return true
    }

    guard let code = queryItems.first(where: { $0.name == "code" })?.value,
          let clientId = pendingStravaClientId,
          let clientSecret = pendingStravaClientSecret else {
      pendingStravaClientId = nil
      pendingStravaClientSecret = nil
      result(FlutterError(code: "missing_code", message: "Strava did not return an authorization code.", details: nil))
      return true
    }

    pendingStravaClientId = nil
    pendingStravaClientSecret = nil
    exchangeStravaCode(code: code, clientId: clientId, clientSecret: clientSecret, result: result)
    return true
  }

  private func exchangeStravaCode(
    code: String,
    clientId: String,
    clientSecret: String,
    result: @escaping FlutterResult
  ) {
    guard let url = URL(string: "https://www.strava.com/oauth/token") else {
      result(FlutterError(code: "invalid_token_url", message: "Could not create Strava token URL.", details: nil))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "client_id": clientId,
      "client_secret": clientSecret,
      "code": code,
      "grant_type": "authorization_code"
    ], options: [])

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error {
        DispatchQueue.main.async {
          result(FlutterError(code: "token_exchange_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard let data,
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            (200..<300).contains(statusCode) else {
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        DispatchQueue.main.async {
          result(FlutterError(code: "token_exchange_rejected", message: "Strava rejected the token exchange (\(statusCode)). \(body)", details: nil))
        }
        return
      }

      DispatchQueue.main.async {
        result(json)
      }
    }.resume()
  }

  private func saveStravaTokens(arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_tokens", message: "Strava token payload is invalid.", details: nil))
      return
    }

    do {
      if let accessToken = payload["strava_access_token"] as? String {
        try saveKeychainValue(accessToken, account: "strava_access_token")
      }
      if let refreshToken = payload["strava_refresh_token"] as? String {
        try saveKeychainValue(refreshToken, account: "strava_refresh_token")
      }
      if let expiresAt = payload["strava_expires_at"] {
        try saveKeychainValue("\(expiresAt)", account: "strava_expires_at")
      }
      result(nil)
    } catch {
      result(FlutterError(code: "token_save_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func loadStravaTokens(result: @escaping FlutterResult) {
    let expiresAtText = keychainValue(account: "strava_expires_at")
    var tokens: [String: Any] = [
      "strava_expires_at": Int(expiresAtText ?? "") ?? 0
    ]
    if let accessToken = keychainValue(account: "strava_access_token") {
      tokens["strava_access_token"] = accessToken
    }
    if let refreshToken = keychainValue(account: "strava_refresh_token") {
      tokens["strava_refresh_token"] = refreshToken
    }
    result(tokens)
  }

  private func clearStravaTokens(result: @escaping FlutterResult) {
    for account in ["strava_access_token", "strava_refresh_token", "strava_expires_at"] {
      deleteKeychainValue(account: account)
    }
    result(nil)
  }

  private func saveKeychainValue(_ value: String, account: String) throws {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.bryandijkh.quantivita.strava",
      kSecAttrAccount as String: account
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess {
      return
    }

    var addQuery = query
    addQuery.merge(attributes) { _, new in new }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError(status: addStatus)
    }
  }

  private func keychainValue(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.bryandijkh.quantivita.strava",
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  private func deleteKeychainValue(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.bryandijkh.quantivita.strava",
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }

  struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
      "Keychain operation failed with status \(status)."
    }
  }

  private func requestHealthAuthorization(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result([
        "available": false,
        "authorized": false,
        "hasRecentData": false,
        "message": "Apple Health is not available on this device."
      ])
      return
    }

    let readTypes = healthReadTypes()

    healthStore.requestAuthorization(toShare: healthShareTypes(), read: readTypes) { [weak self] success, error in
      guard let self else { return }

      if let error {
        DispatchQueue.main.async {
          result(FlutterError(code: "authorization_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      if !success {
        DispatchQueue.main.async {
          result([
            "available": true,
            "authorized": false,
            "hasRecentData": false,
            "message": "Apple Health permission was not granted."
          ])
        }
        return
      }

      self.loadTodaySummary(workoutLookbackDays: 7) { summary in
        let hasRecentData = summary.values.contains { value in
          self.doubleValue(value) > 0
        }

        DispatchQueue.main.async {
          result([
            "available": true,
            "authorized": true,
            "hasRecentData": hasRecentData,
            "summary": summary,
            "message": hasRecentData
              ? "Health data updated."
              : "No recent Health data found yet."
          ])
        }
      }
    }
  }

  private func healthReadTypes() -> Set<HKObjectType> {
    var types = Set<HKObjectType>()

    [
      HKObjectType.quantityType(forIdentifier: .stepCount),
      HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
      HKObjectType.quantityType(forIdentifier: .basalEnergyBurned),
      HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
      HKObjectType.quantityType(forIdentifier: .dietaryWater),
      HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
      HKObjectType.quantityType(forIdentifier: .dietaryProtein),
      HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
      HKObjectType.quantityType(forIdentifier: .heartRate),
      HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
      HKObjectType.quantityType(forIdentifier: .restingHeartRate),
      HKObjectType.quantityType(forIdentifier: .respiratoryRate),
      HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
      HKObjectType.quantityType(forIdentifier: .bodyTemperature),
      HKObjectType.quantityType(forIdentifier: .bodyMass),
      HKObjectType.quantityType(forIdentifier: .height),
      HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
      HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
      HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
      HKObjectType.characteristicType(forIdentifier: .biologicalSex),
    ].compactMap { $0 }.forEach { types.insert($0) }

    if #available(iOS 16.0, *) {
      if let wristTemperature = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
        types.insert(wristTemperature)
      }
    }

    types.insert(HKObjectType.workoutType())
    types.insert(HKSeriesType.workoutRoute())

    return types
  }

  private func healthShareTypes() -> Set<HKSampleType> {
    var types = Set<HKSampleType>()
    types.insert(HKObjectType.workoutType())
    types.insert(HKSeriesType.workoutRoute())

    [
      HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
      HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
      HKObjectType.quantityType(forIdentifier: .distanceCycling),
      HKObjectType.quantityType(forIdentifier: .distanceSwimming),
      HKObjectType.quantityType(forIdentifier: .heartRate),
    ].compactMap { $0 }.forEach { types.insert($0) }

    return types
  }

  private func exportMergedWorkout(arguments: Any?, result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(FlutterError(code: "health_unavailable", message: "Apple Health is not available on this device.", details: nil))
      return
    }

    guard let payload = arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_payload", message: "Merged workout export payload is invalid.", details: nil))
      return
    }

    healthStore.requestAuthorization(toShare: healthShareTypes(), read: healthReadTypes()) { [weak self] success, error in
      guard let self else { return }

      if let error {
        DispatchQueue.main.async {
          result(FlutterError(code: "export_authorization_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard success else {
        DispatchQueue.main.async {
          result([
            "success": false,
            "message": "Apple Health write permission was not granted."
          ])
        }
        return
      }

      self.saveMergedWorkout(payload: payload, result: result)
    }
  }

  private func saveMergedWorkout(payload: [String: Any], result: @escaping FlutterResult) {
    let startTime = doubleValue(payload["startTime"])
    let endTime = doubleValue(payload["endTime"])
    guard startTime > 0, endTime > startTime else {
      DispatchQueue.main.async {
        result(FlutterError(code: "invalid_dates", message: "Merged workout needs valid start and end times.", details: nil))
      }
      return
    }

    let start = Date(timeIntervalSince1970: startTime)
    let end = Date(timeIntervalSince1970: endTime)
    let activityType = workoutActivityType(from: payload["exportType"] as? String)
    let energyKcal = max(doubleValue(payload["activeEnergyKcal"]), doubleValue(payload["totalEnergyKcal"]))
    let distanceMeters = doubleValue(payload["distanceMeters"])
    let title = payload["title"] as? String ?? "Merged Workout"
    let segments = payload["segments"] as? [[String: Any]] ?? []
    let syncIdentifier = "quantivita.merge.\(Int(startTime)).\(Int(endTime)).\(segments.count)"

    var metadata: [String: Any] = [
      HKMetadataKeyWorkoutBrandName: "Quantivita",
      HKMetadataKeySyncIdentifier: syncIdentifier,
      HKMetadataKeySyncVersion: 1,
      "QuantivitaMergedWorkout": true,
      "QuantivitaMergedTitle": title,
      "QuantivitaMovingMinutes": doubleValue(payload["movingMinutes"]),
      "QuantivitaElapsedMinutes": doubleValue(payload["elapsedMinutes"]),
      "QuantivitaRouteSegments": doubleValue(payload["routeSegments"]),
      "QuantivitaAverageHeartRate": doubleValue(payload["averageHeartRate"]),
      "QuantivitaMaxHeartRate": doubleValue(payload["maxHeartRate"]),
      "QuantivitaAverageSpeedKmh": doubleValue(payload["averageSpeedKmh"]),
      "QuantivitaElevationGainMeters": doubleValue(payload["elevationGainMeters"]),
      "QuantivitaWeatherConditions": payload["weatherConditions"] as? String ?? "",
      "QuantivitaAverageHumidityPercent": doubleValue(payload["averageHumidityPercent"]),
      "QuantivitaAverageTemperatureC": doubleValue(payload["averageTemperatureC"]),
      "QuantivitaAverageAirQualityIndex": doubleValue(payload["averageAirQualityIndex"])
    ]

    let averageTemperatureC = doubleValue(payload["averageTemperatureC"])
    if averageTemperatureC > 0 {
      metadata[HKMetadataKeyWeatherTemperature] = HKQuantity(unit: .degreeCelsius(), doubleValue: averageTemperatureC)
    }

    let averageHumidityPercent = doubleValue(payload["averageHumidityPercent"])
    if averageHumidityPercent > 0 {
      metadata[HKMetadataKeyWeatherHumidity] = HKQuantity(unit: .percent(), doubleValue: averageHumidityPercent / 100)
    }

    if let segmentJSON = jsonString(from: segments) {
      metadata["QuantivitaSegments"] = segmentJSON
    }

    let workout = HKWorkout(
      activityType: activityType,
      start: start,
      end: end,
      workoutEvents: nil,
      totalEnergyBurned: energyKcal > 0 ? HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal) : nil,
      totalDistance: distanceMeters > 0 ? HKQuantity(unit: .meter(), doubleValue: distanceMeters) : nil,
      metadata: metadata
    )

    healthStore.save(workout) { [weak self] success, error in
      guard let self else { return }

      if let error {
        DispatchQueue.main.async {
          result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard success else {
        DispatchQueue.main.async {
          result([
            "success": false,
            "message": "Merged workout could not be exported."
          ])
        }
        return
      }

      self.saveMergedWorkoutSamples(
        workout: workout,
        activityType: activityType,
        start: start,
        end: end,
        energyKcal: energyKcal,
        distanceMeters: distanceMeters,
        averageHeartRate: doubleValue(payload["averageHeartRate"])
      ) { sampleMessage, sampleError in
        if let sampleError {
          DispatchQueue.main.async {
            result([
              "success": true,
              "message": "Merged workout exported, but linked samples failed: \(sampleError.localizedDescription)"
            ])
          }
          return
        }

        self.copyRoutes(from: segments, to: workout) { copiedRoutePoints, routeError in
        DispatchQueue.main.async {
          if let routeError {
            result([
              "success": true,
              "message": "Merged workout exported, but GPS route copy failed: \(routeError.localizedDescription)"
            ])
            return
          }

          result([
            "success": true,
            "message": copiedRoutePoints > 0
              ? "Merged workout exported with \(copiedRoutePoints) GPS route points. \(sampleMessage)"
              : "Merged workout exported. No source GPS route points were found. \(sampleMessage)"
          ])
        }
      }
      }
    }
  }

  private func createStravaTcx(arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_payload", message: "Strava TCX payload is invalid.", details: nil))
      return
    }

    let segments = payload["segments"] as? [[String: Any]] ?? []
    guard !segments.isEmpty else {
      result(FlutterError(code: "no_segments", message: "Select workouts before exporting to Strava.", details: nil))
      return
    }

    collectMergedRouteLocations(from: segments) { [weak self] locations, routeError in
      guard let self else { return }

      if let routeError {
        DispatchQueue.main.async {
          result(FlutterError(code: "route_read_failed", message: routeError.localizedDescription, details: nil))
        }
        return
      }

      guard !locations.isEmpty else {
        DispatchQueue.main.async {
          result(FlutterError(code: "no_route_points", message: "No GPS points found for the selected workouts.", details: nil))
        }
        return
      }

      let tcx = self.tcxString(payload: payload, locations: locations)
      do {
        let fileName = self.safeFileName(payload["title"] as? String ?? "quantivita-merged-workout")
        let fileURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("\(fileName)-strava.tcx")
        try tcx.write(to: fileURL, atomically: true, encoding: .utf8)

        DispatchQueue.main.async {
          result([
            "success": true,
            "path": fileURL.path,
            "message": "Strava TCX created with \(locations.count) GPS points."
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "tcx_write_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func loadWorkoutHistory(arguments: Any?, result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(FlutterError(code: "health_unavailable", message: "Apple Health is not available on this device.", details: nil))
      return
    }

    guard let payload = arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_payload", message: "Workout history payload is invalid.", details: nil))
      return
    }

    let days = max(7, min(365, Int(doubleValue(payload["days"]))))
    let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

    readRecentWorkouts(start: start, lookbackDays: days, limit: 50) { workoutSummary in
      DispatchQueue.main.async {
        result([
          "summary": workoutSummary,
          "message": "Loaded \(Int(self.doubleValue(workoutSummary["workoutCount"]))) workouts from the last \(days) days."
        ])
      }
    }
  }

  private func collectMergedRouteLocations(
    from segments: [[String: Any]],
    completion: @escaping ([CLLocation], Error?) -> Void
  ) {
    let routeSegments = segments.filter { segment in
      (segment["hasRoute"] as? Bool) == true
    }

    guard !routeSegments.isEmpty else {
      completion([], nil)
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var allLocations = [CLLocation]()
    var firstError: Error?

    for segment in routeSegments {
      group.enter()
      findSourceWorkout(for: segment) { [weak self] sourceWorkout in
        guard let self, let sourceWorkout else {
          group.leave()
          return
        }

        self.readRouteLocations(for: sourceWorkout) { locations, error in
          lock.lock()
          if let error, firstError == nil {
            firstError = error
          }
          allLocations.append(contentsOf: locations)
          lock.unlock()
          group.leave()
        }
      }
    }

    group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
      guard let self else { return }
      if let firstError {
        completion([], firstError)
        return
      }

      completion(self.deduplicateLocations(allLocations), nil)
    }
  }

  private func saveMergedWorkoutSamples(
    workout: HKWorkout,
    activityType: HKWorkoutActivityType,
    start: Date,
    end: Date,
    energyKcal: Double,
    distanceMeters: Double,
    averageHeartRate: Double,
    completion: @escaping (String, Error?) -> Void
  ) {
    var samples = [HKQuantitySample]()
    var labels = [String]()

    if energyKcal > 0,
       let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
      samples.append(
        HKQuantitySample(
          type: energyType,
          quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
          start: start,
          end: end,
          metadata: [
            HKMetadataKeyWasUserEntered: false,
            "QuantivitaMergedWorkoutSample": true
          ]
        )
      )
      labels.append("energy")
    }

    if distanceMeters > 0,
       let distanceType = distanceQuantityType(for: activityType) {
      samples.append(
        HKQuantitySample(
          type: distanceType,
          quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
          start: start,
          end: end,
          metadata: [
            HKMetadataKeyWasUserEntered: false,
            "QuantivitaMergedWorkoutSample": true
          ]
        )
      )
      labels.append("distance")
    }

    if averageHeartRate > 0,
       let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
      samples.append(
        HKQuantitySample(
          type: heartRateType,
          quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: averageHeartRate),
          start: start,
          end: end,
          metadata: [
            HKMetadataKeyWasUserEntered: false,
            "QuantivitaMergedWorkoutSample": true,
            "QuantivitaSyntheticAverageHeartRate": true
          ]
        )
      )
      labels.append("avg HR")
    }

    guard !samples.isEmpty else {
      completion("No linked quantity samples written.", nil)
      return
    }

    healthStore.add(samples, to: workout) { success, error in
      if let error {
        completion("", error)
        return
      }

      completion(success ? "Linked \(labels.joined(separator: ", ")) samples." : "Linked samples were not accepted.", nil)
    }
  }

  private func distanceQuantityType(for activityType: HKWorkoutActivityType) -> HKQuantityType? {
    switch activityType {
    case .cycling:
      return HKObjectType.quantityType(forIdentifier: .distanceCycling)
    case .swimming:
      return HKObjectType.quantityType(forIdentifier: .distanceSwimming)
    case .walking, .running, .hiking:
      return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
    default:
      return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
    }
  }

  private func tcxString(payload: [String: Any], locations: [CLLocation]) -> String {
    let title = xmlEscape(payload["title"] as? String ?? "Quantivita Merged Workout")
    let sport = stravaSport(from: payload["exportType"] as? String)
    let start = Date(timeIntervalSince1970: doubleValue(payload["startTime"]))
    let end = Date(timeIntervalSince1970: doubleValue(payload["endTime"]))
    let totalSeconds = max(0, end.timeIntervalSince(start))
    let distanceMeters = doubleValue(payload["distanceMeters"]) > 0
      ? doubleValue(payload["distanceMeters"])
      : routeDistanceMeters(locations)
    let calories = Int(doubleValue(payload["activeEnergyKcal"]).rounded())
    let avgHeartRate = Int(doubleValue(payload["averageHeartRate"]).rounded())
    let maxHeartRate = Int(doubleValue(payload["maxHeartRate"]).rounded())
    let notes = xmlEscape("Exported from Quantivita. \(payload["weatherConditions"] as? String ?? "")")

    var cumulativeDistance = 0.0
    var previousLocation: CLLocation?
    let trackpoints = locations.map { location in
      let altitude = location.verticalAccuracy >= 0 ? location.altitude : 0
      if let previousLocation {
        cumulativeDistance += location.distance(from: previousLocation)
      }
      previousLocation = location
      return """
              <Trackpoint>
                <Time>\(iso8601(location.timestamp))</Time>
                <Position>
                  <LatitudeDegrees>\(location.coordinate.latitude)</LatitudeDegrees>
                  <LongitudeDegrees>\(location.coordinate.longitude)</LongitudeDegrees>
                </Position>
                <AltitudeMeters>\(String(format: "%.1f", altitude))</AltitudeMeters>
                <DistanceMeters>\(String(format: "%.1f", cumulativeDistance))</DistanceMeters>
              </Trackpoint>
      """
    }.joined(separator: "\n")

    let avgHrXml = avgHeartRate > 0
      ? "<AverageHeartRateBpm><Value>\(avgHeartRate)</Value></AverageHeartRateBpm>"
      : ""
    let maxHrXml = maxHeartRate > 0
      ? "<MaximumHeartRateBpm><Value>\(maxHeartRate)</Value></MaximumHeartRateBpm>"
      : ""

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
      <Activities>
        <Activity Sport="\(sport)">
          <Id>\(iso8601(start))</Id>
          <Lap StartTime="\(iso8601(start))">
            <TotalTimeSeconds>\(String(format: "%.0f", totalSeconds))</TotalTimeSeconds>
            <DistanceMeters>\(String(format: "%.1f", distanceMeters))</DistanceMeters>
            <Calories>\(calories)</Calories>
            \(avgHrXml)
            \(maxHrXml)
            <Intensity>Active</Intensity>
            <TriggerMethod>Manual</TriggerMethod>
            <Track>
    \(trackpoints)
            </Track>
            <Notes>\(notes)</Notes>
          </Lap>
          <Creator xsi:type="Device_t">
            <Name>Quantivita</Name>
            <UnitId>1</UnitId>
            <ProductID>1</ProductID>
          </Creator>
        </Activity>
      </Activities>
      <Author xsi:type="Application_t">
        <Name>Quantivita</Name>
        <Build>
          <Version>
            <VersionMajor>1</VersionMajor>
            <VersionMinor>0</VersionMinor>
          </Version>
        </Build>
        <LangID>en</LangID>
        <PartNumber>Quantivita</PartNumber>
      </Author>
    </TrainingCenterDatabase>
    """
  }

  private func routeDistanceMeters<S: Sequence>(_ locations: S) -> Double where S.Element == CLLocation {
    var total = 0.0
    var previous: CLLocation?
    for location in locations {
      if let previous {
        total += location.distance(from: previous)
      }
      previous = location
    }
    return total
  }

  private func stravaSport(from exportType: String?) -> String {
    switch exportType {
    case "Run":
      return "Running"
    case "Walk", "Hike":
      return "Running"
    case "Swim":
      return "Other"
    default:
      return "Biking"
    }
  }

  private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private func safeFileName(_ text: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return text
      .lowercased()
      .replacingOccurrences(of: " ", with: "-")
      .unicodeScalars
      .map { allowed.contains($0) ? String($0) : "" }
      .joined()
  }

  private func xmlEscape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  private func copyRoutes(
    from segments: [[String: Any]],
    to mergedWorkout: HKWorkout,
    completion: @escaping (Int, Error?) -> Void
  ) {
    let routeSegments = segments.filter { segment in
      (segment["hasRoute"] as? Bool) == true
    }

    guard !routeSegments.isEmpty else {
      completion(0, nil)
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var allLocations = [CLLocation]()
    var firstError: Error?
    var matchedSegments = 0
    var missedSegments = [String]()
    var perSegmentCounts = [String: Int]()

    for segment in routeSegments {
      group.enter()
      findSourceWorkout(for: segment) { [weak self] sourceWorkout in
        guard let self, let sourceWorkout else {
          lock.lock()
          missedSegments.append(segment["title"] as? String ?? "Unknown")
          lock.unlock()
          group.leave()
          return
        }
        lock.lock()
        matchedSegments += 1
        lock.unlock()

        self.readRouteLocations(for: sourceWorkout) { locations, error in
          lock.lock()
          if let error, firstError == nil {
            firstError = error
          }
          allLocations.append(contentsOf: locations)
          perSegmentCounts[segment["title"] as? String ?? sourceWorkout.uuid.uuidString] = locations.count
          lock.unlock()
          group.leave()
        }
      }
    }

    group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
      guard let self else { return }

      if let firstError {
        completion(allLocations.count, firstError)
        return
      }

      let uniqueLocations = self.deduplicateLocations(allLocations)
      guard !uniqueLocations.isEmpty else {
        if !missedSegments.isEmpty || matchedSegments < routeSegments.count {
          let missed = missedSegments.joined(separator: ", ")
          completion(0, RouteCopyError.noLocations("Matched \(matchedSegments)/\(routeSegments.count) route segments. Missing: \(missed)."))
          return
        }
        completion(0, nil)
        return
      }

      self.writeRoute(uniqueLocations, to: mergedWorkout) { count, error in
        if let error {
          completion(count, error)
          return
        }
        if matchedSegments < routeSegments.count {
          completion(count, RouteCopyError.partial("Copied \(count) GPS points, but matched only \(matchedSegments)/\(routeSegments.count) route segments."))
          return
        }
        completion(count, nil)
      }
    }
  }

  private func findSourceWorkout(
    for segment: [String: Any],
    completion: @escaping (HKWorkout?) -> Void
  ) {
    if let sourceUuid = segment["sourceUuid"] as? String,
       let uuid = UUID(uuidString: sourceUuid) {
      findWorkout(by: uuid) { workout in
        if let workout {
          completion(workout)
        } else {
          self.findSourceWorkoutByTimeAndType(for: segment, completion: completion)
        }
      }
      return
    }

    findSourceWorkoutByTimeAndType(for: segment, completion: completion)
  }

  private func findWorkout(by uuid: UUID, completion: @escaping (HKWorkout?) -> Void) {
    let predicate = HKQuery.predicateForObject(with: uuid)
    let query = HKSampleQuery(
      sampleType: HKObjectType.workoutType(),
      predicate: predicate,
      limit: 1,
      sortDescriptors: nil
    ) { _, samples, _ in
      completion((samples as? [HKWorkout])?.first)
    }

    healthStore.execute(query)
  }

  private func findSourceWorkoutByTimeAndType(
    for segment: [String: Any],
    completion: @escaping (HKWorkout?) -> Void
  ) {
    let start = Date(timeIntervalSince1970: doubleValue(segment["startTime"]) - 2)
    let end = Date(timeIntervalSince1970: doubleValue(segment["endTime"]) + 2)
    let expectedStart = doubleValue(segment["startTime"])
    let expectedEnd = doubleValue(segment["endTime"])
    let expectedType = Int(doubleValue(segment["typeCode"]))
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    let query = HKSampleQuery(
      sampleType: HKObjectType.workoutType(),
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [sort]
    ) { [weak self] _, samples, _ in
      guard let self else {
        completion(nil)
        return
      }

      let workouts = samples as? [HKWorkout] ?? []
      let bestMatch = workouts.min { left, right in
        self.workoutMatchScore(left, expectedStart: expectedStart, expectedEnd: expectedEnd, expectedType: expectedType) <
          self.workoutMatchScore(right, expectedStart: expectedStart, expectedEnd: expectedEnd, expectedType: expectedType)
      }

      guard let bestMatch,
            self.workoutMatchScore(bestMatch, expectedStart: expectedStart, expectedEnd: expectedEnd, expectedType: expectedType) < 120 else {
        completion(nil)
        return
      }

      completion(bestMatch)
    }

    healthStore.execute(query)
  }

  private func workoutMatchScore(
    _ workout: HKWorkout,
    expectedStart: Double,
    expectedEnd: Double,
    expectedType: Int
  ) -> Double {
    let startDelta = abs(workout.startDate.timeIntervalSince1970 - expectedStart)
    let endDelta = abs(workout.endDate.timeIntervalSince1970 - expectedEnd)
    let typePenalty = Int(workoutDisplayCode(workout.workoutActivityType)) == expectedType ? 0.0 : 4.0
    return startDelta + endDelta + typePenalty
  }

  private func readRouteLocations(
    for workout: HKWorkout,
    completion: @escaping ([CLLocation], Error?) -> Void
  ) {
    readRoutes(for: workout) { [weak self] routes, error in
      guard let self else { return }
      if let error {
        completion([], error)
        return
      }

      guard !routes.isEmpty else {
        completion([], nil)
        return
      }

      let group = DispatchGroup()
      let lock = NSLock()
      var locations = [CLLocation]()
      var firstError: Error?

      for route in routes {
        group.enter()
        self.readLocations(for: route) { routeLocations, routeError in
          lock.lock()
          if let routeError, firstError == nil {
            firstError = routeError
          }
          locations.append(contentsOf: routeLocations)
          lock.unlock()
          group.leave()
        }
      }

      group.notify(queue: .global(qos: .userInitiated)) {
        completion(locations, firstError)
      }
    }
  }

  private func readRoutes(
    for workout: HKWorkout,
    completion: @escaping ([HKWorkoutRoute], Error?) -> Void
  ) {
    let predicate = HKQuery.predicateForObjects(from: workout)
    let query = HKSampleQuery(
      sampleType: HKSeriesType.workoutRoute(),
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { _, samples, error in
      completion(samples as? [HKWorkoutRoute] ?? [], error)
    }

    healthStore.execute(query)
  }

  private func readLocations(
    for route: HKWorkoutRoute,
    completion: @escaping ([CLLocation], Error?) -> Void
  ) {
    var locations = [CLLocation]()
    let query = HKWorkoutRouteQuery(route: route) { _, routeLocations, done, error in
      if let routeLocations {
        locations.append(contentsOf: routeLocations)
      }

      if done || error != nil {
        completion(locations, error)
      }
    }

    healthStore.execute(query)
  }

  private func deduplicateLocations(_ locations: [CLLocation]) -> [CLLocation] {
    let sorted = locations.sorted { $0.timestamp < $1.timestamp }
    var seen = Set<String>()
    var unique = [CLLocation]()

    for location in sorted {
      let key = "\(Int(location.timestamp.timeIntervalSince1970 * 1000)):\(location.coordinate.latitude):\(location.coordinate.longitude)"
      if seen.insert(key).inserted {
        unique.append(location)
      }
    }

    return unique
  }

  private func writeRoute(
    _ locations: [CLLocation],
    to workout: HKWorkout,
    completion: @escaping (Int, Error?) -> Void
  ) {
    let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
    let chunkSize = 1000
    var index = 0

    func insertNextChunk() {
      guard index < locations.count else {
        builder.finishRoute(with: workout, metadata: [
          "QuantivitaMergedRoute": true,
          "QuantivitaRoutePointCount": locations.count
        ]) { _, error in
          completion(locations.count, error)
        }
        return
      }

      let endIndex = min(index + chunkSize, locations.count)
      let chunk = Array(locations[index..<endIndex])
      builder.insertRouteData(chunk) { success, error in
        if let error {
          completion(index, error)
          return
        }

        guard success else {
          completion(index, nil)
          return
        }

        index = endIndex
        insertNextChunk()
      }
    }

    insertNextChunk()
  }

  enum RouteCopyError: LocalizedError {
    case partial(String)
    case noLocations(String)

    var errorDescription: String? {
      switch self {
      case .partial(let message), .noLocations(let message):
        return message
      }
    }
  }

  private func doubleValue(_ value: Any?) -> Double {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return 0
  }

  private func jsonString(from value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  private func workoutActivityType(from label: String?) -> HKWorkoutActivityType {
    switch label {
    case "Run":
      return .running
    case "Walk":
      return .walking
    case "Cycle":
      return .cycling
    case "Swim":
      return .swimming
    case "Strength":
      return .traditionalStrengthTraining
    case "HIIT":
      return .highIntensityIntervalTraining
    case "Yoga":
      return .yoga
    case "Hike":
      return .hiking
    case "Elliptical":
      return .elliptical
    case "Rowing":
      return .rowing
    case "swimBikeRun":
      if #available(iOS 16.0, *) {
        return .swimBikeRun
      }
      return .other
    case "mixedCardio":
      return .mixedCardio
    default:
      return .other
    }
  }

  private func loadTodaySummary(workoutLookbackDays: Int, completion: @escaping ([String: Any]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var summary: [String: Any] = [
      "steps": 0.0,
      "activeEnergyKcal": 0.0,
      "basalEnergyKcal": 0.0,
      "dietaryEnergyKcal": 0.0,
      "dietaryWaterMl": 0.0,
      "dietaryCarbohydratesG": 0.0,
      "dietaryProteinG": 0.0,
      "dietaryFatG": 0.0,
      "hrvMs": 0.0,
      "restingHeartBpm": 0.0,
      "sleepMinutes": 0.0,
      "respiratoryRate": 0.0,
      "oxygenSaturation": 0.0,
      "bodyTemperatureC": 0.0,
      "wristTemperatureC": 0.0,
      "bodyMassKg": 0.0,
      "heightCm": 0.0,
      "bodyFatPercent": 0.0,
      "birthYear": 0.0,
      "birthMonth": 0.0,
      "birthDay": 0.0,
      "biologicalSex": 0.0,
      "workoutCount": 0.0,
      "lastWorkoutStart": 0.0,
      "lastWorkoutDurationMinutes": 0.0,
      "lastWorkoutEnergyKcal": 0.0,
      "sleepCoreMinutes": 0.0,
      "sleepRemMinutes": 0.0,
      "sleepDeepMinutes": 0.0,
      "sleepAwakeMinutes": 0.0,
      "sleepInBedMinutes": 0.0
    ]

    readProfileSummary().forEach { key, value in
      summary[key] = value
    }

    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: Date())
    let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? startOfDay
    let workoutStart = calendar.date(byAdding: .day, value: -workoutLookbackDays, to: Date()) ?? sevenDaysAgo
    let sleepStart = recoverySleepStart()

    group.enter()
    readQuantitySum(.stepCount, unit: .count(), start: startOfDay) { value in
      lock.lock()
      summary["steps"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.activeEnergyBurned, unit: .kilocalorie(), start: startOfDay) { value in
      lock.lock()
      summary["activeEnergyKcal"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.basalEnergyBurned, unit: .kilocalorie(), start: startOfDay) { value in
      lock.lock()
      summary["basalEnergyKcal"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.dietaryEnergyConsumed, unit: .kilocalorie(), start: startOfDay) { value in
      lock.lock()
      summary["dietaryEnergyKcal"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.dietaryWater, unit: HKUnit.literUnit(with: .milli), start: startOfDay) { value in
      lock.lock()
      summary["dietaryWaterMl"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.dietaryCarbohydrates, unit: .gram(), start: startOfDay) { value in
      lock.lock()
      summary["dietaryCarbohydratesG"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.dietaryProtein, unit: .gram(), start: startOfDay) { value in
      lock.lock()
      summary["dietaryProteinG"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantitySum(.dietaryFatTotal, unit: .gram(), start: startOfDay) { value in
      lock.lock()
      summary["dietaryFatG"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityAverage(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), start: sevenDaysAgo) { value in
      lock.lock()
      summary["hrvMs"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: sevenDaysAgo) { value in
      lock.lock()
      summary["restingHeartBpm"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readSleepSummary(start: sleepStart) { sleepSummary in
      lock.lock()
      sleepSummary.forEach { key, value in
        summary[key] = value
      }
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityAverage(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: sevenDaysAgo) { value in
      lock.lock()
      summary["respiratoryRate"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityAverage(.oxygenSaturation, unit: .percent(), start: sevenDaysAgo) { value in
      lock.lock()
      summary["oxygenSaturation"] = value * 100
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityAverage(.bodyTemperature, unit: .degreeCelsius(), start: sevenDaysAgo) { value in
      lock.lock()
      summary["bodyTemperatureC"] = value
      lock.unlock()
      group.leave()
    }

    if #available(iOS 16.0, *) {
      group.enter()
      readQuantityAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: sevenDaysAgo) { value in
        lock.lock()
        summary["wristTemperatureC"] = value
        lock.unlock()
        group.leave()
      }
    }

    group.enter()
    readQuantityMostRecent(.bodyMass, unit: .gramUnit(with: .kilo), start: sevenDaysAgo) { value in
      lock.lock()
      summary["bodyMassKg"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityMostRecent(.height, unit: .meterUnit(with: .centi), start: sevenDaysAgo) { value in
      lock.lock()
      summary["heightCm"] = value
      lock.unlock()
      group.leave()
    }

    group.enter()
    readQuantityMostRecent(.bodyFatPercentage, unit: .percent(), start: sevenDaysAgo) { value in
      lock.lock()
      summary["bodyFatPercent"] = value * 100
      lock.unlock()
      group.leave()
    }

    group.enter()
    readRecentWorkouts(start: workoutStart, lookbackDays: workoutLookbackDays, limit: 50) { workoutSummary in
      lock.lock()
      workoutSummary.forEach { key, value in
        summary[key] = value
      }
      lock.unlock()
      group.leave()
    }

    group.notify(queue: .global(qos: .userInitiated)) {
      completion(summary)
    }
  }

  private func recoverySleepStart(now: Date = Date()) -> Date {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: now)
    let hour = calendar.component(.hour, from: now)

    if hour < 4 {
      return startOfDay
    }

    return calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
  }

  private func readQuantitySum(
    _ identifier: HKQuantityTypeIdentifier,
    unit: HKUnit,
    start: Date,
    completion: @escaping (Double) -> Void
  ) {
    guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
      completion(0)
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    let query = HKStatisticsQuery(
      quantityType: quantityType,
      quantitySamplePredicate: predicate,
      options: .cumulativeSum
    ) { _, statistics, _ in
      completion(statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
    }

    healthStore.execute(query)
  }

  private func readQuantityAverage(
    _ identifier: HKQuantityTypeIdentifier,
    unit: HKUnit,
    start: Date,
    completion: @escaping (Double) -> Void
  ) {
    guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
      completion(0)
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    let query = HKStatisticsQuery(
      quantityType: quantityType,
      quantitySamplePredicate: predicate,
      options: .discreteAverage
    ) { _, statistics, _ in
      completion(statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0)
    }

    healthStore.execute(query)
  }

  private func readQuantityMostRecent(
    _ identifier: HKQuantityTypeIdentifier,
    unit: HKUnit,
    start: Date,
    completion: @escaping (Double) -> Void
  ) {
    guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
      completion(0)
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let query = HKSampleQuery(
      sampleType: quantityType,
      predicate: predicate,
      limit: 1,
      sortDescriptors: [sort]
    ) { _, samples, _ in
      let sample = (samples as? [HKQuantitySample])?.first
      completion(sample?.quantity.doubleValue(for: unit) ?? 0)
    }

    healthStore.execute(query)
  }

  private func readProfileSummary() -> [String: Double] {
    var profile = [String: Double]()

    if let birthDate = try? healthStore.dateOfBirthComponents() {
      profile["birthYear"] = Double(birthDate.year ?? 0)
      profile["birthMonth"] = Double(birthDate.month ?? 0)
      profile["birthDay"] = Double(birthDate.day ?? 0)
    }

    if let sex = try? healthStore.biologicalSex() {
      profile["biologicalSex"] = Double(sex.biologicalSex.rawValue)
    }

    return profile
  }

  private func readSleepSummary(start: Date, completion: @escaping ([String: Double]) -> Void) {
    guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      completion(["sleepMinutes": 0])
      return
    }

    let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    let query = HKSampleQuery(
      sampleType: sleepType,
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { _, samples, _ in
      var summary = [
        "sleepMinutes": 0.0,
        "sleepCoreMinutes": 0.0,
        "sleepRemMinutes": 0.0,
        "sleepDeepMinutes": 0.0,
        "sleepAwakeMinutes": 0.0,
        "sleepInBedMinutes": 0.0
      ]

      for sample in samples as? [HKCategorySample] ?? [] {
        let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60

        if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
          summary["sleepInBedMinutes", default: 0] += minutes
          continue
        }

        if #available(iOS 16.0, *) {
          switch sample.value {
          case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            summary["sleepCoreMinutes", default: 0] += minutes
            summary["sleepMinutes", default: 0] += minutes
          case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            summary["sleepRemMinutes", default: 0] += minutes
            summary["sleepMinutes", default: 0] += minutes
          case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            summary["sleepDeepMinutes", default: 0] += minutes
            summary["sleepMinutes", default: 0] += minutes
          case HKCategoryValueSleepAnalysis.awake.rawValue:
            summary["sleepAwakeMinutes", default: 0] += minutes
          default:
            summary["sleepMinutes", default: 0] += minutes
          }
        } else {
          summary["sleepMinutes", default: 0] += minutes
        }
      }

      completion(summary)
    }

    healthStore.execute(query)
  }

  private func readRecentWorkouts(
    start: Date,
    lookbackDays: Int,
    limit: Int,
    completion: @escaping ([String: Any]) -> Void
  ) {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
    let query = HKSampleQuery(
      sampleType: HKObjectType.workoutType(),
      predicate: predicate,
      limit: limit,
      sortDescriptors: [sort]
    ) { _, samples, _ in
      let workouts = samples as? [HKWorkout] ?? []
      guard let workout = workouts.first else {
        completion([
          "workoutCount": 0,
          "workoutLookbackDays": Double(lookbackDays),
          "lastWorkoutStart": 0,
          "lastWorkoutDurationMinutes": 0,
          "lastWorkoutEnergyKcal": 0
        ])
        return
      }

      var workoutSummary: [String: Any] = [
        "workoutCount": Double(workouts.count),
        "workoutLookbackDays": Double(lookbackDays),
        "lastWorkoutStart": workout.startDate.timeIntervalSince1970,
        "lastWorkoutDurationMinutes": workout.duration / 60,
        "lastWorkoutEnergyKcal": workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
        "lastWorkoutDistanceMeters": workout.totalDistance?.doubleValue(for: .meter()) ?? 0
      ]

      let group = DispatchGroup()
      let lock = NSLock()

      for (index, recentWorkout) in workouts.enumerated() {
        let prefix = "workout\(index + 1)"
        workoutSummary["\(prefix)Uuid"] = recentWorkout.uuid.uuidString
        workoutSummary["\(prefix)Start"] = recentWorkout.startDate.timeIntervalSince1970
        workoutSummary["\(prefix)DurationMinutes"] = recentWorkout.duration / 60
        workoutSummary["\(prefix)EnergyKcal"] =
          recentWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        workoutSummary["\(prefix)TotalEnergyKcal"] =
          recentWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        workoutSummary["\(prefix)DistanceMeters"] =
          recentWorkout.totalDistance?.doubleValue(for: .meter()) ?? 0
        workoutSummary["\(prefix)ElevationGainMeters"] =
          self.metadataDouble(recentWorkout.metadata?[HKMetadataKeyElevationAscended], unit: .meter())
        workoutSummary["\(prefix)TemperatureC"] =
          (recentWorkout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity)?
            .doubleValue(for: .degreeCelsius()) ?? 0
        workoutSummary["\(prefix)HumidityPercent"] =
          self.metadataPercent(recentWorkout.metadata?[HKMetadataKeyWeatherHumidity])
        workoutSummary["\(prefix)WeatherCondition"] =
          self.weatherConditionLabel(recentWorkout.metadata?[HKMetadataKeyWeatherCondition])
        workoutSummary["\(prefix)AirQualityIndex"] = 0
        workoutSummary["\(prefix)AverageHeartRate"] = 0
        workoutSummary["\(prefix)MaxHeartRate"] = 0
        workoutSummary["\(prefix)Type"] = self.workoutDisplayCode(recentWorkout.workoutActivityType)
        workoutSummary["\(prefix)HasRoute"] = 0

        group.enter()
        self.readWorkoutRouteMetrics(for: recentWorkout) { routeMetrics in
          lock.lock()
          workoutSummary["\(prefix)HasRoute"] = routeMetrics.hasRoute ? 1 : 0
          let existingElevation = self.doubleValue(workoutSummary["\(prefix)ElevationGainMeters"])
          workoutSummary["\(prefix)ElevationGainMeters"] = existingElevation > 0
            ? existingElevation
            : routeMetrics.elevationGainMeters
          workoutSummary["\(prefix)RoutePointCount"] = Double(routeMetrics.pointCount)
          lock.unlock()
          group.leave()
        }

        group.enter()
        self.readHeartRateMetrics(for: recentWorkout) { heartMetrics in
          lock.lock()
          workoutSummary["\(prefix)AverageHeartRate"] = heartMetrics.average
          workoutSummary["\(prefix)MaxHeartRate"] = heartMetrics.max
          lock.unlock()
          group.leave()
        }
      }

      group.notify(queue: .global(qos: .userInitiated)) {
        completion(workoutSummary)
      }
    }

    healthStore.execute(query)
  }

  private func readWorkoutRouteMetrics(for workout: HKWorkout, completion: @escaping (WorkoutRouteMetrics) -> Void) {
    readRouteLocations(for: workout) { [weak self] locations, _ in
      guard let self else { return }
      completion(
        WorkoutRouteMetrics(
          hasRoute: !locations.isEmpty,
          pointCount: locations.count,
          elevationGainMeters: self.elevationGain(from: locations)
        )
      )
    }
  }

  private func readHeartRateMetrics(for workout: HKWorkout, completion: @escaping (HeartRateMetrics) -> Void) {
    guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
      completion(HeartRateMetrics(average: 0, max: 0))
      return
    }

    let unit = HKUnit.count().unitDivided(by: .minute())
    let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
    let query = HKStatisticsQuery(
      quantityType: heartRateType,
      quantitySamplePredicate: predicate,
      options: [.discreteAverage, .discreteMax]
    ) { _, statistics, _ in
      completion(
        HeartRateMetrics(
          average: statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0,
          max: statistics?.maximumQuantity()?.doubleValue(for: unit) ?? 0
        )
      )
    }

    healthStore.execute(query)
  }

  private func elevationGain(from locations: [CLLocation]) -> Double {
    guard locations.count > 1 else { return 0 }

    let sorted = locations.sorted { $0.timestamp < $1.timestamp }
    var gain = 0.0
    var previousAltitude: CLLocationDistance?

    for location in sorted where location.verticalAccuracy >= 0 {
      if let previousAltitude {
        let delta = location.altitude - previousAltitude
        if delta > 0.5 {
          gain += delta
        }
      }
      previousAltitude = location.altitude
    }

    return gain
  }

  private func metadataDouble(_ value: Any?, unit: HKUnit) -> Double {
    if let quantity = value as? HKQuantity {
      return quantity.doubleValue(for: unit)
    }
    return doubleValue(value)
  }

  private func metadataPercent(_ value: Any?) -> Double {
    if let quantity = value as? HKQuantity {
      let percent = quantity.doubleValue(for: .percent())
      return percent <= 1 ? percent * 100 : percent
    }

    let percent = doubleValue(value)
    return percent <= 1 && percent > 0 ? percent * 100 : percent
  }

  private func weatherConditionLabel(_ value: Any?) -> String {
    let code = Int(doubleValue(value))
    switch code {
    case 1:
      return "Clear"
    case 2:
      return "Fair"
    case 3:
      return "Partly cloudy"
    case 4:
      return "Mostly cloudy"
    case 5:
      return "Cloudy"
    case 6:
      return "Foggy"
    case 7:
      return "Haze"
    case 8:
      return "Windy"
    case 9:
      return "Blustery"
    case 10:
      return "Smoky"
    case 11:
      return "Dust"
    case 12:
      return "Snow"
    case 13:
      return "Hail"
    case 14:
      return "Sleet"
    case 15:
      return "Freezing drizzle"
    case 16:
      return "Freezing rain"
    case 17:
      return "Mixed rain and hail"
    case 18:
      return "Mixed rain and snow"
    case 19:
      return "Mixed rain and sleet"
    case 20:
      return "Mixed snow and sleet"
    case 21:
      return "Drizzle"
    case 22:
      return "Scattered showers"
    case 23:
      return "Showers"
    case 24:
      return "Thunderstorms"
    case 25:
      return "Tropical storm"
    case 26:
      return "Hurricane"
    case 27:
      return "Tornado"
    default:
      return ""
    }
  }

  struct WorkoutRouteMetrics {
    let hasRoute: Bool
    let pointCount: Int
    let elevationGainMeters: Double
  }

  struct HeartRateMetrics {
    let average: Double
    let max: Double
  }

  private func workoutDisplayCode(_ type: HKWorkoutActivityType) -> Double {
    switch type {
    case .running:
      return 1
    case .walking:
      return 2
    case .cycling:
      return 3
    case .swimming:
      return 4
    case .functionalStrengthTraining, .traditionalStrengthTraining:
      return 5
    case .highIntensityIntervalTraining:
      return 6
    case .yoga:
      return 7
    case .hiking:
      return 8
    case .elliptical:
      return 9
    case .rowing:
      return 10
    default:
      return 0
    }
  }
}
