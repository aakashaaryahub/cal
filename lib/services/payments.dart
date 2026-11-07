import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../models/user_profile.dart';
import 'api.dart';
import 'storage.dart';

/// Thrown when Play accepted the payment but hasn't confirmed it yet (slow
/// UPI, cash). Premium turns on by itself once it clears.
class PaymentPending implements Exception {
  final String message = 'Your payment is processing. Premium turns on as soon as it completes.';
}

/// Buys premium plans through Google Play Billing. Each plan is a consumable
/// Play product with the same ID. The server verifies every purchase with
/// Google, grants the days and consumes it; premium is only granted server-side.
class Payments {
  static final _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;

  /// The purchase the paywall is waiting on.
  static String? _buyingProductId;
  static Completer<UserProfile?>? _buying;

  /// Listens for purchases for the app's lifetime: pending payments can clear
  /// long after the paywall closes. Call once at startup.
  static void init() {
    if (!Platform.isAndroid) return;
    _sub ??= _iap.purchaseStream.listen(
      (purchases) {
        for (final p in purchases) {
          _handle(p);
        }
      },
      onError: (Object e) => debugPrint('Purchase stream error: $e'),
    );
  }

  /// Resends purchases Play still holds unconsumed (app closed mid-payment, a
  /// pending payment that cleared, a failed server call). Call once signed in.
  static Future<void> resendUnfinished() async {
    if (!Platform.isAndroid || !Storage.hasToken) return;
    try {
      if (await _iap.isAvailable()) await _iap.restorePurchases();
    } catch (e) {
      debugPrint('Restoring purchases failed: $e');
    }
  }

  /// Play's own prices (localized, in the buyer's currency), keyed by plan ID.
  /// Empty when Play isn't available, e.g. on an emulator without Play Store.
  static Future<Map<String, ProductDetails>> playProducts(List<Plan> plans) async {
    if (!Platform.isAndroid || plans.isEmpty) return {};
    try {
      if (!await _iap.isAvailable()) return {};
      final res = await _iap.queryProductDetails(plans.map((p) => p.id).toSet());
      return {for (final d in res.productDetails) d.id: d};
    } catch (e) {
      debugPrint('Loading Play products failed: $e');
      return {};
    }
  }

  /// Returns the updated user, or null if the user cancelled.
  ///
  /// [confirmTestPurchase] is shown when the backend has no Google Play
  /// credentials and runs in dev mode, so the flow can be tried without real money.
  static Future<UserProfile?> purchase(
    Plan plan, {
    required Future<bool> Function() confirmTestPurchase,
  }) async {
    final order = await Api.createOrder(plan.id);

    if (order['mode'] == 'dev') {
      if (!await confirmTestPurchase()) return null;
      return _finish(await Api.verifyPayment(orderId: order['orderId'].toString()));
    }

    final productId = (order['productId'] ?? plan.id).toString();
    final product = (await playProducts([plan]))[productId];
    if (product == null) {
      throw ApiException('Google Play isn\'t available right now. Make sure the Play Store app is signed in.');
    }

    final completer = _buying = Completer<UserProfile?>();
    _buyingProductId = productId;
    try {
      final started = await _iap.buyConsumable(
        // Tags the purchase with the account, so the server can check it isn't
        // claimed by someone else.
        purchaseParam: PurchaseParam(productDetails: product, applicationUserName: '${Storage.user?.id ?? ''}'),
        // The server consumes after granting premium; consuming here first
        // could lose a purchase if the server call failed.
        autoConsume: false,
      );
      if (!started) return null;
      return await completer.future;
    } on PlatformException catch (e) {
      throw ApiException(e.message ?? 'Payment failed. You have not been charged.');
    } finally {
      _buying = null;
      _buyingProductId = null;
    }
  }

  static Future<void> _handle(PurchaseDetails p) async {
    final waiting = p.productID == _buyingProductId ? _buying : null;
    void complete(UserProfile? user) {
      if (waiting != null && !waiting.isCompleted) waiting.complete(user);
    }

    void fail(Object error) {
      if (waiting != null && !waiting.isCompleted) waiting.completeError(error);
    }

    switch (p.status) {
      case PurchaseStatus.canceled:
        complete(null);
      case PurchaseStatus.error:
        fail(ApiException(p.error?.message ?? 'Payment failed. You have not been charged.'));
        // Play refuses a plan while an earlier purchase of it is unconsumed.
        unawaited(resendUnfinished());
      case PurchaseStatus.pending:
        fail(PaymentPending());
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        try {
          final user = await Api.verifyPlayPurchase(
            productId: p.productID,
            purchaseToken: p.verificationData.serverVerificationData,
          );
          if (user == null) return fail(PaymentPending());
          await _finish(user);
          // The server already consumed it; this refreshes Play's local cache
          // so the plan can be bought again straight away.
          await _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().consumePurchase(p);
          complete(user);
        } on ApiException catch (e) {
          // Left unconsumed, so it is retried on the next launch.
          debugPrint('Verifying purchase failed: ${e.message}');
          fail(ApiException(
            'Payment received but not confirmed yet. It will be retried automatically; '
            'if Premium doesn\'t turn on, Google refunds you within 3 days.',
          ));
        }
    }
  }

  static Future<UserProfile> _finish(UserProfile user) async {
    await Storage.saveUser(user);
    return user;
  }
}
