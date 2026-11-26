package cn.survey.survey_pro

import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.View
import kotlin.math.roundToInt
import androidx.annotation.ColorInt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// 通过平台通道把系统（壁纸）强调色交给 Dart 侧做莫奈取色。
///
/// Android 12（API 31）起系统会从壁纸生成 tonal 色板，这里读
/// `android.R.color.system_accent1_*` 作为种子；低版本返回 null，
/// Dart 侧自动回落到手选种子色。
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val content = findViewById<View>(android.R.id.content)
        content.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            val density = view.resources.displayMetrics.density
            if (view.width / density >= 840 || view.height == 0) {
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "survey/theme")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "accentColor" -> result.success(systemAccentColor())
                    else -> result.notImplemented()
                }
            }
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
