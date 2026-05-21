/// 仅解析十进制分钟数（拒绝 0x20 等十六进制写法）。
int? parseDecimalMinutes(String raw, {int min = 1, int max = 99999}) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('0x') || s.startsWith('0X')) return null;
  final n = int.tryParse(s);
  if (n == null) return null;
  if (n < min || n > max) return null;
  return n;
}
