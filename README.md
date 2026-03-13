# Xissin — Multi-Tool Flutter App

Flutter app for Android & iOS. Dark **Midnight Pulse** theme.  
Backend: Railway · Redis: Upstash

## Features
- 💣 SMS Bomber — 14 PH services, 1–5 rounds
- 🔑 Key Manager — redeem & view key status
- 👤 Auto user registration on first launch
- 🛡️ Key-gated features

## Setup

### Prerequisites
- Flutter SDK ≥ 3.0
- Android Studio / VS Code

### Install
```bash
git clone https://github.com/Xissin/Xissin-App.git
cd Xissin-App
flutter pub get
flutter run
```

### Wireless Debug (Android)
1. Enable Developer Options on your phone
2. Enable Wireless Debugging
3. In Android Studio: `Pair device with QR code` or `Pair device with code`
4. Then: `flutter run`

## Backend
API lives at: `https://xissin-app-backend-production.up.railway.app`  
Backend repo: `https://github.com/Xissin/Xissin-bot`

## Build APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```
