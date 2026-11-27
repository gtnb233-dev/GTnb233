package cn.survey.survey_pro

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.View
import android.view.WindowManager
import androidx.annotation.ColorInt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStreamReader
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/// Platform bridges for Survey Pro:
/// - `survey/theme`: Android 12+ Material You wallpaper accent color (`accentColor`)
/// - `survey/files`: SAF document picker (`pickDocument`), MediaStore gallery save (`savePngToGallery`) & system share (`shareImageUri`)
class MainActivity : FlutterActivity() {

    companion object {
        private const val kSurveyThemeChannel = "survey/theme"
        private const val kSurveyFilesChannel = "survey/files"
        private const val kSurveyGnssChannel = "survey/gnss"
        private const val REQUEST_PICK_DOCUMENT = 4102
        private const val REQUEST_GNSS_CONNECT = 4103
        private const val MAX_GGA_AGE_MS = 10_000L
        private const val MAX_DOCUMENT_BYTES = 16 * 1024 * 1024
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private var pendingPickDocumentResult: MethodChannel.Result? = null
    private var pendingReceiverList: MethodChannel.Result? = null
    private val gnssExecutor = Executors.newSingleThreadExecutor()
    private val gnssReader = Executors.newSingleThreadExecutor()
    private val gnssLock = Any()
    @Volatile
    private var gnssSocket: BluetoothSocket? = null
    @Volatile
    private var gnssDeviceName: String? = null
    @Volatile
    private var latestGga: Pair<Long, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val content = findViewById<View>(android.R.id.content)
        content.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            val density = view.resources.displayMetrics.density
            val landscape = view.width > view.height
            val widthDp = view.width / density
            val compact = widthDp < 720 && (!landscape || widthDp < 640)
            if (!compact || view.height == 0) {
                view.systemGestureExclusionRects = emptyList()
            } else {
                // Android reserves part of each edge for system Back. Give the
                // middle of the compact left edge to the Flutter drag recognizers.
                val height = minOf(view.height, (200 * density).roundToInt())
                val top = (view.height - height) / 2
                view.systemGestureExclusionRects =
                    listOf(Rect(0, top, (20 * density).roundToInt(), top + height))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, kSurveyThemeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "accentColor" -> result.success(systemAccentColor())
                    "setKeepScreenOn" -> {
                        val enabled = (call.arguments as? Boolean) ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, kSurveyFilesChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePngToGallery" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val rawFilename = call.argument<String>("filename")
                            ?.trim()
                            ?.substringAfterLast('/')
                            ?.substringAfterLast('\\')
                            ?.takeIf { it.isNotBlank() && it != "." && it != ".." }
                            ?: "survey_pro.png"
                        val rawAlbum = call.argument<String>("album")
                            ?.trim()
                            ?.replace("..", "")
                            ?.trim('/', '\\')
                            ?.takeIf { it.isNotBlank() }
                            ?: "SurveyPro"
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("INVALID_ARGS", "PNG bytes must not be empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val saved = savePngToMediaStore(bytes, rawFilename, rawAlbum)
                            result.success(saved)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    "shareImageUri" -> {
                        val uriStr = call.argument<String>("uri")
                        val subject = call.argument<String>("subject")
                        val mimeType = call.argument<String>("mimeType")
                            ?.takeIf { it.isNotBlank() } ?: "image/png"
                        if (uriStr.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val ok = shareContentUri(uriStr, subject, mimeType)
                        result.success(ok)
                    }

                    "pickDocument" -> {
                        if (pendingPickDocumentResult != null) {
                            result.error(
                                "PICKER_BUSY",
                                "A document picker request is already active",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        pendingPickDocumentResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf(
                                    "text/plain",
                                    "text/csv",
                                    "text/comma-separated-values",
                                    "application/csv",
                                    "application/dxf",
                                    "image/vnd.dxf",
                                    "application/octet-stream",
                                    "*/*",
                                ),
                            )
                        }
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, REQUEST_PICK_DOCUMENT)
                        } catch (e: Exception) {
                            pendingPickDocumentResult = null
                            result.error("PICKER_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, kSurveyGnssChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(gnssSocket?.isConnected == true)
                    "pairedReceivers" -> listReceiversWithPermission(result)
                    "connect" -> {
                        val address = call.argument<String>("deviceAddress")
                        gnssExecutor.execute {
                            val ok = !address.isNullOrBlank() && connectGnssSpp(address)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                    "disconnect" -> {
                        disconnectGnssSpp()
                        result.success(null)
                    }
                    "readLatestGga" -> {
                        result.success(synchronized(gnssLock) {
                            val connected = gnssSocket?.isConnected == true
                            val fresh = latestGga?.takeIf {
                                connected && SystemClock.elapsedRealtime() - it.first <= MAX_GGA_AGE_MS
                            }
                            mapOf(
                                "connected" to connected,
                                "simulated" to false,
                                "deviceName" to gnssDeviceName,
                                "rawGga" to fresh?.second,
                            )
                        })
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_GNSS_CONNECT) return
        val pending = pendingReceiverList
        pendingReceiverList = null
        pending?.success(pairedReceivers())
    }

    override fun onDestroy() {
        pendingReceiverList?.success(emptyList<Map<String, String>>())
        pendingReceiverList = null
        gnssExecutor.shutdownNow()
        disconnectGnssSpp()
        gnssReader.shutdownNow()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_DOCUMENT) {
            val pending = pendingPickDocumentResult
            pendingPickDocumentResult = null
            if (pending == null) return
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                pending.success(null)
                return
            }
            try {
                val fileName = queryDisplayName(uri)
                val bytes = readUriBytes(uri, MAX_DOCUMENT_BYTES)
                pending.success(
                    mapOf(
                        "name" to fileName,
                        "bytes" to bytes,
                    ),
                )
            } catch (e: Exception) {
                pending.error("READ_FAILED", e.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun queryDisplayName(uri: Uri): String {
        val queried = runCatching {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) cursor.getString(idx) else null
                } else {
                    null
                }
            }
        }.getOrNull()
        if (!queried.isNullOrBlank()) return queried
        return uri.lastPathSegment
            ?.substringAfterLast('/')
            ?.takeIf { it.isNotBlank() }
            ?: "document"
    }

    private fun readUriBytes(uri: Uri, maxBytes: Int): ByteArray {
        val stream = contentResolver.openInputStream(uri)
            ?: throw IOException("Failed to open document input stream")
        return stream.use { input ->
            val buffer = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            var total = 0
            while (true) {
                val read = input.read(chunk)
                if (read < 0) break
                total += read
                if (total > maxBytes) {
                    throw IOException("Selected document exceeds 16 MB limit")
                }
                buffer.write(chunk, 0, read)
            }
            buffer.toByteArray()
        }
    }

    private fun savePngToMediaStore(
        bytes: ByteArray,
        filename: String,
        album: String,
    ): Map<String, String> {
        val relativePath = "${Environment.DIRECTORY_PICTURES}/$album"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val resolver = applicationContext.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Failed to create MediaStore record")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw IOException("Failed to open MediaStore output stream")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val done = ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }
                resolver.update(uri, done, null, null)
            }
        } catch (e: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
        return mapOf(
            "uri" to uri.toString(),
            "displayPath" to "Pictures/$album/$filename",
        )
    }

    private fun shareContentUri(uriStr: String, subject: String?, mimeType: String): Boolean {
        return runCatching {
            val uri = Uri.parse(uriStr)
            if (uri.scheme != "content") return false
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!subject.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(intent, subject)
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            true
        }.getOrDefault(false)
    }

    @ColorInt
    private fun systemAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val candidates = intArrayOf(
            android.R.color.system_accent1_500,
            android.R.color.system_accent1_400,
            android.R.color.system_accent1_600,
        )
        for (id in candidates) {
            val color = runCatching {
                ContextCompat.getColor(this, id)
            }.getOrNull()
            if (color != null && color != 0) return color
        }
        return null
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    private fun listReceiversWithPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasBluetoothConnectPermission()) {
            if (pendingReceiverList != null) {
                result.success(emptyList<Map<String, String>>())
                return
            }
            pendingReceiverList = result
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_GNSS_CONNECT)
            return
        }
        result.success(pairedReceivers())
    }

    @SuppressLint("MissingPermission")
    private fun pairedReceivers(): List<Map<String, String>> {
        if (!hasBluetoothConnectPermission()) return emptyList()
        return runCatching {
            bluetoothAdapter()?.bondedDevices.orEmpty().map {
                mapOf("address" to it.address, "name" to (it.name ?: it.address))
            }.sortedBy { it["name"] }
        }.getOrDefault(emptyList())
    }

    @SuppressLint("MissingPermission")
    private fun connectGnssSpp(deviceAddress: String): Boolean {
        if (!hasBluetoothConnectPermission()) return false
        val adapter = bluetoothAdapter() ?: return false
        val socket = runCatching {
            val target = adapter.bondedDevices.orEmpty()
                .firstOrNull { it.address.equals(deviceAddress, ignoreCase = true) }
                ?: return false
            val name = target.name ?: target.address
            val created = target.createRfcommSocketToServiceRecord(SPP_UUID)
            disconnectGnssSpp()
            synchronized(gnssLock) {
                if (gnssExecutor.isShutdown) {
                    created.close()
                    return false
                }
                gnssSocket = created
                gnssDeviceName = name
            }
            created
        }.getOrElse { return false }
        return runCatching {
            socket.connect()
            gnssReader.execute { readGnssStream(socket) }
            true
        }.getOrElse {
            disconnectGnssSpp(socket)
            false
        }
    }

    private fun readGnssStream(socket: BluetoothSocket) {
        runCatching {
            val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.US_ASCII))
            while (socket.isConnected) {
                val line = reader.readLine() ?: break
                val trimmed = line.trim()
                if (trimmed.startsWith("\$GPGGA", ignoreCase = true) ||
                    trimmed.startsWith("\$GNGGA", ignoreCase = true)
                ) {
                    synchronized(gnssLock) {
                        if (gnssSocket === socket) {
                            latestGga = SystemClock.elapsedRealtime() to trimmed
                        }
                    }
                }
            }
        }
        disconnectGnssSpp(socket)
    }

    private fun disconnectGnssSpp(expected: BluetoothSocket? = null) {
        val socket = synchronized(gnssLock) {
            if (expected != null && gnssSocket !== expected) return
            val current = gnssSocket
            gnssSocket = null
            gnssDeviceName = null
            latestGga = null
            current
        }
        runCatching { socket?.close() }
    }
}
