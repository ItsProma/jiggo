import 'widgets/local_files_panel.dart';
import 'screens/file_editor_screen.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'services/auth_service.dart';
import 'services/notification_controller.dart';
import 'services/notification_driver.dart';
import 'services/notification_preferences.dart';
import 'services/notification_registry.dart';
import 'services/notification_background.dart';
import 'screens/notifications_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/scan_pdf_screen.dart';

import 'dart:async' as async_utils;

import 'package:flutter/foundation.dart' as foundation;

import 'services/ads_service.dart';
import 'widgets/home_tools.dart';
import 'widgets/home_overview.dart';
import 'services/app_settings.dart';
import 'services/app_strings.dart';
import 'services/app_theme.dart';
import 'screens/app_preferences_screen.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:firebase_app_check/firebase_app_check.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/create_screen.dart';
import 'screens/library_screen.dart';
import 'screens/profile_screen.dart';

import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAppCheck.instance.activate(
    providerAndroid: foundation.kDebugMode
        ? const AndroidDebugProvider(
            debugToken: String.fromEnvironment('APP_CHECK_DEBUG_TOKEN') == ''
                ? null
                : String.fromEnvironment('APP_CHECK_DEBUG_TOKEN'),
          )
        : const AndroidPlayIntegrityProvider(),
    providerWeb: ReCaptchaEnterpriseProvider(
      '6Le2EBYuAAAAAJlw09CqDcLqFA5MGSvA3WEn_dyj',
    ),
  );

  FirebaseMessaging.onBackgroundMessage(jiggoBackgroundNotification);

  runApp(const JiggoApp());
}

class JiggoApp extends StatefulWidget {
  final Stream<User?>? authStateChanges;
  final AppSettings? settings;
  final NotificationController? notifications;

  const JiggoApp({
    super.key,
    this.authStateChanges,
    this.settings,
    this.notifications,
  });

  @override
  State<JiggoApp> createState() => _JiggoAppState();
}

