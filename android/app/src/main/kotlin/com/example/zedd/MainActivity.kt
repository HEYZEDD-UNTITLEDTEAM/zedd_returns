package com.example.zedd

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat // Import ActivityCompat for permission handling
import androidx.core.content.ContextCompat // Import ContextCompat for permission checks
import android.Manifest // Import Manifest for permissions
import android.content.pm.PackageManager // Import PackageManager for checking permissions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "overlay_channel"
    private lateinit var overlayView: View
    private lateinit var windowManager: WindowManager
    private var isOverlayShowing = false

    // Define constant for request code at the top level of the class.
    companion object {
        private const val REQUEST_CODE_CONTACTS = 101 // Moved to companion object for accessibility.
        private const val REQUEST_CODE_OVERLAY = 100 // For overlay permission requests.
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestContactsPermission() // Request contacts permission on create

        if (!Settings.canDrawOverlays(this)) {
            requestOverlayPermission()
        } else {
            setupMethodChannel()
            showOverlay()
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMethodChannel()
    }

    private fun requestContactsPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CONTACTS), REQUEST_CODE_CONTACTS)
        } else {
            loadContacts() // Load contacts if permission is already granted.
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_CONTACTS) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                loadContacts() // Load contacts if permission granted.
            } else {
                // Handle permission denial (optional)
            }
        }
    }

    private fun loadContacts() {
        val contactsList = mutableListOf<Pair<String, String>>() // Pair of name and phone number
        val cursor = contentResolver.query(android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI, null, null, null, null)

        cursor?.use {
            while (it.moveToNext()) {
                val name = it.getString(it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME))
                val phoneNumber = it.getString(it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER))
                contactsList.add(Pair(name, phoneNumber))
            }
        }

        // Store or process contactsList as needed (e.g., save to a variable or database).
    }

    private fun setupMethodChannel() {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateOverlayContent" -> {
                        val text = call.argument<String>("text") ?: ""
                        updateOverlayContent(text)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun showOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        overlayView = LayoutInflater.from(this).inflate(R.layout.overlay_layout, null)

        val displayMetrics = resources.displayMetrics
        val screenHeight = displayMetrics.heightPixels

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            screenHeight / 5,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        params.gravity = Gravity.BOTTOM
        params.x = 0
        params.y = 0

        overlayView.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, CHANNEL).invokeMethod("startListening", null)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, CHANNEL).invokeMethod("stopListening", null)
                    }
                    true
                }
                else -> false
            }
        }

        windowManager.addView(overlayView, params)
        isOverlayShowing = true
    }

    private fun updateOverlayContent(text: String) {
        if (::overlayView.isInitialized) {
            overlayView.findViewById<TextView>(R.id.overlayText)?.text = text
        }
    }

    private fun requestOverlayPermission() {
        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
        startActivityForResult(intent, REQUEST_CODE_OVERLAY)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_OVERLAY) {
            if (Settings.canDrawOverlays(this)) {
                setupMethodChannel()
                showOverlay()
            }
        }
    }
}