import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const NetworkGuardApp());
}

class NetworkGuardApp extends StatelessWidget {
  const NetworkGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '网络守护',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D9488),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<NetworkStatus>? _networkSubscription;
  bool _isLoading = true;
  bool _hasWifiOrCellular = true;
  String _emailAddress = '';
  String _smsPhoneNumber = '';
  String _deviceName = '';
  List<String> _emailLogs = <String>[];
  EmailServerSettings _emailServerSettings = EmailServerSettings.empty();
  String _statusMessage = '等待初始化...';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final String savedEmail = await NativeBridge.getEmailAddress();
      final String savedSmsPhoneNumber = await NativeBridge.getSmsPhoneNumber();
      final String savedDeviceName = await NativeBridge.getDeviceName();
      final List<String> savedEmailLogs = await NativeBridge.getEmailLogs();
      final EmailServerSettings savedEmailServerSettings =
          await NativeBridge.getEmailServerSettings();
      final NetworkStatus currentStatus =
          await NativeBridge.getCurrentNetworkStatus();
      await NativeBridge.startGuardService();

      if (!mounted) {
        return;
      }

      setState(() {
        _emailAddress = savedEmail;
        _smsPhoneNumber = savedSmsPhoneNumber;
        _deviceName = savedDeviceName;
        _emailLogs = savedEmailLogs;
        _emailServerSettings = savedEmailServerSettings;
        _hasWifiOrCellular = currentStatus.hasWifiOrCellular;
        _statusMessage = _statusLabel(currentStatus.hasWifiOrCellular);
        _isLoading = false;
      });

      _networkSubscription = NativeBridge.networkEvents.listen(
        _handleNetworkStatus,
        onError: (Object error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _statusMessage = '监听网络状态失败：$error';
          });
        },
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _statusMessage = '初始化失败：${error.message ?? error.code}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _statusMessage = '初始化失败：$error';
      });
    }
  }

  Future<void> _handleNetworkStatus(NetworkStatus status) async {
    if (!mounted) {
      return;
    }

    final List<String> latestLogs = await NativeBridge.getEmailLogs();

    if (!mounted) {
      return;
    }

    setState(() {
      _hasWifiOrCellular = status.hasWifiOrCellular;
      _statusMessage = _statusLabel(status.hasWifiOrCellular);
      _emailLogs = latestLogs;
    });
  }

  Future<void> _clearEmailLogs() async {
    await NativeBridge.clearEmailLogs();
    if (!mounted) {
      return;
    }
    setState(() {
      _emailLogs = <String>[];
    });
  }

  Future<void> _openSettings() async {
    final SettingsValues? settings = await Navigator.of(context)
        .push<SettingsValues>(
          MaterialPageRoute<SettingsValues>(
            builder: (BuildContext context) => SettingsPage(
              initialEmail: _emailAddress,
              initialSmsPhoneNumber: _smsPhoneNumber,
              initialDeviceName: _deviceName,
              initialEmailServerSettings: _emailServerSettings,
            ),
          ),
        );

    if (settings == null || !mounted) {
      return;
    }

    setState(() {
      _emailAddress = settings.emailAddress;
      _smsPhoneNumber = settings.smsPhoneNumber;
      _deviceName = settings.deviceName;
      _emailServerSettings = settings.emailServerSettings;
    });
  }

  Future<void> _requestSmsPermission() async {
    await NativeBridge.startGuardService();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('如果系统弹出权限请求，请允许发送短信权限。')));
  }

  String _smsLabel() {
    if (_smsPhoneNumber.isEmpty) {
      return '尚未设置';
    }
    return _smsPhoneNumber;
  }

  String get _resolvedDeviceName {
    if (_deviceName.trim().isEmpty) {
      return '未命名设备';
    }
    return _deviceName.trim();
  }

  String _statusLabel(bool hasWifiOrCellular) {
    return hasWifiOrCellular ? '当前网络可用' : '当前 WiFi 或移动数据不可用';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('网络守护')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _StatusCard(
            hasWifiOrCellular: _hasWifiOrCellular,
            statusMessage: _statusMessage,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('后台守护', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('已启动前台服务。即使 App 被划走，也会继续监听网络状态。'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: NativeBridge.startGuardService,
                    child: const Text('重新启动守护'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _EmailLogCard(logs: _emailLogs, onClear: _clearEmailLogs),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('通知设置', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '本机名称：$_resolvedDeviceName',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '邮箱：${_emailAddress.isEmpty ? '尚未设置' : _emailAddress}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '短信号码：${_smsLabel()}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '邮件服务器：${_emailServerSettings.smtpHost.isEmpty ? '尚未设置' : _emailServerSettings.smtpHost}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonal(
                        onPressed: _openSettings,
                        child: const Text('打开设置'),
                      ),
                      OutlinedButton(
                        onPressed: _requestSmsPermission,
                        child: const Text('申请短信权限'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('说明', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    '1. 后台前台服务会持续监听网络状态。\n'
                    '2. 当 WiFi 或移动数据任意一个不可用时，会发出系统级通知提醒。\n'
                    '3. 设置短信号码并授权后，触发提醒时会自动发送短信。\n'
                    '4. 邮件会在任一种网络不可用时立刻尝试发送，失败后会在网络恢复时重试。',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.hasWifiOrCellular,
    required this.statusMessage,
  });

  final bool hasWifiOrCellular;
  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = hasWifiOrCellular
        ? const Color(0xFF047857)
        : const Color(0xFFB91C1C);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: hasWifiOrCellular
              ? <Color>[const Color(0xFFD1FAE5), const Color(0xFFF0FDF4)]
              : <Color>[const Color(0xFFFEE2E2), const Color(0xFFFFF1F2)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            hasWifiOrCellular ? Icons.wifi : Icons.portable_wifi_off,
            size: 36,
            color: accentColor,
          ),
          const SizedBox(height: 12),
          Text(
            hasWifiOrCellular ? '网络正常' : '已触发提醒条件',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(statusMessage, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _EmailLogCard extends StatelessWidget {
  const _EmailLogCard({required this.logs, required this.onClear});

  final List<String> logs;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '邮件发送日志',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: logs.isEmpty ? null : onClear,
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              const Text('暂无邮件发送记录。')
            else
              ...logs
                  .take(8)
                  .map(
                    (String log) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        log,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initialEmail,
    required this.initialSmsPhoneNumber,
    required this.initialDeviceName,
    required this.initialEmailServerSettings,
  });

  final String initialEmail;
  final String initialSmsPhoneNumber;
  final String initialDeviceName;
  final EmailServerSettings initialEmailServerSettings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _smsController;
  late final TextEditingController _smtpHostController;
  late final TextEditingController _smtpPortController;
  late final TextEditingController _smtpUsernameController;
  late final TextEditingController _smtpPasswordController;
  late final TextEditingController _senderEmailController;
  late String _smtpSecurity;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _deviceNameController = TextEditingController(
      text: widget.initialDeviceName,
    );
    _emailController = TextEditingController(text: widget.initialEmail);
    _smsController = TextEditingController(text: widget.initialSmsPhoneNumber);
    _smtpHostController = TextEditingController(
      text: widget.initialEmailServerSettings.smtpHost,
    );
    _smtpPortController = TextEditingController(
      text: widget.initialEmailServerSettings.smtpPort.toString(),
    );
    _smtpUsernameController = TextEditingController(
      text: widget.initialEmailServerSettings.smtpUsername,
    );
    _smtpPasswordController = TextEditingController(
      text: widget.initialEmailServerSettings.smtpPassword,
    );
    _senderEmailController = TextEditingController(
      text: widget.initialEmailServerSettings.senderEmail,
    );
    _smtpSecurity = widget.initialEmailServerSettings.security;
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _emailController.dispose();
    _smsController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUsernameController.dispose();
    _smtpPasswordController.dispose();
    _senderEmailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final String email = _emailController.text.trim();
    final String smsPhoneNumber = _smsController.text.trim();
    final String deviceName = _deviceNameController.text.trim();
    final EmailServerSettings emailServerSettings = EmailServerSettings(
      smtpHost: _smtpHostController.text.trim(),
      smtpPort: int.tryParse(_smtpPortController.text.trim()) ?? 465,
      smtpUsername: _smtpUsernameController.text.trim(),
      smtpPassword: _smtpPasswordController.text,
      senderEmail: _senderEmailController.text.trim(),
      security: _smtpSecurity,
    );

    try {
      await NativeBridge.saveEmailAddress(email);
      await NativeBridge.saveSmsPhoneNumber(smsPhoneNumber);
      await NativeBridge.saveDeviceName(deviceName);
      await NativeBridge.saveEmailServerSettings(emailServerSettings);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        SettingsValues(
          emailAddress: email,
          smsPhoneNumber: smsPhoneNumber,
          deviceName: deviceName,
          emailServerSettings: emailServerSettings,
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：${error.message ?? error.code}')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              Text('本机名称', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '例如 客厅手机、爸爸手机、1号设备',
                ),
                validator: (String? value) {
                  final String text = value?.trim() ?? '';
                  if (text.length > 40) {
                    return '本机名称不要超过 40 个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                '接收提醒的电子邮件地址',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'name@example.com',
                ),
                validator: (String? value) {
                  final String text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  const String pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
                  if (!RegExp(pattern).hasMatch(text)) {
                    return '请输入有效的电子邮件地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('任一种网络不可用时会立刻尝试发送邮件；如果不需要邮件，可以留空收件邮箱。'),
              const SizedBox(height: 24),
              Text(
                'SMTP 邮件服务器',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _smtpHostController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SMTP 服务器',
                  hintText: 'smtp.example.com',
                ),
                validator: (String? value) {
                  if (_emailController.text.trim().isEmpty) {
                    return null;
                  }
                  if ((value ?? '').trim().isEmpty) {
                    return '请输入 SMTP 服务器地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _smtpPortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '端口',
                  hintText: '465',
                ),
                validator: (String? value) {
                  if (_emailController.text.trim().isEmpty) {
                    return null;
                  }
                  final int? port = int.tryParse((value ?? '').trim());
                  if (port == null || port <= 0 || port > 65535) {
                    return '请输入有效端口';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _smtpSecurity,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '连接安全',
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'ssl',
                    child: Text('SSL/TLS，常用 465'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'none',
                    child: Text('不加密，常用 25/587'),
                  ),
                ],
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _smtpSecurity = value;
                    if (_smtpPortController.text.trim().isEmpty ||
                        _smtpPortController.text.trim() == '465' ||
                        _smtpPortController.text.trim() == '25') {
                      _smtpPortController.text = value == 'ssl' ? '465' : '25';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _smtpUsernameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '邮箱账号',
                  hintText: '通常是完整邮箱地址',
                ),
                validator: (String? value) {
                  if (_emailController.text.trim().isEmpty) {
                    return null;
                  }
                  if ((value ?? '').trim().isEmpty) {
                    return '请输入邮箱账号';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _smtpPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '邮箱密码或授权码',
                ),
                validator: (String? value) {
                  if (_emailController.text.trim().isEmpty) {
                    return null;
                  }
                  if ((value ?? '').isEmpty) {
                    return '请输入邮箱密码或授权码';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _senderEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '发件人邮箱',
                  hintText: 'name@example.com',
                ),
                validator: (String? value) {
                  if (_emailController.text.trim().isEmpty) {
                    return null;
                  }
                  final String text = value?.trim() ?? '';
                  const String pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
                  if (!RegExp(pattern).hasMatch(text)) {
                    return '请输入有效的发件人邮箱';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text('多数邮箱服务商需要使用“授权码”而不是登录密码。'),
              const SizedBox(height: 24),
              Text('接收提醒的短信号码', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _smsController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '例如 13800138000',
                ),
                validator: (String? value) {
                  final String text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  const String pattern = r'^\+?[0-9][0-9\s-]{5,20}$';
                  if (!RegExp(pattern).hasMatch(text)) {
                    return '请输入有效的手机号码';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text('短信会在网络提醒触发时由系统短信服务发送，需允许发送短信权限。'),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(_isSaving ? '保存中...' : '保存设置'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NetworkStatus {
  const NetworkStatus({
    required this.hasWifiOrCellular,
    required this.eventType,
  });

  factory NetworkStatus.fromMap(Map<Object?, Object?> map) {
    return NetworkStatus(
      hasWifiOrCellular: map['hasWifiOrCellular'] as bool? ?? false,
      eventType: map['eventType'] as String? ?? 'unknown',
    );
  }

  final bool hasWifiOrCellular;
  final String eventType;
}

class SettingsValues {
  const SettingsValues({
    required this.emailAddress,
    required this.smsPhoneNumber,
    required this.deviceName,
    required this.emailServerSettings,
  });

  final String emailAddress;
  final String smsPhoneNumber;
  final String deviceName;
  final EmailServerSettings emailServerSettings;
}

class EmailServerSettings {
  const EmailServerSettings({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.smtpPassword,
    required this.senderEmail,
    required this.security,
  });

  factory EmailServerSettings.empty() {
    return const EmailServerSettings(
      smtpHost: '',
      smtpPort: 465,
      smtpUsername: '',
      smtpPassword: '',
      senderEmail: '',
      security: 'ssl',
    );
  }

  factory EmailServerSettings.fromMap(Map<Object?, Object?> map) {
    return EmailServerSettings(
      smtpHost: map['smtpHost'] as String? ?? '',
      smtpPort: map['smtpPort'] as int? ?? 465,
      smtpUsername: map['smtpUsername'] as String? ?? '',
      smtpPassword: map['smtpPassword'] as String? ?? '',
      senderEmail: map['senderEmail'] as String? ?? '',
      security: map['security'] as String? ?? 'ssl',
    );
  }

  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final String smtpPassword;
  final String senderEmail;
  final String security;

  bool get isConfigured {
    return smtpHost.isNotEmpty &&
        smtpPort > 0 &&
        smtpUsername.isNotEmpty &&
        smtpPassword.isNotEmpty &&
        senderEmail.isNotEmpty;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'smtpHost': smtpHost,
      'smtpPort': smtpPort,
      'smtpUsername': smtpUsername,
      'smtpPassword': smtpPassword,
      'senderEmail': senderEmail,
      'security': security,
    };
  }
}

class NativeBridge {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.example.android_elderly/settings',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.example.android_elderly/network_events',
  );

  static Future<String> getEmailAddress() async {
    final String? email = await _methodChannel.invokeMethod<String>(
      'getEmailAddress',
    );
    return email ?? '';
  }

  static Future<String> getSmsPhoneNumber() async {
    final String? phoneNumber = await _methodChannel.invokeMethod<String>(
      'getSmsPhoneNumber',
    );
    return phoneNumber ?? '';
  }

  static Future<String> getDeviceName() async {
    final String? deviceName = await _methodChannel.invokeMethod<String>(
      'getDeviceName',
    );
    return deviceName ?? '';
  }

  static Future<EmailServerSettings> getEmailServerSettings() async {
    final Map<Object?, Object?>? response = await _methodChannel
        .invokeMapMethod<Object?, Object?>('getEmailServerSettings');
    return EmailServerSettings.fromMap(response ?? <Object?, Object?>{});
  }

  static Future<List<String>> getEmailLogs() async {
    final List<Object?>? logs = await _methodChannel.invokeListMethod<Object?>(
      'getEmailLogs',
    );
    return (logs ?? <Object?>[]).whereType<String>().toList();
  }

  static Future<void> saveEmailAddress(String emailAddress) {
    return _methodChannel.invokeMethod<void>(
      'saveEmailAddress',
      <String, Object?>{'emailAddress': emailAddress},
    );
  }

  static Future<void> saveSmsPhoneNumber(String phoneNumber) {
    return _methodChannel.invokeMethod<void>(
      'saveSmsPhoneNumber',
      <String, Object?>{'phoneNumber': phoneNumber},
    );
  }

  static Future<void> saveDeviceName(String deviceName) {
    return _methodChannel.invokeMethod<void>(
      'saveDeviceName',
      <String, Object?>{'deviceName': deviceName},
    );
  }

  static Future<void> saveEmailServerSettings(EmailServerSettings settings) {
    return _methodChannel.invokeMethod<void>(
      'saveEmailServerSettings',
      settings.toMap(),
    );
  }

  static Future<void> clearEmailLogs() {
    return _methodChannel.invokeMethod<void>('clearEmailLogs');
  }

  static Future<NetworkStatus> getCurrentNetworkStatus() async {
    final Map<Object?, Object?>? response = await _methodChannel
        .invokeMapMethod<Object?, Object?>('getCurrentNetworkState');
    return NetworkStatus.fromMap(response ?? <Object?, Object?>{});
  }

  static Future<void> startGuardService() {
    return _methodChannel.invokeMethod<void>('startGuardService');
  }

  static Stream<NetworkStatus> get networkEvents {
    return _eventChannel.receiveBroadcastStream().map(
      (Object? event) => NetworkStatus.fromMap(
        event as Map<Object?, Object?>? ?? <Object?, Object?>{},
      ),
    );
  }
}
