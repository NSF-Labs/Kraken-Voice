import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KrakenColors {
  KrakenColors._();
  static const Color bg = Color(0xFF0A0A0C);
  static const Color surface = Color(0xFF121216);
  static const Color surfaceElevated = Color(0xFF17171D);
  static const Color border = Color(0x0FFFFFFF);
  static const Color borderStrong = Color(0x1FFFFFFF);
  static const Color textPrimary = Color(0xFFF2EFE8);
  static const Color textSecondary = Color(0xFFA5A3A0);
  static const Color textMuted = Color(0xFF6B6966);
  static const Color accent = Color(0xFF8B7DFF);
  static const Color accentDim = Color(0x268B7DFF);
  static const Color accentBorder = Color(0x4D8B7DFF);
  static const Color onlineGreen = Color(0xFF6EE7B7);
  static const Color onlineGreenDim = Color(0x1F6EE7B7);
  static const Color danger = Color(0xFFF87171);
}

class KrakenSpacing {
  KrakenSpacing._();
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 14;
  static const double s5 = 16;
  static const double s6 = 20;
  static const double s7 = 24;
  static const double s8 = 28;
  static const double s9 = 32;
  static const double s10 = 36;
  static const double s11 = 40;
}

class KrakenRadius {
  KrakenRadius._();
  static const double sm = 5;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double r2xl = 14;
  static const double r3xl = 16;
}

class KrakenDuration {
  KrakenDuration._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
}

class KrakenText {
  KrakenText._();

  static TextStyle displayLg({Color? color}) => GoogleFonts.fraunces(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
    color: color ?? KrakenColors.textPrimary,
  );

  static TextStyle displayMd({Color? color}) => GoogleFonts.fraunces(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    color: color ?? KrakenColors.textPrimary,
  );

  static TextStyle bodyLg({Color? color}) => GoogleFonts.interTight(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: color ?? KrakenColors.textPrimary,
  );

  static TextStyle bodyMd({Color? color}) => GoogleFonts.interTight(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: color ?? KrakenColors.textPrimary,
  );

  static TextStyle bodySm({Color? color}) => GoogleFonts.interTight(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: color ?? KrakenColors.textPrimary,
  );

  static TextStyle caption({Color? color}) => GoogleFonts.interTight(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: color ?? KrakenColors.textPrimary,
  );

  static TextStyle label({Color? color}) => GoogleFonts.interTight(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: color ?? KrakenColors.textMuted,
  );

  static TextStyle meta({Color? color}) => GoogleFonts.interTight(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: color ?? KrakenColors.textMuted,
  );

  static TextStyle monoData({Color? color}) => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    color: color ?? KrakenColors.textMuted,
  );
}

