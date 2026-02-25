---
trigger: always_on
---

When completing a task:

1. Run `flutter analyze` and fix all errors
2. Run `dart format .` and fix all errors
3. Check for the presence of growing Dart file size and monolithinc components. Refactor them into smaller more organized components and files.