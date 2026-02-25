---
trigger: always_on
---

* PlatformInfo provides an abstraction layer over the Platform object. This is required for Chrome compatibility. Always use it.
* Do not attempt to run the application for testing, even in Chromium. The app is too complex to test. 