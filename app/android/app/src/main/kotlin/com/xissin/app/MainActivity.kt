package com.xissin.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE: blocks screenshots, screen recording, recent-apps preview
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onResume() {
        super.onResume()
        // Re-apply on resume — some Android versions lift it temporarily
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}