import 'package:ag_ui_view_state/ag_ui_view_state.dart';

final class RunAdmission {
  const RunAdmission({required this.sessionId, required this.runId});

  final String sessionId;
  final String runId;
}

abstract interface class EinoSessionContract {
  RequestSpec watchRequest(String sessionId);

  RequestSpec admissionRequest(String sessionId, String newText);

  RunAdmission decodeAdmission(List<int> body);

  RequestSpec interruptRequest(String sessionId, String runId);
}
