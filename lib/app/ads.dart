import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob configuration.
///
/// Real ad unit IDs are never stored in the code. Release builds read them
/// from `secrets.json` (not in version control, see `secrets.example.json`):
///   flutter build appbundle --dart-define-from-file=secrets.json
/// Without it - and always in debug - Google's public test ads are shown,
/// which are safe to tap.
class AdConfig {
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  /// Real rewarded ad unit ("Rewarded - hints and hearts").
  static const _releaseRewarded = String.fromEnvironment('ADMOB_REWARDED');

  static String get rewardedUnitId =>
      kReleaseMode && _releaseRewarded.isNotEmpty
          ? _releaseRewarded
          : _testRewarded;

  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';

  /// Real interstitial ad unit ("Interstitial - between levels").
  static const _releaseInterstitial =
      String.fromEnvironment('ADMOB_INTERSTITIAL');

  static String get interstitialUnitId =>
      kReleaseMode && _releaseInterstitial.isNotEmpty
          ? _releaseInterstitial
          : _testInterstitial;
}

/// When a full-screen ad may appear between levels: never in the first
/// levels, never right after a loss (only called after wins), at most every
/// [every] wins and with a pause of at least [gap] between two ads.
class InterstitialPolicy {
  static const firstLevel = 11;
  static const every = 5;
  static const gap = Duration(seconds: 120);

  static bool due({
    required int level,
    required int winsSinceAd,
    required DateTime? lastAd,
    required DateTime now,
  }) =>
      level >= firstLevel &&
      winsSinceAd >= every &&
      (lastAd == null || now.difference(lastAd) >= gap);
}

/// Loads and shows rewarded ads. Always keeps one ad preloaded so the
/// "Watch ad" buttons can respond instantly.
class Ads extends ChangeNotifier {
  Ads._();
  static final instance = Ads._();

  RewardedAd? _ad;
  bool _loading = false;

  InterstitialAd? _inter;
  bool _interLoading = false;
  int _interRetry = 0;
  int _winsSinceAd = 0;
  DateTime? _lastInter;

  /// Set when the player bought "Remove Ads": no more between-level ads
  /// (rewarded ads stay, they are always the player's choice).
  bool adsRemoved = false;
  bool _enabled = false;
  bool _showing = false;
  int _retry = 0;

  /// True when the user must be able to reopen the consent form (EU/UK).
  bool privacyOptionsRequired = false;

  bool get ready => _ad != null && !_showing;

  /// Ads are set up and allowed (consent given, supported platform).
  bool get available => _enabled;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Gathers consent (GDPR/UMP) and then starts the SDK. Safe to call without
  /// awaiting; the game works fine while this runs or if it fails.
  Future<void> init() async {
    if (!_supported || AdConfig.rewardedUnitId.isEmpty) return;
    try {
      final gathered = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!gathered.isCompleted) gathered.complete();
        }),
        (_) {
          if (!gathered.isCompleted) gathered.complete();
        },
      );
      await gathered.future;
      privacyOptionsRequired = await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (!await ConsentInformation.instance.canRequestAds()) {
        notifyListeners();
        return;
      }
      await MobileAds.instance.initialize();
      _enabled = true;
      _load();
      _loadInterstitial();
    } catch (e) {
      debugPrint('Ads unavailable: $e');
    }
    notifyListeners();
  }

  /// Reopens the consent form from Settings.
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    await done.future;
    if (!_enabled && await ConsentInformation.instance.canRequestAds()) {
      await MobileAds.instance.initialize();
      _enabled = true;
      _load();
      _loadInterstitial();
    }
  }

  void _loadInterstitial() {
    if (!_enabled || adsRemoved || _interLoading || _inter != null) return;
    _interLoading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _inter = ad;
          _interLoading = false;
          _interRetry = 0;
        },
        onAdFailedToLoad: (error) {
          _interLoading = false;
          _interRetry++;
          debugPrint('Interstitial failed to load: $error');
          Future.delayed(Duration(seconds: min(300, 8 << min(_interRetry, 5))),
              _loadInterstitial);
        },
      ),
    );
  }

  /// Called after a won level, before moving on. Shows a full-screen ad when
  /// [InterstitialPolicy] allows it; completes when the ad is closed (or
  /// right away when none is shown).
  Future<void> afterLevelWin(int level) async {
    _winsSinceAd++;
    if (adsRemoved || _showing) return;
    final ad = _inter;
    final now = DateTime.now();
    if (ad == null ||
        !InterstitialPolicy.due(
            level: level,
            winsSinceAd: _winsSinceAd,
            lastAd: _lastInter,
            now: now)) {
      _loadInterstitial();
      return;
    }
    _inter = null;
    _showing = true;
    final done = Completer<void>();
    void finish(Ad a) {
      a.dispose();
      _showing = false;
      _winsSinceAd = 0;
      _lastInter = DateTime.now();
      if (!done.isCompleted) done.complete();
      _loadInterstitial();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (a, _) => finish(a),
    );
    await ad.show();
    return done.future;
  }

  /// Drops the between-level ads (after the Remove Ads purchase).
  void removeAds() {
    adsRemoved = true;
    _inter?.dispose();
    _inter = null;
    notifyListeners();
  }

  void _load() {
    if (!_enabled || _loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          _retry = 0;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _retry++;
          debugPrint('Rewarded ad failed to load: $error');
          Future.delayed(
              Duration(seconds: min(120, 4 << min(_retry, 5))), _load);
        },
      ),
    );
  }

  /// Shows the preloaded ad. Completes with true only if the user watched it
  /// long enough to earn the reward.
  Future<bool> showRewarded() async {
    final ad = _ad;
    if (ad == null || _showing) {
      _load();
      return false;
    }
    _ad = null;
    _showing = true;
    notifyListeners();
    var earned = false;
    final result = Completer<bool>();
    void finish(Ad a) {
      a.dispose();
      _showing = false;
      if (!result.isCompleted) result.complete(earned);
      notifyListeners();
      _load();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (a, _) => finish(a),
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return result.future;
  }
}
