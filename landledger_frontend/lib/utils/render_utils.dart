import 'package:flutter/material.dart';

class RenderUtils {
  /// Get responsive padding based on screen size
  static EdgeInsets getResponsivePadding(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) {
      return const EdgeInsets.all(24);
    } else if (screenWidth > 600) {
      return const EdgeInsets.all(16);
    } else {
      return const EdgeInsets.all(12);
    }
  }

  /// Get responsive margin based on screen size
  static EdgeInsets getResponsiveMargin(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 8);
    } else if (screenWidth > 600) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    } else {
      return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    }
  }

  /// Get responsive font size
  static double getResponsiveFontSize(BuildContext context, double baseFontSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) {
      return baseFontSize * 1.2;
    } else if (screenWidth > 600) {
      return baseFontSize * 1.1;
    } else {
      return baseFontSize;
    }
  }

  /// Check if device is tablet or larger
  static bool isTabletOrLarger(BuildContext context) {
    return MediaQuery.of(context).size.width > 600;
  }

  /// Check if device is desktop
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > 1200;
  }

  /// Safe area wrapper that handles notches and system UI
  static Widget safeAreaWrapper(Widget child) {
    return SafeArea(
      child: child,
    );
  }

  /// Constrained box for preventing overflow
  static Widget constrainedWrapper(Widget child, {double? maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: child,
    );
  }
}

/// Extension for responsive design
extension ResponsiveExtension on BuildContext {
  bool get isTablet => MediaQuery.of(this).size.width > 600;
  bool get isDesktop => MediaQuery.of(this).size.width > 1200;
  bool get isMobile => MediaQuery.of(this).size.width <= 600;
  
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
}