class _JiggoAppState extends State<JiggoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late Stream<User?> _authStream;
  String? _lastUid;
  bool _receivedAuth = false;
  late final AppSettings _settings;
  bool _loadingSettings = true;
  bool _settingsLoadFailed = false;
  late final NotificationController _notifications;
  late final Future<void> Function() _beforeSignOut;
  bool _notificationBound = false;
  String? _notificationAccount;
  String? _lastOpenedNotice;
  int _homeEvent = 0;

  void _syncNotificationAccount() {
    if (!_receivedAuth || !_notifications.ready) return;
    if (!_notificationBound || _notificationAccount != _lastUid) {
      _notificationBound = true;
      _notificationAccount = _lastUid;
      _notifications.bindAccount(_lastUid, _settings.locale.languageCode);
    }
  }

  void _settingsChanged() =>
      _notifications.updateLanguage(_settings.locale.languageCode);

  void _notificationChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncNotificationAccount();
      if (!_settings.hasLanguage ||
          !_notifications.prompted ||
          _lastUid == null) {
        return;
      }
      final navigator = _navigatorKey.currentState;
      final context = _navigatorKey.currentContext;
      if (navigator == null || context == null) return;
      final foreground = _notifications.foregroundNotice;
      if (foreground != null) {
        _notifications.consumeForeground();
        if (foreground.ownerUid == _lastUid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(foreground.title),
              action: SnackBarAction(
                label: context.tr('Open'),
                onPressed: () => _notifications.open(foreground),
              ),
            ),
          );
        }
      }
      final notice = _notifications.pendingOpen;
      if (notice == null) return;
      _notifications.consumeOpen();
      if (notice.ownerUid != _lastUid || notice.id == _lastOpenedNotice) return;
      _lastOpenedNotice = notice.id;
      navigator.popUntil((route) => route.isFirst);
      final page = switch (notice.target) {
        'scan' => const ScanScreen(),
        'create' => const CreateScreen(),
        'library' => const LibraryScreen(),
        'profile' => const ProfileScreen(),
        _ => null,
      };
      if (page == null) {
        setState(() => _homeEvent++);
      } else {
        navigator.push<void>(MaterialPageRoute<void>(builder: (_) => page));
      }
    });
  }

  Future<void> _loadSettings() async {
    try {
      await _settings.load();
    } catch (_) {
      _settingsLoadFailed = true;
    }
    if (mounted) setState(() => _loadingSettings = false);
  }

  @override
  void dispose() {
    _settings.removeListener(_settingsChanged);
    _notifications.removeListener(_notificationChanged);
    if (AuthService.beforeSignOut == _beforeSignOut) {
      AuthService.beforeSignOut = null;
    }
    if (widget.notifications == null) _notifications.dispose();
    if (widget.settings == null) _settings.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _settings = widget.settings ?? AppSettings(store: DeviceSettingsStore());
    _notifications =
        widget.notifications ??
        NotificationController(
          store: NotificationPreferencesStore(),
          driver: createNotificationDriver(),
          registry: FirebaseNotificationRegistry(),
          currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        );
    _beforeSignOut = _notifications.detachBeforeSignOut;
    AuthService.beforeSignOut = _beforeSignOut;
    _notifications.addListener(_notificationChanged);
    _settings.addListener(_settingsChanged);
    if (!_notifications.ready) {
      async_utils.unawaited(_notifications.initialize());
    }
    if (widget.settings != null) {
      _loadingSettings = false;
    } else {
      async_utils.unawaited(_loadSettings());
    }
    _authStream =
        widget.authStateChanges ?? FirebaseAuth.instance.authStateChanges();
  }

  @override
  void didUpdateWidget(covariant JiggoApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authStateChanges != widget.authStateChanges) {
      _authStream =
          widget.authStateChanges ?? FirebaseAuth.instance.authStateChanges();
    }
  }

  void _observeAccount(String? uid) {
    final changed = _receivedAuth && _lastUid != uid;
    _lastUid = uid;
    final firstAccount = !_receivedAuth;
    _receivedAuth = true;
    if (firstAccount || changed) _notificationChanged();
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lastUid == uid) {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationScope(
      controller: _notifications,
      child: AppSettingsScope(
        settings: _settings,
        child: AnimatedBuilder(
          animation: Listenable.merge([_settings, _notifications]),
          builder: (context, _) => MaterialApp(
            navigatorKey: _navigatorKey,

            localizationsDelegates: const [
              FlutterQuillLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('bn')],

            title: 'Jiggo',
            debugShowCheckedModeBanner: false,
            locale: _settings.locale,
            theme: jiggoTheme(Brightness.light),
            darkTheme: jiggoTheme(Brightness.dark),
            themeMode: _settings.themeMode,
            home: _loadingSettings
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                : _settingsLoadFailed
                ? Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr(
                                  'Could not load your preferences. Please try again.',
                                ),
                              ),
                              FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _settingsLoadFailed = false;
                                    _loadingSettings = true;
                                  });
                                  async_utils.unawaited(_loadSettings());
                                },
                                child: Text(context.tr('Retry')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : !_settings.hasLanguage
                ? const LanguageSelectionScreen()
                : _notifications.ready &&
                      !_notifications.prompted &&
                      _notifications.supported
                ? const NotificationPermissionScreen()
                : StreamBuilder<User?>(
                    stream: _authStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        _observeAccount(null);
                        return Scaffold(
                          body: Center(
                            child: Text(
                              context.tr('Unable to check login status.'),
                            ),
                          ),
                        );
                      }
                      _observeAccount(snapshot.data?.uid);
                      return snapshot.data == null
                          ? const LoginScreen()
                          : JiggoHomePage(
                              key: ValueKey(snapshot.data!.uid),
                              homeEvent: _homeEvent,
                            );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class JiggoHomePage extends StatefulWidget {
  final int homeEvent;
  const JiggoHomePage({super.key, this.homeEvent = 0});

  @override
  State<JiggoHomePage> createState() => _JiggoHomePageState();
}

class _JiggoHomePageState extends State<JiggoHomePage> {
  int selectedIndex = 0;

  @override
  void didUpdateWidget(covariant JiggoHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeEvent != widget.homeEvent) selectedIndex = 0;
  }

  final TextEditingController promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (AdsService.supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          async_utils.unawaited(AdsService.instance.start());
        }
      });
    }
  }

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  void showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('{feature} is coming soon', {
            'feature': context.tr(feature),
          }),
        ),
      ),
    );
  }

  void _openChat(String question) {
    promptController.clear();
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AiChatScreen(initialQuestion: question),
      ),
    );
  }

  void _openTool(HomeTool tool) {
    switch (tool) {
      case HomeTool.scanSolve:
        setState(() => selectedIndex = 1);
        break;
      case HomeTool.documentMaker:
        setState(() => selectedIndex = 2);
        break;
      case HomeTool.pdfScanner:
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ScanPdfScreen()),
        );
        break;
      case HomeTool.fileEditor:
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const FileEditorScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: selectedIndex == 0
          ? AppBar(
              backgroundColor: context.pageColor,
              title: Text(
                context.tr('Jiggo'),
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: context.accentColor,
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      selectedIndex = 4;
                    });
                  },
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              ],
            )
          : null,
      body: IndexedStack(
        index: selectedIndex,
        children: [
          HomeOverview(
            recentFiles: FirebaseAuth.instance.currentUser == null
                ? null
                : LocalFilesPanel(
                    key: ValueKey(
                      'recent-${FirebaseAuth.instance.currentUser!.uid}',
                    ),
                    userId: FirebaseAuth.instance.currentUser!.uid,
                    compact: true,
                    currentOwner: () => FirebaseAuth.instance.currentUser?.uid,
                  ),
            promptController: promptController,
            onToolSelected: _openTool,
            onSubmit: _openChat,
            onUnavailable: showComingSoon,
            onOpenLibrary: () => setState(() => selectedIndex = 3),
          ),
          const ScanScreen(),
          const CreateScreen(),
          const LibraryScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedIndex == 0)
            Visibility(
              visible: MediaQuery.viewInsetsOf(context).bottom == 0,
              maintainState: true,
              child: const HomeBannerAd(),
            ),
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                label: context.tr('Home'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.document_scanner_outlined),
                label: context.tr('Scan'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.add_box_outlined),
                label: context.tr('Create'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.folder_outlined),
                label: context.tr('Library'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                label: context.tr('Profile'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
