package com.halatalab.partners

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {
    private var pendingBluetoothPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val CHANNEL = "com.halatalab.partners/direct_printer"
        private const val BLUETOOTH_PERMISSION_REQUEST = 9042
        private const val USB_PERMISSION_ACTION = "com.halatalab.partners.USB_PERMISSION"
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createHalaTalabNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBluetoothPermission" -> {
                    val missing = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                            missing.add(Manifest.permission.BLUETOOTH_CONNECT)
                        }
                        if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                            missing.add(Manifest.permission.BLUETOOTH_SCAN)
                        }
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                            missing.add(Manifest.permission.ACCESS_FINE_LOCATION)
                        }
                    }
                    if (missing.isNotEmpty()) {
                        pendingBluetoothPermissionResult?.success(false)
                        pendingBluetoothPermissionResult = result
                        requestPermissions(missing.toTypedArray(), BLUETOOTH_PERMISSION_REQUEST)
                    } else {
                        result.success(true)
                    }
                }
                "openBluetoothSettings" -> {
                    startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                }
                "listPrinters" -> {
                    val transport = call.argument<String>("transport") ?: "bluetooth"
                    if (transport == "ble") {
                        Thread {
                            try {
                                val devices = listBlePrinters()
                                runOnUiThread { result.success(devices) }
                            } catch (e: PrinterException) {
                                runOnUiThread { result.error(e.code, e.message, null) }
                            } catch (e: SecurityException) {
                                runOnUiThread { result.error("BLUETOOTH_PERMISSION_REQUIRED", "Bluetooth permission is required", null) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("LIST_FAILED", e.message, null) }
                            }
                        }.start()
                    } else {
                        try {
                            result.success(listDirectPrinters(transport))
                        } catch (e: SecurityException) {
                            result.error("BLUETOOTH_PERMISSION_REQUIRED", "Bluetooth permission is required", null)
                        } catch (e: Exception) {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }
                }
                "testConnection" -> {
                    Thread {
                        try {
                            val transport = call.argument<String>("transport") ?: "bluetooth"
                            val deviceId = call.argument<String>("deviceId")
                            val host = call.argument<String>("host")
                            val port = call.argument<Int>("port") ?: 9100
                            when (transport) {
                                "bluetooth" -> testBluetoothConnection(deviceId)
                                "ble" -> testBleConnection(deviceId)
                                "usb" -> testUsbConnection(deviceId)
                                "network" -> testNetworkConnection(host, port)
                                else -> throw IllegalArgumentException("Unsupported printer transport")
                            }
                            runOnUiThread { result.success(true) }
                        } catch (e: PrinterException) {
                            runOnUiThread { result.error(e.code, e.message, null) }
                        } catch (e: SecurityException) {
                            runOnUiThread { result.error("BLUETOOTH_PERMISSION_REQUIRED", "Bluetooth permission is required", null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CONNECTION_FAILED", e.message ?: "Printer connection failed", null) }
                        }
                    }.start()
                }
                "printRaster" -> {
                    Thread {
                        try {
                            val transport = call.argument<String>("transport") ?: "bluetooth"
                            val deviceId = call.argument<String>("deviceId")
                            val host = call.argument<String>("host")
                            val port = call.argument<Int>("port") ?: 9100
                            val widthPx = call.argument<Int>("widthPx") ?: 576
                            val autoCut = call.argument<Boolean>("autoCut") ?: true
                            val beep = call.argument<Boolean>("beep") ?: false
                            @Suppress("UNCHECKED_CAST")
                            val images = call.argument<List<ByteArray>>("images") ?: emptyList()
                            if (images.isEmpty()) throw IllegalArgumentException("No receipt image was supplied")

                            when (transport) {
                                "bluetooth" -> printBluetooth(deviceId, images, widthPx, autoCut, beep)
                                "ble" -> printBle(deviceId, images, widthPx, autoCut, beep)
                                "usb" -> printUsb(deviceId, images, widthPx, autoCut, beep)
                                "network" -> printNetwork(host, port, images, widthPx, autoCut, beep)
                                else -> throw IllegalArgumentException("Unsupported printer transport")
                            }
                            runOnUiThread { result.success(true) }
                        } catch (e: PrinterException) {
                            runOnUiThread { result.error(e.code, e.message, null) }
                        } catch (e: SecurityException) {
                            runOnUiThread { result.error("BLUETOOTH_PERMISSION_REQUIRED", "Bluetooth permission is required", null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PRINT_FAILED", e.message ?: "Printing failed", null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }


    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BLUETOOTH_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingBluetoothPermissionResult?.success(granted)
            pendingBluetoothPermissionResult = null
        }
    }

    private fun listDirectPrinters(transport: String): List<Map<String, Any?>> {
        return when (transport) {
            "bluetooth" -> listBluetoothPrinters()
            "usb" -> listUsbPrinters()
            else -> emptyList()
        }
    }

    private fun ensureBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectMissing = checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
            val scanMissing = checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED
            if (connectMissing || scanMissing) {
                throw PrinterException("BLUETOOTH_PERMISSION_REQUIRED", "اسمح للتطبيق بالوصول إلى Bluetooth ثم أعد المحاولة")
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                throw PrinterException("BLUETOOTH_PERMISSION_REQUIRED", "اسمح بصلاحية الموقع المطلوبة للبحث عن أجهزة Bluetooth على هذا الإصدار من Android")
            }
        }
    }

    private fun requireBluetoothAdapter(): BluetoothAdapter {
        ensureBluetoothPermission()
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw PrinterException("DEVICE_NOT_FOUND", "Bluetooth غير متوفر على هذا الجهاز")
        if (!adapter.isEnabled) {
            throw PrinterException("CONNECTION_FAILED", "Bluetooth غير مفعّل. فعّله ثم أعد المحاولة")
        }
        return adapter
    }

    private fun listBluetoothPrinters(): List<Map<String, Any?>> {
        val adapter = requireBluetoothAdapter()
        return adapter.bondedDevices
            .sortedBy { it.name ?: it.address }
            .map { device ->
                mapOf(
                    "id" to device.address,
                    "name" to (device.name ?: "Bluetooth ${device.address}"),
                    "transport" to "bluetooth",
                    "address" to device.address
                )
            }
    }


    private fun listBlePrinters(): List<Map<String, Any?>> {
        val adapter = requireBluetoothAdapter()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            throw PrinterException("CONNECTION_FAILED", "Bluetooth Low Energy يحتاج Android 5.0 أو أحدث")
        }
        val scanner = adapter.bluetoothLeScanner
            ?: throw PrinterException("CONNECTION_FAILED", "تعذر تشغيل البحث عن أجهزة Bluetooth Low Energy")
        val found = linkedMapOf<String, Map<String, Any?>>()
        val finished = CountDownLatch(1)
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                val address = try { device.address } catch (_: Exception) { return }
                val name = try {
                    device.name ?: result.scanRecord?.deviceName ?: "BLE $address"
                } catch (_: Exception) {
                    "BLE $address"
                }
                synchronized(found) {
                    found[address] = mapOf(
                        "id" to address,
                        "name" to name,
                        "transport" to "ble",
                        "address" to address
                    )
                }
            }

            override fun onScanFailed(errorCode: Int) {
                finished.countDown()
            }
        }
        try {
            scanner.startScan(callback)
            finished.await(4500, TimeUnit.MILLISECONDS)
        } finally {
            try { scanner.stopScan(callback) } catch (_: Exception) {}
        }
        return synchronized(found) {
            found.values.sortedBy { it["name"].toString().lowercase() }
        }
    }

    private data class BleConnection(
        val gatt: BluetoothGatt,
        val characteristic: BluetoothGattCharacteristic,
        val session: BleGattSession
    )

    private inner class BleGattSession : BluetoothGattCallback() {
        val connected = CountDownLatch(1)
        val mtuReady = CountDownLatch(1)
        val servicesReady = CountDownLatch(1)
        val writeReady = AtomicReference<CountDownLatch?>(null)
        @Volatile var connectionStatus: Int = -1
        @Volatile var serviceStatus: Int = -1
        @Volatile var writeStatus: Int = -1
        @Volatile var mtu: Int = 23

        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            connectionStatus = if (newState == BluetoothProfile.STATE_CONNECTED) 0 else status
            connected.countDown()
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && mtu > 23) this.mtu = mtu
            mtuReady.countDown()
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            serviceStatus = status
            servicesReady.countDown()
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            writeStatus = status
            writeReady.getAndSet(null)?.countDown()
        }
    }

    private fun connectBlePrinter(deviceId: String?): BleConnection {
        if (deviceId.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "اختر طابعة Bluetooth Low Energy")
        val adapter = requireBluetoothAdapter()
        val device = try { adapter.getRemoteDevice(deviceId) } catch (_: Exception) {
            throw PrinterException("DEVICE_NOT_FOUND", "تعذر العثور على جهاز Bluetooth Low Energy")
        }
        val session = BleGattSession()
        val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(this, false, session, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(this, false, session)
        }
        if (!session.connected.await(8, TimeUnit.SECONDS) || session.connectionStatus != 0) {
            try { gatt.close() } catch (_: Exception) {}
            throw PrinterException("CONNECTION_FAILED", "تعذر الاتصال بطابعة Bluetooth Low Energy")
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try { gatt.requestMtu(247) } catch (_: Exception) {}
                session.mtuReady.await(1200, TimeUnit.MILLISECONDS)
            }
            if (!gatt.discoverServices()) {
                throw PrinterException("CONNECTION_FAILED", "تعذر قراءة خدمات طابعة Bluetooth Low Energy")
            }
            if (!session.servicesReady.await(8, TimeUnit.SECONDS) || session.serviceStatus != BluetoothGatt.GATT_SUCCESS) {
                throw PrinterException("CONNECTION_FAILED", "تعذر اكتشاف خدمة الطباعة في جهاز Bluetooth Low Energy")
            }
            val characteristic = findBleWritableCharacteristic(gatt)
                ?: throw PrinterException("DEVICE_NOT_FOUND", "الجهاز متصل لكن لم يتم العثور على قناة كتابة للطباعة. قد يحتاج تعريف الشركة الخاص.")
            return BleConnection(gatt, characteristic, session)
        } catch (e: Exception) {
            try { gatt.disconnect() } catch (_: Exception) {}
            try { gatt.close() } catch (_: Exception) {}
            if (e is PrinterException) throw e
            throw PrinterException("CONNECTION_FAILED", e.message ?: "تعذر تجهيز اتصال Bluetooth Low Energy")
        }
    }

    private fun findBleWritableCharacteristic(gatt: BluetoothGatt): BluetoothGattCharacteristic? {
        val preferred = listOf(
            "0000ff02-0000-1000-8000-00805f9b34fb",
            "0000ff01-0000-1000-8000-00805f9b34fb",
            "0000ffe1-0000-1000-8000-00805f9b34fb",
            "6e400002-b5a3-f393-e0a9-e50e24dcca9e",
            "49535343-8841-43f4-a8d4-ecbe34729bb3"
        ).map { UUID.fromString(it) }
        val all = gatt.services.flatMap { it.characteristics }
        for (uuid in preferred) {
            val match = all.firstOrNull { it.uuid == uuid && isBleWritable(it) }
            if (match != null) return match
        }
        return all.firstOrNull { isBleWritable(it) }
    }

    private fun isBleWritable(characteristic: BluetoothGattCharacteristic): Boolean {
        val p = characteristic.properties
        return (p and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0 ||
            (p and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
    }

    private fun testBleConnection(deviceId: String?) {
        val connection = connectBlePrinter(deviceId)
        try {
            // Discovering a writable characteristic is enough for a safe connection test.
        } finally {
            try { connection.gatt.disconnect() } catch (_: Exception) {}
            try { connection.gatt.close() } catch (_: Exception) {}
        }
    }

    private fun printBle(
        deviceId: String?,
        images: List<ByteArray>,
        widthPx: Int,
        autoCut: Boolean,
        beep: Boolean
    ) {
        val connection = connectBlePrinter(deviceId)
        try {
            val payload = buildReceiptPayload(images, widthPx, autoCut, beep)
            writeBlePayload(connection, payload)
        } finally {
            try { connection.gatt.disconnect() } catch (_: Exception) {}
            try { connection.gatt.close() } catch (_: Exception) {}
        }
    }

    @Suppress("DEPRECATION")
    private fun writeBlePayload(connection: BleConnection, payload: ByteArray) {
        val characteristic = connection.characteristic
        val noResponse = (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
        characteristic.writeType = if (noResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }
        val chunkSize = (connection.session.mtu - 3).coerceIn(20, 180)
        var offset = 0
        while (offset < payload.size) {
            val len = minOf(chunkSize, payload.size - offset)
            val chunk = payload.copyOfRange(offset, offset + len)
            characteristic.value = chunk
            if (noResponse) {
                if (!connection.gatt.writeCharacteristic(characteristic)) {
                    throw PrinterException("PRINT_FAILED", "فشل إرسال البيانات إلى طابعة Bluetooth Low Energy")
                }
                Thread.sleep(12)
            } else {
                val latch = CountDownLatch(1)
                connection.session.writeStatus = -1
                connection.session.writeReady.set(latch)
                if (!connection.gatt.writeCharacteristic(characteristic)) {
                    connection.session.writeReady.set(null)
                    throw PrinterException("PRINT_FAILED", "فشل بدء إرسال البيانات إلى طابعة Bluetooth Low Energy")
                }
                if (!latch.await(5, TimeUnit.SECONDS) || connection.session.writeStatus != BluetoothGatt.GATT_SUCCESS) {
                    throw PrinterException("PRINT_FAILED", "لم تؤكد طابعة Bluetooth Low Energy استلام البيانات")
                }
            }
            offset += len
        }
    }

    private fun listUsbPrinters(): List<Map<String, Any?>> {
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        return usbManager.deviceList.values.map { device ->
            mapOf(
                "id" to device.deviceName,
                "name" to usbDisplayName(device),
                "transport" to "usb",
                "vendorId" to device.vendorId,
                "productId" to device.productId
            )
        }.sortedBy { it["name"].toString() }
    }

    private fun usbDisplayName(device: UsbDevice): String {
        val product = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) device.productName else null
        val manufacturer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) device.manufacturerName else null
        return listOfNotNull(manufacturer, product)
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .ifBlank { "USB ${device.vendorId}:${device.productId}" }
    }

    private fun testBluetoothConnection(deviceId: String?) {
        if (deviceId.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "اختر طابعة Bluetooth")
        val adapter = requireBluetoothAdapter()
        val device = try { adapter.getRemoteDevice(deviceId) } catch (_: Exception) {
            throw PrinterException("DEVICE_NOT_FOUND", "تعذر العثور على طابعة Bluetooth")
        }
        connectBluetoothSocket(adapter, device).use { socket ->
            if (!socket.isConnected) throw PrinterException("CONNECTION_FAILED", "تعذر الاتصال بطابعة Bluetooth")
        }
    }

    private fun testUsbConnection(deviceId: String?) {
        if (deviceId.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "اختر طابعة USB")
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val device = usbManager.deviceList[deviceId]
            ?: usbManager.deviceList.values.firstOrNull { it.deviceName == deviceId }
            ?: throw PrinterException("DEVICE_NOT_FOUND", "طابعة USB غير متصلة")
        if (!usbManager.hasPermission(device)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val permissionIntent = PendingIntent.getBroadcast(this, 0, Intent(USB_PERMISSION_ACTION), flags)
            usbManager.requestPermission(device, permissionIntent)
            throw PrinterException("USB_PERMISSION_REQUIRED", "وافق على صلاحية USB ثم أعد الاختبار")
        }
        if (findUsbOutput(device) == null) {
            throw PrinterException("DEVICE_NOT_FOUND", "لم يتم العثور على منفذ طباعة USB")
        }
        val connection = usbManager.openDevice(device)
            ?: throw PrinterException("CONNECTION_FAILED", "تعذر فتح اتصال USB")
        connection.close()
    }

    private fun testNetworkConnection(host: String?, port: Int) {
        if (host.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "أدخل IP للطابعة")
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), 3000)
        }
    }

    private fun printBluetooth(
        deviceId: String?,
        images: List<ByteArray>,
        widthPx: Int,
        autoCut: Boolean,
        beep: Boolean
    ) {
        if (deviceId.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "اختر طابعة Bluetooth")
        val adapter = requireBluetoothAdapter()
        val device: BluetoothDevice = try {
            adapter.getRemoteDevice(deviceId)
        } catch (_: Exception) {
            throw PrinterException("DEVICE_NOT_FOUND", "تعذر العثور على طابعة Bluetooth")
        }

        connectBluetoothSocket(adapter, device).use { socket ->
            val out = socket.outputStream
            writeReceiptChunked(out, images, widthPx, autoCut, beep, 4096)
        }
    }

    private fun connectBluetoothSocket(adapter: BluetoothAdapter, device: BluetoothDevice): android.bluetooth.BluetoothSocket {
        adapter.cancelDiscovery()
        val attempts = mutableListOf<() -> android.bluetooth.BluetoothSocket>()
        attempts.add { device.createRfcommSocketToServiceRecord(SPP_UUID) }
        attempts.add { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) }
        // A number of classic ESC/POS printers expose SPP only on RFCOMM channel 1.
        // Reflection is used only as a last compatibility fallback.
        attempts.add {
            val method = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
            method.invoke(device, 1) as android.bluetooth.BluetoothSocket
        }

        var lastError: Exception? = null
        for (factory in attempts) {
            var socket: android.bluetooth.BluetoothSocket? = null
            try {
                socket = factory()
                socket.connect()
                return socket
            } catch (e: Exception) {
                lastError = e
                try { socket?.close() } catch (_: Exception) {}
            }
        }
        throw PrinterException("CONNECTION_FAILED", lastError?.message ?: "تعذر الاتصال بطابعة Bluetooth")
    }

    private fun printUsb(
        deviceId: String?,
        images: List<ByteArray>,
        widthPx: Int,
        autoCut: Boolean,
        beep: Boolean
    ) {
        if (deviceId.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "اختر طابعة USB")
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val device = usbManager.deviceList[deviceId]
            ?: usbManager.deviceList.values.firstOrNull { it.deviceName == deviceId }
            ?: throw PrinterException("DEVICE_NOT_FOUND", "طابعة USB غير متصلة")

        if (!usbManager.hasPermission(device)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val permissionIntent = PendingIntent.getBroadcast(
                this,
                0,
                Intent(USB_PERMISSION_ACTION),
                flags
            )
            usbManager.requestPermission(device, permissionIntent)
            throw PrinterException("USB_PERMISSION_REQUIRED", "وافق على صلاحية USB ثم أعد المحاولة")
        }

        val target = findUsbOutput(device)
            ?: throw PrinterException("DEVICE_NOT_FOUND", "لم يتم العثور على منفذ طباعة USB")
        val connection: UsbDeviceConnection = usbManager.openDevice(device)
            ?: throw PrinterException("PRINT_FAILED", "تعذر فتح اتصال USB")
        try {
            if (!connection.claimInterface(target.first, true)) {
                throw PrinterException("PRINT_FAILED", "تعذر حجز واجهة USB")
            }
            val payload = buildReceiptPayload(images, widthPx, autoCut, beep)
            var offset = 0
            while (offset < payload.size) {
                val len = minOf(4096, payload.size - offset)
                val chunk = payload.copyOfRange(offset, offset + len)
                var written = connection.bulkTransfer(target.second, chunk, chunk.size, 5000)
                if (written <= 0) {
                    Thread.sleep(25)
                    written = connection.bulkTransfer(target.second, chunk, chunk.size, 5000)
                }
                if (written <= 0) throw PrinterException("PRINT_FAILED", "فشل إرسال البيانات إلى طابعة USB")
                offset += written
            }
        } finally {
            try { connection.releaseInterface(target.first) } catch (_: Exception) {}
            connection.close()
        }
    }

    private fun findUsbOutput(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            for (e in 0 until intf.endpointCount) {
                val endpoint = intf.getEndpoint(e)
                if (endpoint.direction == UsbConstants.USB_DIR_OUT &&
                    (endpoint.type == UsbConstants.USB_ENDPOINT_XFER_BULK ||
                     endpoint.type == UsbConstants.USB_ENDPOINT_XFER_INT)
                ) {
                    return Pair(intf, endpoint)
                }
            }
        }
        return null
    }

    private fun printNetwork(
        host: String?,
        port: Int,
        images: List<ByteArray>,
        widthPx: Int,
        autoCut: Boolean,
        beep: Boolean
    ) {
        if (host.isNullOrBlank()) throw PrinterException("DEVICE_NOT_FOUND", "أدخل IP للطابعة")
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), 5000)
            socket.soTimeout = 5000
            writeReceiptChunked(socket.getOutputStream(), images, widthPx, autoCut, beep, 8192)
        }
    }

    private fun writeReceiptChunked(
        out: OutputStream,
        images: List<ByteArray>,
        widthPx: Int,
        autoCut: Boolean,
        beep: Boolean,
        chunkSize: Int
    ) {
        val payload = buildReceiptPayload(images, widthPx, autoCut, beep)
        var offset = 0
        while (offset < payload.size) {
            val len = minOf(chunkSize, payload.size - offset)
            out.write(payload, offset, len)
            out.flush()
            offset += len
            // Small pause protects low-buffer Bluetooth/network thermal printers
            // from being overrun by a full-page raster payload.
            if (offset < payload.size) Thread.sleep(8)
        }
    }

    private fun buildReceiptPayload(
        images: List<ByteArray>,
        widthPx: Int,
        autoCut: Boolean,
        beep: Boolean
    ): ByteArray {
        val buffer = ByteArrayOutputStream()
        buffer.write(byteArrayOf(0x1B, 0x40)) // ESC @ initialize
        buffer.write(byteArrayOf(0x1B, 0x61, 0x01)) // center
        images.forEach { png ->
            val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size)
                ?: throw PrinterException("PRINT_FAILED", "تعذر قراءة صورة الإيصال")
            buffer.write(bitmapToRaster(bitmap, widthPx))
            buffer.write(byteArrayOf(0x0A, 0x0A))
            if (!bitmap.isRecycled) bitmap.recycle()
        }
        buffer.write(byteArrayOf(0x1B, 0x61, 0x00))
        if (beep) {
            // ESC B n t: common buzzer command; unsupported printers safely ignore it.
            buffer.write(byteArrayOf(0x1B, 0x42, 0x02, 0x02))
        }
        buffer.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x0A))
        if (autoCut) {
            buffer.write(byteArrayOf(0x1D, 0x56, 0x00)) // GS V 0 full cut
        }
        return buffer.toByteArray()
    }

    private fun bitmapToRaster(source: Bitmap, requestedWidth: Int): ByteArray {
        val width = requestedWidth.coerceIn(200, 1024)
        val scaled = if (source.width == width) {
            source
        } else {
            val height = (source.height.toDouble() * width / source.width).toInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(source, width, height, true)
        }

        val bytesPerRow = (scaled.width + 7) / 8
        val height = scaled.height
        val data = ByteArray(bytesPerRow * height)
        var index = 0
        for (y in 0 until height) {
            for (xByte in 0 until bytesPerRow) {
                var value = 0
                for (bit in 0 until 8) {
                    val x = xByte * 8 + bit
                    if (x < scaled.width) {
                        val pixel = scaled.getPixel(x, y)
                        val a = (pixel ushr 24) and 0xFF
                        val r = (pixel ushr 16) and 0xFF
                        val g = (pixel ushr 8) and 0xFF
                        val b = pixel and 0xFF
                        val gray = (r * 30 + g * 59 + b * 11) / 100
                        val black = a > 32 && gray < 180
                        if (black) value = value or (1 shl (7 - bit))
                    }
                }
                data[index++] = value.toByte()
            }
        }

        val xL = bytesPerRow and 0xFF
        val xH = (bytesPerRow shr 8) and 0xFF
        val yL = height and 0xFF
        val yH = (height shr 8) and 0xFF
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0x1D, 0x76, 0x30, 0x00, xL.toByte(), xH.toByte(), yL.toByte(), yH.toByte()))
        out.write(data)
        if (scaled !== source && !scaled.isRecycled) scaled.recycle()
        return out.toByteArray()
    }

    private fun createHalaTalabNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "hala_talab_orders",
                "طلبات وإشعارات هلا طلب",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "إشعارات الطلبات والتنبيهات المهمة للمتجر والسائق"
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private class PrinterException(val code: String, message: String) : Exception(message)
}
