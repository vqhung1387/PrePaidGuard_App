final _tokenScale = BigInt.from(1000000);
final _amountPattern = RegExp(r'^\d{1,24}([.,]\d{1,6})?$');
final _ambiguousThousandPattern = RegExp(r'^[1-9]\d{0,2}[.,]\d{3}$');
final _multiThousandPattern = RegExp(r'^\d{1,3}([.,]\d{3}){2,}$');
final _tooManyDecimalsPattern = RegExp(r'^\d+[.,]\d{7,}$');
final _periodPattern = RegExp(r'^\d+$');

const tokenAmountHint =
    'Nhập 1000 cho một nghìn, 1,25 cho số lẻ (bỏ dấu hàng nghìn).';
const tokenAmountError =
    'Nhập giá dương, tối đa 6 chữ số thập phân, bỏ dấu hàng nghìn.';

BigInt? parseTokenAmount(String text) {
  final amount = text.trim();
  if (!_amountPattern.hasMatch(amount) ||
      _ambiguousThousandPattern.hasMatch(amount)) {
    return null;
  }

  final parts = amount.replaceAll(',', '.').split('.');
  final fraction = parts.length == 2 ? parts[1].padRight(6, '0') : '0';
  final atomicAmount =
      BigInt.parse(parts.first) * _tokenScale + BigInt.parse(fraction);
  return atomicAmount > BigInt.zero ? atomicAmount : null;
}

String? validateTokenAmountInput(String? raw) {
  final amount = (raw ?? '').trim();
  if (amount.isEmpty) return 'Nhập giá lớn hơn 0.';
  if (_ambiguousThousandPattern.hasMatch(amount) ||
      _multiThousandPattern.hasMatch(amount)) {
    return 'Không dùng dấu hàng nghìn: nhập 1000 cho một nghìn (nếu là số lẻ 3 chữ số, thêm 0 cuối như 1,0010).';
  }
  if (_tooManyDecimalsPattern.hasMatch(amount)) {
    return 'Tối đa 6 chữ số thập phân (mUSDC có 6 decimals).';
  }
  if (parseTokenAmount(amount) == null) return tokenAmountError;
  return null;
}

String formatTokenAmount(BigInt amount) {
  final whole = (amount ~/ _tokenScale).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = (amount % _tokenScale)
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole,$fraction';
}

int? parseWholeNumber(String text, {required int max}) {
  final value = text.trim();
  if (!_periodPattern.hasMatch(value)) return null;
  final number = int.tryParse(value);
  return number != null && number >= 1 && number <= max ? number : null;
}

enum ServiceCategory {
  gym('Gym'),
  yoga('Yoga'),
  course('Khóa học'),
  other('Dịch vụ khác');

  const ServiceCategory(this.label);
  final String label;
}

class DemoPlan {
  const DemoPlan({
    required this.title,
    required this.description,
    required this.pricePerPeriod,
    required this.periods,
    required this.daysPerPeriod,
    this.monthlyListPrice,
    this.bonusDaysAfterCheckIn = 0,
    this.category = ServiceCategory.gym,
    this.provider,
  });

  final String title;
  final String description;
  final BigInt pricePerPeriod;
  final int periods;
  final int daysPerPeriod;
  final BigInt? monthlyListPrice;
  final int bonusDaysAfterCheckIn;
  final ServiceCategory category;
  final String? provider;

  String get serviceLabel =>
      provider == null ? category.label : '${category.label} · $provider';

  BigInt get total => pricePerPeriod * BigInt.from(periods);
  int get accessDays => periods * daysPerPeriod;

  BigInt get regularTotal =>
      (monthlyListPrice ?? pricePerPeriod) * BigInt.from(periods);
  BigInt get savings => regularTotal - total;
  int get discountPercent => regularTotal == BigInt.zero
      ? 0
      : (savings * BigInt.from(100) ~/ regularTotal).toInt();
}
