const kTaskKindGeneral = 'general';
const kTaskKindOffice = 'office';
const kTaskKindCode = 'code';

const kTaskKinds = [kTaskKindGeneral, kTaskKindOffice, kTaskKindCode];

String normalizeTaskKind(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case kTaskKindOffice:
      return kTaskKindOffice;
    case kTaskKindCode:
      return kTaskKindCode;
    default:
      return kTaskKindGeneral;
  }
}

bool shouldDeepLinkCodeWorkbench(String? kind) =>
    normalizeTaskKind(kind) == kTaskKindCode;

bool officeResultHidesCodeTools(String? kind) =>
    normalizeTaskKind(kind) == kTaskKindOffice;

bool isCodeWorkbenchToolName(String? name) {
  if (name == null || name.isEmpty) return false;
  final n = name.toLowerCase();
  if (n.contains('git')) return true;
  switch (n) {
    case 'bash':
    case 'shell':
    case 'terminal':
    case 'npm':
    case 'cargo':
      return true;
    default:
      return false;
  }
}
