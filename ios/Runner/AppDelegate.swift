import Flutter
import UIKit
import UserNotifications
import CoreBluetooth
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var directPrinterPlugin: IOSDirectPrinterPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep Flutter/Firebase's normal lifecycle. Do not manually configure
    // Firebase or replace FlutterAppDelegate's notification delegate.
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    // Existing iOS notification fallback kept unchanged.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .badge, .sound]
      ) { granted, error in
        if let error = error {
          print("Hala Talab Partners notification permission error: \(error)")
        }
        if granted {
          DispatchQueue.main.async {
            application.registerForRemoteNotifications()
          }
        }
      }
    }

    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // iOS direct thermal printer bridge. This is intentionally registered
    // beside the existing plugins and does not alter Firebase/APNs handling.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HalaTalabDirectPrinterIOS") else {
      print("Hala Talab Partners direct printer registrar unavailable")
      return
    }
    let plugin = IOSDirectPrinterPlugin(messenger: registrar.messenger())
    directPrinterPlugin = plugin
  }
}

private final class IOSDirectPrinterPlugin: NSObject {
  private let channel: FlutterMethodChannel
  private let ble = HalaBLEPrinterManager()
  private let networkQueue = DispatchQueue(label: "com.halatalab.partners.direct_printer.network")

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.halatalab.partners/direct_printer",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestBluetoothPermission":
      ble.requestPermission { allowed in result(allowed) }

