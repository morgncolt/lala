#! /bin/bash
flutter clean
flutter pub get
flutter build web
flutter run -d ios
