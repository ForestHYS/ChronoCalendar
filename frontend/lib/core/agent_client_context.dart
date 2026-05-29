/// Agent API 请求的客户端上下文（时区等）。
Map<String, dynamic> buildAgentClientContext() {
  final now = DateTime.now();
  return {
    'timezone_offset_minutes': now.timeZoneOffset.inMinutes,
    'timezone_name': now.timeZoneName,
  };
}
