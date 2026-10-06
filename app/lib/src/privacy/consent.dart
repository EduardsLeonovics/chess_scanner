import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

/// What the user agreed to in Google's consent message (the UMP SDK, set up
/// under AdMob → Privacy & messaging), shown at launch where the law
/// requires it (EEA, UK, Switzerland, some US states).
@immutable
class PrivacyState {
  const PrivacyState({this.canShowAds = false, this.statsConsent = false, this.privacyOptionsRequired = false});

  /// Ads may be requested: consent was given or isn't needed. Google still
  /// decides between personalised and limited ads from the choices made.
  final bool canShowAds;

  /// The anonymous usage statistics may be collected: the user allowed the
  /// app's own measurement purposes in the message (TCF purposes 1 and 8
  /// or 9), or no consent message applies where they are.
  final bool statsConsent;

  /// Settings must offer a way back into the consent message.
  final bool privacyOptionsRequired;
}

final privacyProvider = NotifierProvider<PrivacyNotifier, PrivacyState>(PrivacyNotifier.new);

class PrivacyNotifier extends Notifier<PrivacyState> {
  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  PrivacyState build() => const PrivacyState();

  /// Asks for consent if needed, then starts the ads SDK if allowed. Call
  /// once at launch; never throws.
  Future<void> start() async {
    if (!_supported) return;
    try {
      final updated = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => updated.complete(),
        (error) => updated.completeError(error.message),
      );
      await updated.future;
      final shown = Completer<void>();
      ConsentForm.loadAndShowConsentFormIfRequired((error) => shown.complete());
      await shown.future;
    } catch (e) {
      // Offline or misconfigured: fall back to whatever was decided before.
      debugPrint('Consent update failed: $e');
    }
    await _refresh();
    if (state.canShowAds) {
      try {
        await MobileAds.instance.initialize();
      } catch (e) {
        debugPrint('Ads unavailable: $e');
        state = PrivacyState(
          statsConsent: state.statsConsent,
          privacyOptionsRequired: state.privacyOptionsRequired,
        );
      }
    }
  }

  /// Opens the consent message again (Settings → Privacy choices).
  Future<void> showPrivacyOptions() async {
    if (!_supported) return;
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) => done.complete());
    await done.future;
    final hadAds = state.canShowAds;
    await _refresh();
    if (!hadAds && state.canShowAds) await MobileAds.instance.initialize();
  }

  Future<void> _refresh() async {
    try {
      final canShowAds = await ConsentInformation.instance.canRequestAds();
      final options = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      state = PrivacyState(
        canShowAds: canShowAds,
        statsConsent: await _statsConsent(),
        privacyOptionsRequired: options == PrivacyOptionsRequirementStatus.required,
      );
    } catch (e) {
      debugPrint('Consent status unavailable: $e');
    }
  }
}

/// The consent message stores its result as IAB TCF strings in the
/// platform's default preferences (Android: the default SharedPreferences
/// file, which the plain shared_preferences API can't see).
SharedPreferencesAsync _tcfStore() => SharedPreferencesAsync(
      options: Platform.isAndroid
          ? const SharedPreferencesAsyncAndroidOptions(
              backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
              originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(),
            )
          : const SharedPreferencesOptions(),
    );

Future<bool> _statsConsent() async {
  final store = _tcfStore();
  int? gdprApplies;
  String? publisherConsent;
  try {
    gdprApplies = await store.getInt('IABTCF_gdprApplies');
    publisherConsent = await store.getString('IABTCF_PublisherConsent');
  } catch (e) {
    debugPrint('Consent choices unreadable: $e');
  }
  return statsAllowed(gdprApplies: gdprApplies, publisherConsent: publisherConsent);
}

/// Whether anonymous usage statistics may be collected, from the TCF
/// values: outside the GDPR (no consent message) yes; inside it only if the
/// user allowed the app's own use of purpose 1 (storing on the device) and
/// purpose 8 (measuring content performance) or 9 (audience statistics).
@visibleForTesting
bool statsAllowed({required int? gdprApplies, required String? publisherConsent}) {
  if (gdprApplies != 1) return true;
  final consent = publisherConsent ?? '';
  bool has(int purpose) => consent.length >= purpose && consent[purpose - 1] == '1';
  return has(1) && (has(8) || has(9));
}