    case "openBluetoothSettings":
      DispatchQueue.main.async {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url)
        }
        result(nil)
      }

    case "listPrinters":
      let args = call.arguments as? [String: Any]
      let transport = (args?["transport"] as? String ?? "ble").lowercased()
      if transport == "network" {
        result([])
      } else if transport == "ble" || transport == "auto" {
        ble.scan(timeout: 4.0) { devices in
          result(devices.map { device in
            [
              "id": device.identifier.uuidString,
              "name": device.name ?? "BLE Printer",
              "transport": "ble"
            ]
          })
        }
      } else if transport == "bluetooth" {
        result(FlutterError(
          code: "IOS_CLASSIC_UNSUPPORTED",
          message: "Bluetooth Classic/SPP العام غير متاح مباشرة على iPhone إلا للطابعات التي تدعم MFi/ExternalAccessory. استخدم BLE أو Wi‑Fi/LAN أو طباعة النظام.",
          details: nil
        ))
      } else if transport == "usb" {
        result(FlutterError(
          code: "IOS_USB_UNSUPPORTED",
          message: "USB المباشر العام غير متاح على iPhone بهذه الطريقة. استخدم BLE أو Wi‑Fi/LAN أو طباعة النظام.",
          details: nil
        ))
      } else {
        result([])
      }

    case "testConnection":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BAD_ARGS", message: "بيانات الطابعة غير مكتملة", details: nil))
        return
      }
      let transport = (args["transport"] as? String ?? "ble").lowercased()
      if transport == "network" {
        guard let host = (args["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
          result(FlutterError(code: "BAD_HOST", message: "أدخل عنوان IP للطابعة", details: nil))
          return
        }
        let port = (args["port"] as? NSNumber)?.uint16Value ?? 9100
        testNetwork(host: host, port: port) { ok, message in
          if ok { result(true) }
          else { result(FlutterError(code: "DEVICE_NOT_FOUND", message: message, details: nil)) }
        }
      } else if transport == "ble" || transport == "auto" {
        guard let id = args["deviceId"] as? String, let uuid = UUID(uuidString: id) else {
          result(FlutterError(code: "DEVICE_NOT_FOUND", message: "اختر طابعة Bluetooth أولًا", details: nil))
          return
        }
        ble.testConnection(identifier: uuid) { ok, message in
          if ok { result(true) }
          else { result(FlutterError(code: "DEVICE_NOT_FOUND", message: message, details: nil)) }
        }
      } else if transport == "bluetooth" {
        result(FlutterError(code: "IOS_CLASSIC_UNSUPPORTED", message: "Bluetooth Classic/SPP العام غير متاح مباشرة على iPhone. استخدم BLE أو Wi‑Fi/LAN.", details: nil))
      } else {
        result(FlutterError(code: "IOS_TRANSPORT_UNSUPPORTED", message: "طريقة الاتصال هذه غير متاحة مباشرة على iPhone", details: nil))
      }

    case "printRaster":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BAD_ARGS", message: "بيانات الطباعة غير مكتملة", details: nil))
        return
      }
      let transport = (args["transport"] as? String ?? "ble").lowercased()
      let widthPx = max(280, min(1024, (args["widthPx"] as? NSNumber)?.intValue ?? 576))
      let autoCut = args["autoCut"] as? Bool ?? true
      let beep = args["beep"] as? Bool ?? false
      let imageValues = args["images"] as? [Any] ?? []
      let imageData: [Data] = imageValues.compactMap { value in
        if let typed = value as? FlutterStandardTypedData { return typed.data }
        if let data = value as? Data { return data }
        return nil
      }
      guard !imageData.isEmpty else {
        result(FlutterError(code: "PRINT_FAILED", message: "لا توجد صفحات جاهزة للطباعة", details: nil))
        return
      }
      guard let payload = buildReceiptPayload(images: imageData, widthPx: widthPx, autoCut: autoCut, beep: beep) else {
        result(FlutterError(code: "PRINT_FAILED", message: "تعذر تجهيز صورة الإيصال للطابعة", details: nil))
        return
      }

      if transport == "network" {
        guard let host = (args["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
          result(FlutterError(code: "BAD_HOST", message: "أدخل عنوان IP للطابعة", details: nil))
          return
        }
        let port = (args["port"] as? NSNumber)?.uint16Value ?? 9100
        sendNetwork(data: payload, host: host, port: port) { ok, message in
          if ok { result(true) }
          else { result(FlutterError(code: "PRINT_FAILED", message: message, details: nil)) }
        }
      } else if transport == "ble" || transport == "auto" {
        guard let id = args["deviceId"] as? String, let uuid = UUID(uuidString: id) else {
          result(FlutterError(code: "DEVICE_NOT_FOUND", message: "اختر طابعة Bluetooth أولًا", details: nil))
          return
        }
        ble.print(identifier: uuid, data: payload) { ok, message in
          if ok { result(true) }
          else { result(FlutterError(code: "PRINT_FAILED", message: message, details: nil)) }
        }
      } else if transport == "bluetooth" {
        result(FlutterError(code: "IOS_CLASSIC_UNSUPPORTED", message: "هذه الطابعة تستخدم Bluetooth Classic/SPP غير العام على iPhone. جرّب BLE أو Wi‑Fi/LAN أو تعريف الشركة/AirPrint.", details: nil))
      } else {
        result(FlutterError(code: "IOS_TRANSPORT_UNSUPPORTED", message: "طريقة الاتصال هذه غير متاحة مباشرة على iPhone", details: nil))
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func testNetwork(host: String, port: UInt16, completion: @escaping (Bool, String) -> Void) {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      completion(false, "منفذ الطابعة غير صالح")
      return
    }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
    var finished = false
    func finish(_ ok: Bool, _ message: String) {
      if finished { return }
      finished = true
      connection.cancel()
      DispatchQueue.main.async { completion(ok, message) }
    }
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: finish(true, "تم الاتصال بالطابعة عبر الشبكة")
      case .failed(let error): finish(false, "تعذر الاتصال بالطابعة عبر الشبكة: \(error.localizedDescription)")
      case .cancelled: if !finished { finish(false, "تم إلغاء الاتصال بالطابعة") }
      default: break
      }
    }
    connection.start(queue: networkQueue)
    networkQueue.asyncAfter(deadline: .now() + 6.0) {
      finish(false, "انتهت مهلة الاتصال بالطابعة عبر الشبكة")
    }
  }

  private func sendNetwork(data: Data, host: String, port: UInt16, completion: @escaping (Bool, String) -> Void) {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      completion(false, "منفذ الطابعة غير صالح")
      return
    }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
    var finished = false
    func finish(_ ok: Bool, _ message: String) {
      if finished { return }
      finished = true
      connection.cancel()
      DispatchQueue.main.async { completion(ok, message) }
    }
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(content: data, completion: .contentProcessed { error in
          if let error = error {
            finish(false, "فشلت الطباعة عبر الشبكة: \(error.localizedDescription)")
          } else {
            finish(true, "تم إرسال الإيصال للطابعة عبر الشبكة")
          }
        })
      case .failed(let error): finish(false, "تعذر الاتصال بالطابعة عبر الشبكة: \(error.localizedDescription)")
      default: break
      }
    }
    connection.start(queue: networkQueue)
    networkQueue.asyncAfter(deadline: .now() + 12.0) {
      finish(false, "انتهت مهلة الطباعة عبر الشبكة")
    }
  }

  private func buildReceiptPayload(images: [Data], widthPx: Int, autoCut: Bool, beep: Bool) -> Data? {
    var output = Data([0x1B, 0x40]) // ESC @ initialize
    for image in images {
      guard let raster = escPosRaster(from: image, targetWidth: widthPx) else { return nil }
      output.append(raster)
      output.append(contentsOf: [0x0A, 0x0A])
    }
    if beep {
      output.append(contentsOf: [0x1B, 0x42, 0x03, 0x02])
    }
    if autoCut {
      output.append(contentsOf: [0x1D, 0x56, 0x42, 0x00])
    } else {
      output.append(contentsOf: [0x0A, 0x0A, 0x0A])
    }
    return output
  }

  private func escPosRaster(from pngData: Data, targetWidth: Int) -> Data? {
    guard let image = UIImage(data: pngData), let source = image.cgImage else { return nil }
    let sourceWidth = source.width
    let sourceHeight = source.height
    guard sourceWidth > 0, sourceHeight > 0 else { return nil }

    let width = max(8, targetWidth)
    let height = max(1, Int((Double(sourceHeight) * Double(width) / Double(sourceWidth)).rounded()))
    var gray = [UInt8](repeating: 255, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(
      data: &gray,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.setFillColor(gray: 1.0, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // Printing.raster() arrives mirrored horizontally on the iOS direct-thermal
    // path used by this project. Flip both axes before converting to ESC/POS:
    // Y restores CoreGraphics image orientation, X cancels the iOS mirror.
    context.translateBy(x: CGFloat(width), y: CGFloat(height))
    context.scaleBy(x: -1, y: -1)
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    let bytesPerRow = (width + 7) / 8
    var bits = Data(count: bytesPerRow * height)
    bits.withUnsafeMutableBytes { rawBuffer in
      guard let dst = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      for y in 0..<height {
        for x in 0..<width {
          // Thermal-friendly threshold. Darker pixel -> printed dot.
          if gray[y * width + x] < 180 {
            dst[y * bytesPerRow + (x / 8)] |= UInt8(0x80 >> (x % 8))
          }
        }
      }
    }

    let xL = UInt8(bytesPerRow & 0xFF)
    let xH = UInt8((bytesPerRow >> 8) & 0xFF)
    let yL = UInt8(height & 0xFF)
    let yH = UInt8((height >> 8) & 0xFF)
    var command = Data([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH])
    command.append(bits)
    return command
  }
}

private final class HalaBLEPrinterManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private var central: CBCentralManager!
  private var discovered: [UUID: CBPeripheral] = [:]
  private var scanCompletion: (([CBPeripheral]) -> Void)?
  private var permissionCompletion: ((Bool) -> Void)?

  private var targetIdentifier: UUID?
  private var activePeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var operationCompletion: ((Bool, String) -> Void)?
  private var payload: Data?
  private var writeOffset = 0
  private var writeChunkSize = 180
  private var waitingForWriteResponse = false
  private var operationToken = UUID()

  override init() {
    super.init()
  }

  private func ensureCentral() {
    if central == nil {
      central = CBCentralManager(delegate: self, queue: .main)
    }
  }

  func requestPermission(completion: @escaping (Bool) -> Void) {
    DispatchQueue.main.async {
      self.ensureCentral()
      switch self.central.state {
      case .poweredOn: completion(true)
      case .unauthorized, .unsupported: completion(false)
      default: self.permissionCompletion = completion
      }
    }
  }

  func scan(timeout: TimeInterval, completion: @escaping ([CBPeripheral]) -> Void) {
    DispatchQueue.main.async {
      self.ensureCentral()
      guard self.central.state == .poweredOn else {
        self.permissionCompletion = { allowed in
          if allowed { self.scan(timeout: timeout, completion: completion) }
          else { completion([]) }
        }
        return
      }
      self.discovered.removeAll()
      self.scanCompletion = completion
      self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
      let token = UUID()
      self.operationToken = token
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        guard self.operationToken == token else { return }
        self.finishScan()
      }
    }
  }

  func testConnection(identifier: UUID, completion: @escaping (Bool, String) -> Void) {
    connect(identifier: identifier, payload: nil, completion: completion)
  }

  func print(identifier: UUID, data: Data, completion: @escaping (Bool, String) -> Void) {
    connect(identifier: identifier, payload: data, completion: completion)
  }

  private func connect(identifier: UUID, payload: Data?, completion: @escaping (Bool, String) -> Void) {
    DispatchQueue.main.async {
      self.ensureCentral()
      guard self.central.state == .poweredOn else {
        completion(false, "Bluetooth غير متاح أو غير مسموح على iPhone")
        return
      }
      self.cancelActiveOperation()
      self.targetIdentifier = identifier
      self.payload = payload
      self.operationCompletion = completion
      self.writeOffset = 0
      self.writeCharacteristic = nil
      self.waitingForWriteResponse = false

      var peripheral = self.discovered[identifier]
      if peripheral == nil {
        peripheral = self.central.retrievePeripherals(withIdentifiers: [identifier]).first
      }
      guard let target = peripheral else {
        self.finishOperation(false, "لم يتم العثور على الطابعة. شغّل البحث واختر الطابعة من جديد")
        return
      }
      self.activePeripheral = target
      target.delegate = self
      self.central.connect(target, options: nil)
      let token = UUID()
      self.operationToken = token
      DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
        guard self.operationToken == token, self.operationCompletion != nil else { return }
        self.finishOperation(false, "انتهت مهلة الاتصال بطابعة Bluetooth")
      }
    }
  }

  private func finishScan() {
    central.stopScan()
    let devices = discovered.values.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    let completion = scanCompletion
    scanCompletion = nil
    completion?(devices)
  }

  private func cancelActiveOperation() {
    if let peripheral = activePeripheral {
      central?.cancelPeripheralConnection(peripheral)
    }
    activePeripheral = nil
    writeCharacteristic = nil
    payload = nil
    operationCompletion = nil
  }

  private func finishOperation(_ ok: Bool, _ message: String) {
    let completion = operationCompletion
    operationCompletion = nil
    payload = nil
    writeCharacteristic = nil
    writeOffset = 0
    operationToken = UUID()
    if let peripheral = activePeripheral {
      central?.cancelPeripheralConnection(peripheral)
    }
    activePeripheral = nil
    completion?(ok, message)
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if let completion = permissionCompletion {
      switch central.state {
      case .poweredOn:
        permissionCompletion = nil
        completion(true)
      case .unauthorized, .unsupported:
        permissionCompletion = nil
        completion(false)
      default:
        break
      }
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    if peripheral.name != nil || advertisedName != nil {
      discovered[peripheral.identifier] = peripheral
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.delegate = self
    peripheral.discoverServices(nil)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    finishOperation(false, "تعذر الاتصال بالطابعة: \(error?.localizedDescription ?? "خطأ غير معروف")")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if operationCompletion != nil && writeOffset == 0 {
      finishOperation(false, "انقطع اتصال Bluetooth بالطابعة")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error = error {
      finishOperation(false, "تعذر قراءة خدمات الطابعة: \(error.localizedDescription)")
      return
    }
    guard let services = peripheral.services, !services.isEmpty else {
      finishOperation(false, "لم تعرض الطابعة خدمات Bluetooth قابلة للطباعة")
      return
    }
    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if writeCharacteristic != nil { return }
    guard error == nil, let characteristics = service.characteristics else { return }

    // Prefer writeWithoutResponse for thermal printers, then normal write.
    if let c = characteristics.first(where: { $0.properties.contains(.writeWithoutResponse) }) {
      foundWriteCharacteristic(c, on: peripheral)
      return
    }
    if let c = characteristics.first(where: { $0.properties.contains(.write) }) {
      foundWriteCharacteristic(c, on: peripheral)
      return
    }

    // Wait briefly for other services before declaring failure.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
      guard self.operationCompletion != nil, self.writeCharacteristic == nil else { return }
      self.finishOperation(false, "اتصلنا بالطابعة لكن لم نجد قناة كتابة BLE. قد تحتاج الطابعة تطبيق/SDK الشركة أو اتصال Wi‑Fi.")
    }
  }

  private func foundWriteCharacteristic(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
    guard writeCharacteristic == nil else { return }
    writeCharacteristic = characteristic
    let maxWithout = peripheral.maximumWriteValueLength(for: .withoutResponse)
    let maxWith = peripheral.maximumWriteValueLength(for: .withResponse)
    writeChunkSize = max(20, min(512, characteristic.properties.contains(.writeWithoutResponse) ? maxWithout : maxWith))

    guard let payload = payload else {
      finishOperation(true, "تم الاتصال بطابعة Bluetooth والعثور على قناة كتابة")
      return
    }
    if payload.isEmpty {
      finishOperation(false, "بيانات الطباعة فارغة")
      return
    }
    sendNextChunk()
  }

  private func sendNextChunk() {
    guard let peripheral = activePeripheral,
          let characteristic = writeCharacteristic,
          let data = payload else { return }
    if writeOffset >= data.count {
      finishOperation(true, "تم إرسال الإيصال للطابعة عبر Bluetooth")
      return
    }

    let end = min(data.count, writeOffset + writeChunkSize)
    let chunk = data.subdata(in: writeOffset..<end)
    if characteristic.properties.contains(.writeWithoutResponse) {
      if peripheral.canSendWriteWithoutResponse {
        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
        writeOffset = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { self.sendNextChunk() }
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self.sendNextChunk() }
      }
    } else {
      waitingForWriteResponse = true
      peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
      writeOffset = end
    }
  }

  func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    if payload != nil { sendNextChunk() }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    waitingForWriteResponse = false
    if let error = error {
      finishOperation(false, "فشل إرسال بيانات الطباعة: \(error.localizedDescription)")
      return
    }
    sendNextChunk()
  }
}
