package com.bacnet_ex.bacview

import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding

/**
 * Tauri hosts Phoenix in a full-screen WebView. Android 15+ draws edge-to-edge;
 * without inset handling LiveView sits under the status / navigation bars.
 *
 * Wry calls [onWebViewCreate] *before* [setContentView], so the WebView has no
 * parent yet. We wait until it is attached, wrap it in a [FrameLayout], and pad
 * that wrapper with system-bar / cutout / IME insets.
 *
 * Padding the WebView itself is unreliable: Chromium often lays out HTML into
 * the full view bounds and ignores Android padding.
 */
class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onWebViewCreate(webView: WebView) {
    super.onWebViewCreate(webView)
    webView.setBackgroundColor(Color.BLACK)

    val install = Runnable { ensureInsetWrapper(webView) }
    if (webView.isAttachedToWindow) {
      webView.post(install)
    } else {
      webView.addOnAttachStateChangeListener(
        object : View.OnAttachStateChangeListener {
          override fun onViewAttachedToWindow(v: View) {
            v.removeOnAttachStateChangeListener(this)
            // One more post so we run after Wry's setContentView finishes.
            v.post(install)
          }

          override fun onViewDetachedFromWindow(v: View) {}
        }
      )
    }
  }

  private fun ensureInsetWrapper(webView: WebView) {
    val parent = webView.parent as? ViewGroup ?: return

    val container: FrameLayout =
      if (parent.tag == INSET_WRAPPER_TAG && parent is FrameLayout) {
        parent
      } else {
        val index = parent.indexOfChild(webView)
        val oldLp = webView.layoutParams
        parent.removeView(webView)

        FrameLayout(this).apply {
          tag = INSET_WRAPPER_TAG
          setBackgroundColor(Color.BLACK)
          layoutParams =
            oldLp
              ?: ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
              )
          addView(
            webView,
            FrameLayout.LayoutParams(
              FrameLayout.LayoutParams.MATCH_PARENT,
              FrameLayout.LayoutParams.MATCH_PARENT
            )
          )
          parent.addView(this, index.coerceAtLeast(0), layoutParams)
        }
      }

    ViewCompat.setOnApplyWindowInsetsListener(container) { view, windowInsets ->
      val bars =
        windowInsets.getInsets(
          WindowInsetsCompat.Type.systemBars() or
            WindowInsetsCompat.Type.displayCutout() or
            WindowInsetsCompat.Type.ime()
        )
      view.updatePadding(
        left = bars.left,
        top = bars.top,
        right = bars.right,
        bottom = bars.bottom
      )
      WindowInsetsCompat.CONSUMED
    }
    ViewCompat.requestApplyInsets(container)
  }

  companion object {
    private const val INSET_WRAPPER_TAG = "bacview_inset_wrapper"
  }
}
