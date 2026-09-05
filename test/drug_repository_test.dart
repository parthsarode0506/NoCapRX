import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/services/drug_repository.dart';

void main() {
  test('resolves a brand name only through the local catalogue', () {
    expect(DrugRepository.resolve('plavix')?.genericName, 'CLOPIDOGREL');
  });

  test('does not guess an unsupported medicine', () {
    expect(DrugRepository.resolve('made up medicine'), isNull);
  });
}
