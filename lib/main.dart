import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/chrome_required_screen.dart';
import 'utils/platform_info.dart';

import 'connector/meshcore_connector.dart';
import 'services/mal/mal_api.dart';
import 'services/mal/mal_provider.dart';
import 'screens/scanner_screen.dart';
import 'services/storage_service.dart';
import 'services/message_retry_service.dart';
import 'services/path_history_service.dart';
import 'services/app_settings_service.dart';
import 'services/notification_service.dart';
import 'services/ble_debug_log_service.dart';
import 'services/app_debug_log_service.dart';
import 'services/background_service.dart';
import 'services/map_tile_cache_service.dart';
import 'services/lua_service.dart';
import 'storage/prefs_manager.dart';
import 'utils/app_logger.dart';

void main() {
  // Wrap in a try-catch to log any startup errors
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Basic sync initialization
      await PrefsManager.initialize();

      final storage = StorageService();
      final connector = MeshCoreConnector();
      final appSettingsService = AppSettingsService();
      final appDebugLogService = AppDebugLogService();

      // Quick load settings
      await appSettingsService.loadSettings();

      runApp(
        MeshCoreApp(
          connector: connector,
          storage: storage,
          appSettingsService: appSettingsService,
          appDebugLogService: appDebugLogService,
        ),
      );
    },
    (error, stack) {
      if (kDebugMode) {
        print('[Main] Fatal Startup Error: $error');
        print(stack);
      }
      appLogger.error('Fatal Startup Error: $error', tag: 'Main');
    },
  );
}

class MeshCoreApp extends StatefulWidget {
  final MeshCoreConnector connector;
  final StorageService storage;
  final AppSettingsService appSettingsService;
  final AppDebugLogService appDebugLogService;

  const MeshCoreApp({
    super.key,
    required this.connector,
    required this.storage,
    required this.appSettingsService,
    required this.appDebugLogService,
  });

  @override
  State<MeshCoreApp> createState() => _MeshCoreAppState();
}

class _MeshCoreAppState extends State<MeshCoreApp> {
  late Future<void> _initFuture;
  late final MalApi _malApi;
  late final LuaService _luaService;
  late final MessageRetryService _retryService;
  late final PathHistoryService _pathHistoryService;
  late final BleDebugLogService _bleDebugLogService;
  late final MapTileCacheService _mapTileCacheService;
  late final BackgroundService _backgroundService;
  late final NotificationService _notificationService;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeServices();
  }

  Future<void> _initializeServices() async {
    final connector = widget.connector;
    final storage = widget.storage;
    final appSettingsService = widget.appSettingsService;
    final appDebugLogService = widget.appDebugLogService;

    // Initialize remaining services
    _pathHistoryService = PathHistoryService(storage);
    _retryService = MessageRetryService();
    _bleDebugLogService = BleDebugLogService();
    _backgroundService = BackgroundService();
    _mapTileCacheService = MapTileCacheService();
    _luaService = LuaService();
    _notificationService = NotificationService();

    // Initialize app logger
    appLogger.initialize(
      appDebugLogService,
      enabled: appSettingsService.settings.appDebugLogEnabled,
    );

    _registerThirdPartyLicenses();

    await _notificationService.initialize();
    await _backgroundService.initialize();

    _malApi = ConnectorMalApi(connector: connector);
    await _malApi.init();

    // Wire up connector with services
    connector.initialize(
      retryService: _retryService,
      pathHistoryService: _pathHistoryService,
      appSettingsService: appSettingsService,
      bleDebugLogService: _bleDebugLogService,
      appDebugLogService: appDebugLogService,
      backgroundService: _backgroundService,
      onConnected: () {
        _luaService.initialize(_malApi);
      },
    );

    await connector.loadContactCache();
    await connector.loadChannelSettings();
    await connector.loadCachedChannels();
    await connector.loadAllChannelMessages();
    await connector.loadUnreadState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF0D0D0D),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/mesh-icon.png',
                      width: 80,
                      height: 80,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.hub, color: Colors.blue, size: 80),
                    ),
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Error initializing: ${snapshot.error}'),
              ),
            ),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: widget.connector),
            ChangeNotifierProvider.value(value: _retryService),
            ChangeNotifierProvider.value(value: _pathHistoryService),
            ChangeNotifierProvider.value(value: widget.appSettingsService),
            ChangeNotifierProvider.value(value: _bleDebugLogService),
            ChangeNotifierProvider.value(value: widget.appDebugLogService),
            Provider.value(value: _malApi),
            Provider.value(value: widget.storage),
            Provider.value(value: _mapTileCacheService),
          ],
          child: Consumer<AppSettingsService>(
            builder: (context, settingsService, child) {
              return MaterialApp(
                title: 'MeshCore Open',
                debugShowCheckedModeBanner: false,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                locale: _localeFromSetting(
                  settingsService.settings.languageOverride,
                ),
                theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
                  useMaterial3: true,
                  fontFamily: 'NotoSans',
                  fontFamilyFallback: const [
                    'NotoSans',
                    'NotoSansSymbols',
                    'NotoSansSC',
                  ],
                  snackBarTheme: const SnackBarThemeData(
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
                darkTheme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: Brightness.dark,
                  ),
                  useMaterial3: true,
                  fontFamily: 'NotoSans',
                  fontFamilyFallback: const [
                    'NotoSans',
                    'NotoSansSymbols',
                    'NotoSansSC',
                  ],
                  snackBarTheme: const SnackBarThemeData(
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
                themeMode: _themeModeFromSetting(
                  settingsService.settings.themeMode,
                ),
                builder: (context, child) {
                  // Update notification service with resolved locale
                  final locale = Localizations.localeOf(context);
                  _notificationService.setLocale(locale);
                  return child ?? const SizedBox.shrink();
                },
                home: (PlatformInfo.isWeb && !PlatformInfo.isChrome)
                    ? const ChromeRequiredScreen()
                    : const ScannerScreen(),
              );
            },
          ),
        );
      },
    );
  }

  ThemeMode _themeModeFromSetting(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Locale? _localeFromSetting(String? languageCode) {
    if (languageCode == null) return null;
    return Locale(languageCode);
  }
}

void _registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      <String>['Open-Meteo Elevation API Data'],
      '''
Data used by LOS elevation lookups is provided by Open-Meteo.

Open-Meteo terms and attribution:
https://open-meteo.com/en/terms

Elevation API:
https://open-meteo.com/en/docs/elevation-api

Attribution license reference:
Creative Commons Attribution 4.0 International (CC BY 4.0)
https://creativecommons.org/licenses/by/4.0/
''',
    );
  });
}
