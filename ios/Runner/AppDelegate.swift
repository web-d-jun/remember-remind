import CoreLocation
import Flutter
import UIKit
// 알림 버튼을 앱이 꺼져 있을 때도 처리하려면 필요하다.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 위치 이벤트로 깨어났을 때 화면 없이 Dart(backgroundMain)를 돌리는 엔진.
  private var backgroundEngine: FlutterEngine?

  /// 화면용 엔진이 이미 떴는지. 떴으면 백그라운드 엔진은 필요 없다.
  private var implicitEngineReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 위치 이벤트로 다시 실행됐으면, 위치 관리자를 바로 만들어 이벤트를 받을 수 있게 해야 한다.
    let wakeup = LocationWakeup.shared
    // 알림을 앱이 열려 있을 때도 띄우고, 알림 버튼 응답을 플러그인이 받게 한다.
    // 이게 없으면 iOS는 앱이 앞에 있는 동안 알림을 조용히 버린다.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // 화면이 붙으면(사용자가 앱을 열면) 백그라운드 엔진은 끈다. 두 엔진이 같이 돌면 알림이 두 번 간다.
    NotificationCenter.default.addObserver(
      forName: UIScene.willConnectNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.stopBackgroundEngine()
    }

    if launchOptions?[.location] != nil {
      // 종료돼 있던 앱이 주요 위치 변경/지역 진입·이탈로 백그라운드에서 실행됐다.
      // UIScene 구조에서는 이때 화면이 안 만들어져 Dart가 돌지 않으므로 직접 띄운다.
      wakeup.resumeSignificantChanges()
      startBackgroundEngineIfNeeded()
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 알림 버튼([샀어요] 등)을 처리하는 백그라운드 isolate에서도 플러그인을 쓸 수 있게 한다.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LocationWakeup") {
      LocationWakeup.shared.attach(key: "app", messenger: registrar.messenger())
    }
    implicitEngineReady = true
    stopBackgroundEngine()
  }

  private func startBackgroundEngineIfNeeded() {
    guard backgroundEngine == nil, !implicitEngineReady else { return }
    let engine = FlutterEngine(
      name: "kkamagwi.background", project: nil, allowHeadlessExecution: true)
    guard engine.run(withEntrypoint: "backgroundMain") else { return }
    GeneratedPluginRegistrant.register(with: engine)
    if let registrar = engine.registrar(forPlugin: "LocationWakeup") {
      LocationWakeup.shared.attach(key: "background", messenger: registrar.messenger())
    }
    backgroundEngine = engine
  }

  private func stopBackgroundEngine() {
    guard let engine = backgroundEngine else { return }
    LocationWakeup.shared.detach(key: "background")
    engine.destroyContext()
    backgroundEngine = nil
  }
}

/// 앱이 종료된 뒤에도 iOS가 위치 이벤트로 앱을 다시 실행하게 한다.
/// Dart 쪽은 lib/services/location_wakeup.dart.
///
/// - 주요 위치 변경(Significant Location Change): 약 500m 이상 움직이면 실행
/// - 지역 모니터링: 등록한 원(최대 20개)에 들어가거나 나가면 실행
/// 실제 매장 판단은 깨어난 Dart가 위치 스트림으로 한다. 여기서는 깨우기만 한다.
final class LocationWakeup: NSObject, CLLocationManagerDelegate {
  static let shared = LocationWakeup()

  private static let regionPrefix = "kkm:"
  private static let enabledKey = "kkamagwi.wakeup.enabled"

  private let manager = CLLocationManager()
  private var channels: [String: FlutterMethodChannel] = [:]

  private override init() {
    super.init()
    manager.delegate = self
  }

  func attach(key: String, messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "kkamagwi/location_wakeup", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    channels[key] = channel
  }

  func detach(key: String) {
    channels[key]?.setMethodCallHandler(nil)
    channels[key] = nil
  }

  /// 다시 실행됐을 때 Dart가 뜨기 전에도 이벤트를 계속 받도록 바로 다시 켠다.
  func resumeSignificantChanges() {
    guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
    startSignificantChanges()
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "start":
      UserDefaults.standard.set(true, forKey: Self.enabledKey)
      startSignificantChanges()
      result(nil)
    case "stop":
      UserDefaults.standard.set(false, forKey: Self.enabledKey)
      manager.stopMonitoringSignificantLocationChanges()
      for region in ownRegions() { manager.stopMonitoring(for: region) }
      result(nil)
    case "setRegions":
      setRegions(call.arguments as? [[String: Any]] ?? [])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startSignificantChanges() {
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
    manager.startMonitoringSignificantLocationChanges()
  }

  private func setRegions(_ items: [[String: Any]]) {
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
    let maxRadius = manager.maximumRegionMonitoringDistance
    var wanted: [String: CLCircularRegion] = [:]
    for item in items.prefix(20) {
      guard let id = item["id"] as? String,
        let lat = item["lat"] as? Double,
        let lng = item["lng"] as? Double,
        let radius = item["radius"] as? Double
      else { continue }
      let region = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
        radius: maxRadius > 0 ? min(radius, maxRadius) : radius,
        identifier: Self.regionPrefix + id)
      region.notifyOnEntry = true
      region.notifyOnExit = true
      wanted[region.identifier] = region
    }

    // 바뀐 것만 다시 등록한다. (같은 identifier로 다시 등록하면 기존 것을 대체한다)
    for region in ownRegions() {
      guard let circle = region as? CLCircularRegion,
        let next = wanted[region.identifier],
        circle.center.latitude == next.center.latitude,
        circle.center.longitude == next.center.longitude,
        circle.radius == next.radius
      else {
        if wanted[region.identifier] == nil { manager.stopMonitoring(for: region) }
        continue
      }
      wanted[region.identifier] = nil
    }
    for region in wanted.values { manager.startMonitoring(for: region) }
  }

  private func ownRegions() -> [CLRegion] {
    manager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.regionPrefix) }
  }

  // 깨우는 것만이 목적이라 이벤트 내용은 쓰지 않는다. 위치 판단은 Dart의 위치 스트림이 한다.
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {}
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {}
  func locationManager(
    _ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error
  ) {}
}
