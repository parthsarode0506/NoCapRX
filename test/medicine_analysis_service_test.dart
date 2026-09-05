import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/services/medicine_analysis_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('medicine analysis services initialize before use', () async {
    final service = MedicineAnalysisService.instance;

    await service.ensureReady();

    expect(service.isReady, isTrue);
  });
}
