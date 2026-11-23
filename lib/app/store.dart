import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'ads.dart';
import 'app_state.dart';

/// Google Play purchases. One product: "Remove Ads" (one-time, non-
/// consumable), which turns off the ads between levels for good.
///
/// Create it in Play Console > Monetize > Products > In-app products with
/// the product ID [removeAdsId].
class Store extends ChangeNotifier {
  Store._();
  static final instance = Store._();

  static const removeAdsId = 'remove_ads';

  bool available = false;
  bool busy = false;
  ProductDetails? removeAds;

  /// Last problem to tell the player about (cleared on the next action).
  String? message;

  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!_supported) return;
    try {
      final iap = InAppPurchase.instance;
      _sub ??= iap.purchaseStream.listen(_onPurchases,
          onError: (Object e) => debugPrint('Purchase stream error: $e'));
      available = await iap.isAvailable();
      if (!available) {
        notifyListeners();
        return;
      }
      final res = await iap.queryProductDetails({removeAdsId});
      removeAds =
          res.productDetails.where((p) => p.id == removeAdsId).firstOrNull;
      notifyListeners();
      // Brings back a purchase made earlier (new phone, reinstall).
      await iap.restorePurchases();
    } catch (e) {
      debugPrint('Store unavailable: $e');
    }
  }

  /// Starts the Remove Ads purchase. The result arrives via the purchase
  /// stream.
  Future<void> buyRemoveAds() async {
    message = null;
    final product = removeAds;
    if (!available || product == null) {
      message = 'The store is not available right now. Please try again '
          'later.';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await InAppPurchase.instance.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      busy = false;
      message = 'The purchase could not be started.';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    message = null;
    if (!available) {
      message = 'The store is not available right now.';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    await InAppPurchase.instance.restorePurchases();
    // Restored purchases (if any) come through the stream; stop the spinner
    // after a moment either way.
    Timer(const Duration(seconds: 3), () {
      if (!busy) return;
      busy = false;
      if (!AppState.instance.adsRemoved) {
        message = 'No earlier purchase found for this Google account.';
      }
      notifyListeners();
    });
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != removeAdsId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          AppState.instance.setAdsRemoved();
          Ads.instance.removeAds();
          busy = false;
        case PurchaseStatus.error:
          busy = false;
          message = 'The purchase did not go through.';
        case PurchaseStatus.canceled:
          busy = false;
        case PurchaseStatus.pending:
          message = 'Your purchase is pending. Ads will be removed as soon '
              'as it is confirmed.';
      }
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
    notifyListeners();
  }
}
