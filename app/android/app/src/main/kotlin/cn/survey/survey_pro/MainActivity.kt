package cn.survey.survey_pro

import android.content.ContentValues
import android.content.Intent
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.View
import android.view.WindowManager
import androidx.annotation.ColorInt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import kotlin.math.roundToInt

/// Platform bridges for Survey Pro:
/// - `survey/theme`: Android 12+ Material You wallpaper accent color (`accentColor`)
/// - `survey/files`: MediaStore gallery save (`savePngToGallery`) & system share (`shareImageUri`)
class MainActivity : FlutterActivity() {

    companion object {
        private const val kSurveyThemeChannel = "survey/theme"
        private const val kSurveyFilesChannel = "survey/files"
    }

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
                        val filename = call.argument<String>("filename")
                            ?.takeIf { it.isNotBlank() } ?: "survey_pro.png"
                        val album = call.argument<String>("album")
                            ?.takeIf { it.isNotBlank() } ?: "SurveyPro"
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("INVALID_ARGS", "PNG bytes must not be empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val saved = savePngToMediaStore(bytes, filename, album)
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

                    else -> result.notImplemented()
                }
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
}
