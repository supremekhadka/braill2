import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../core/app_constants.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  const SettingsScreen({super.key, required this.settingsService});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtrl;
  bool _saving = false;
  String? _success;
  String? _error;
  late bool _autoCrop;
  late bool _autoCapture;
  late bool _developerMode;
  late double _confThreshold;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.settingsService.baseUrl);
    _autoCrop = widget.settingsService.autoCrop;
    _autoCapture = widget.settingsService.autoCaptureEnabled;
    _developerMode = widget.settingsService.developerModeEnabled;
    _confThreshold = widget.settingsService.confThreshold;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  /// Spoken + felt confirmation for every change, for screen-reader users.
  void _cue(String message, {bool warn = false}) {
    warn ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
    SemanticsService.announce(message, TextDirection.ltr);
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'URL cannot be empty.');
      _cue('URL cannot be empty.', warn: true);
      return;
    }
    if (!url.startsWith('http')) {
      setState(() => _error = 'URL must start with http:// or https://');
      _cue('URL must start with http:// or https://', warn: true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    await widget.settingsService.setBaseUrl(url);
    setState(() {
      _saving = false;
      _success = 'Saved!';
    });
    _cue('Server address saved.');
  }

  Future<void> _reset() async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    await widget.settingsService.resetBaseUrl();
    _urlCtrl.text = AppConstants.defaultBaseUrl;
    setState(() {
      _saving = false;
      _success = 'Reset to default.';
    });
    _cue('Server address reset to default.');
  }

  Future<void> _setAutoCrop(bool value) async {
    setState(() => _autoCrop = value);
    _cue('Auto-crop ${value ? 'on' : 'off'}.');
    await widget.settingsService.setAutoCrop(value);
  }

  Future<void> _setAutoCapture(bool value) async {
    setState(() => _autoCapture = value);
    _cue('Automatic capture ${value ? 'on' : 'off'}.');
    await widget.settingsService.setAutoCaptureEnabled(value);
  }

  Future<void> _setDeveloperMode(bool value) async {
    setState(() => _developerMode = value);
    _cue(value
        ? 'Developer options on. Server and detection settings are shown below.'
        : 'Developer options off.');
    await widget.settingsService.setDeveloperModeEnabled(value);
  }

  void _previewConfThreshold(double value) {
    setState(() => _confThreshold = value);
  }

  Future<void> _commitConfThreshold(double value) async {
    await widget.settingsService.setConfThreshold(value);
    _cue('Confidence threshold ${(value * 100).round()} percent.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Heading('Scanning'),
            const SizedBox(height: 4),
            Text(
              'Control how the document scanner processes each capture. '
              'Auto-crop is on by default; automatic capture is off, so you '
              'press the shutter (or a volume button) yourself.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            _ToggleRow(
              icon: Icons.crop_free_rounded,
              label: 'Auto-crop',
              subtitle: 'Automatically detect edges and crop to the page',
              value: _autoCrop,
              onChanged: _setAutoCrop,
            ),
            const SizedBox(height: 12),
            _ToggleRow(
              icon: Icons.camera_alt_outlined,
              label: 'Automatic capture',
              subtitle:
                  'Take the photo by itself when the page is held steady. '
                  'Needs Auto-crop.',
              value: _autoCapture,
              onChanged: _setAutoCapture,
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.xl),
            _ToggleRow(
              icon: Icons.developer_mode_outlined,
              label: 'Developer options',
              subtitle: 'Show advanced settings: backend server & detection tuning',
              value: _developerMode,
              onChanged: _setDeveloperMode,
            ),
            if (_developerMode) ...[
              const SizedBox(height: AppSpacing.lg),
              const _Heading('Server'),
              const SizedBox(height: 4),
              Text(
                'Set the base URL of your Braille backend. '
                'Restart the app after changing this.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              _HintRow(
                icon: Icons.phone_android_outlined,
                label: 'Android emulator',
                value: 'http://10.0.2.2:8000',
                onTap: () {
                  _urlCtrl.text = 'http://10.0.2.2:8000';
                  _cue('Android emulator address filled in.');
                },
              ),
              const SizedBox(height: 8),
              _HintRow(
                icon: Icons.laptop_mac_outlined,
                label: 'iOS simulator / macOS',
                value: 'http://localhost:8000',
                onTap: () {
                  _urlCtrl.text = 'http://localhost:8000';
                  _cue('Simulator address filled in.');
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: context.text.bodyLarge,
                decoration: InputDecoration(
                  labelText: 'Backend base URL',
                  labelStyle: context.text.bodyMedium,
                  hintText: AppConstants.defaultBaseUrl,
                  filled: true,
                  fillColor: context.bgSurface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.borderStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.accentStrong, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 14,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.accentWarm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (_success != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _success!,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.accentStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Save',
                      loading: _saving,
                      onTap: _save,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    label: 'Reset',
                    loading: false,
                    onTap: _saving ? null : _reset,
                    outlined: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _Heading('Detection'),
              const SizedBox(height: 4),
              Text(
                'Minimum confidence a detected braille cell needs to be kept. '
                'Lower catches more cells but risks false positives.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              _ConfidenceThresholdRow(
                value: _confThreshold,
                onChanged: _previewConfThreshold,
                onChangeEnd: _commitConfThreshold,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: context.text.titleLarge));
}

/// Whole row is the touch target (≥72dp) and one screen-reader stop:
/// "Auto-crop, <description>, switch, on".
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: '$label. $subtitle',
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: value ? context.accentStrong : context.borderStrong,
              width: value ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 26, color: context.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The state is also written out, so it never relies on the
              // switch colour alone.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: context.bgPage,
                    activeTrackColor: context.accentStrong,
                    inactiveThumbColor: context.borderStrong,
                    inactiveTrackColor: context.bgSurfaceHigh,
                    trackOutlineColor: WidgetStatePropertyAll(
                      value ? context.accentStrong : context.borderStrong,
                    ),
                  ),
                  Text(
                    value ? 'On' : 'Off',
                    style: context.text.labelLarge?.copyWith(
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfidenceThresholdRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  const _ConfidenceThresholdRow({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: context.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderStrong, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 26, color: context.textPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Confidence threshold',
                    style: context.text.titleMedium,
                  ),
                ),
                Text(
                  '$percent%',
                  style: context.text.titleMedium?.copyWith(
                    color: context.accentStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              activeTrackColor: context.accentStrong,
              thumbColor: context.accentStrong,
              inactiveTrackColor: context.borderStrong,
              overlayColor: context.accentStrong.withOpacity(0.12),
            ),
            child: Semantics(
              label: 'Confidence threshold',
              child: Slider(
                value: value,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '$percent%',
                semanticFormatterCallback: (v) => '${(v * 100).round()} percent',
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _HintRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label. $value. Double tap to fill it in.',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.borderStrong, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 26, color: context.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.titleMedium),
                    Text(value, style: context.text.bodyMedium),
                  ],
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 22,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final bool outlined;
  const _ActionButton({
    required this.label,
    required this.loading,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, working' : label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60, minWidth: 96),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          decoration: BoxDecoration(
            color: outlined
                ? Colors.transparent
                : context.accentStrong.withOpacity(0.14),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: outlined ? context.textMuted : context.accentStrong,
              width: 2,
            ),
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: context.accentStrong,
                      strokeWidth: 3,
                    ),
                  )
                : Text(
                    label,
                    style: context.text.labelLarge?.copyWith(
                      color: context.textPrimary,
                      fontSize: 18,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}