import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/ads_service.dart';

void main() {
  test('Ad-free build does not require Firebase, consent or an ad ID', () async {
    expect(AdsService.supported, isFalse);
    expect(AdsService.instance.bannerId, isNull);
    await AdsService.instance.start();
    await AdsService.instance.start(afterDeclaration: true);
    await AdsService.instance.showPrivacyOptions();
    expect(AdsService.instance.ready.value, isFalse);
    expect(AdsService.instance.privacyOptionsRequired.value, isFalse);
  });

  testWidgets('Existing banner placement takes no space in the ad-free build',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: HomeBannerAd())),
    ));
    expect(tester.getSize(find.byType(HomeBannerAd)), Size.zero);
    expect(find.text('Advertisement'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
