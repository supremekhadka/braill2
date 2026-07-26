import 'package:flutter/material.dart';
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

  // ── Scanning toggles ────────────────────────────────────────────────────
  late bool _autoCrop;
  late bool _autoRotate;

  // ── Developer section ───────────────────────────────────────────────────
  late bool _developerMode;
  late double _confThreshold;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.settingsService.baseUrl);
    _autoCrop = widget.settingsService.autoCrop;
    _autoRotate = widget.settingsService.autoRotate;
    _developerMode = widget.settingsService.developerModeEnabled;
    _confThreshold = widget.settingsService.confThreshold;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'URL cannot be empty.');
      return;
    }
    if (!url.startsWith('http')) {
      setState(() => _error = 'URL must start with http:// or https://');
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
  }

  Future<void> _setAutoCrop(bool value) async {
    setState(() => _autoCrop = value);
    await widget.settingsService.setAutoCrop(value);
  }

  Future<void> _setAutoRotate(bool value) async {
    setState(() => _autoRotate = value);
    await widget.settingsService.setAutoRotate(value);
  }

  Future<void> _setDeveloperMode(bool value) async {
    setState(() => _developerMode = value);
    await widget.settingsService.setDeveloperModeEnabled(value);
  }

  /// Called continuously while dragging, for a responsive label — the value
  /// isn't persisted until [_commitConfThreshold] on drag end, so we're not
  /// hitting SharedPreferences on every frame.
  void _previewConfThreshold(double value) {
    setState(() => _confThreshold = value);
  }

  Future<void> _commitConfThreshold(double value) async {
    await widget.settingsService.setConfThreshold(value);
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
            // ── Scanning section ─────────────────────────────────────────
            Text('Scanning', style: context.text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Control how the document scanner processes each capture. '
              'Both are off by default so the photo you take is used as-is.',
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
              icon: Icons.screen_rotation_alt_outlined,
              label: 'Auto-rotate',
              subtitle: 'Automatically straighten the page after capture',
              value: _autoRotate,
              onChanged: _setAutoRotate,
            ),

            const SizedBox(height: AppSpacing.xl),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.xl),

            // ── Developer section ────────────────────────────────────────
            _ToggleRow(
              icon: Icons.developer_mode_outlined,
              label: 'Developer options',
              subtitle: 'Show advanced settings: backend server & detection tuning',
              value: _developerMode,
              onChanged: _setDeveloperMode,
            ),
            if (_developerMode) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Server', style: context.text.titleLarge),
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
                onTap: () => _urlCtrl.text = 'http://10.0.2.2:8000',
              ),
              const SizedBox(height: 8),
              _HintRow(
                icon: Icons.laptop_mac_outlined,
                label: 'iOS simulator / macOS',
                value: 'http://localhost:8000',
                onTap: () => _urlCtrl.text = 'http://localhost:8000',
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
                    borderSide: BorderSide(color: context.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 14,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.accentWarm,
                  ),
                ),
              ],
              if (_success != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _success!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.accent,
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
                    onTap: _saving ? () {} : _reset,
                    outlined: true,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              Text('Detection', style: context.text.titleLarge),
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: context.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.titleMedium),
                Text(
                  subtitle,
                  style: context.text.bodyMedium?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: context.accent,
          ),
        ],
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
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: context.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: context.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Confidence threshold',
                  style: context.text.titleMedium,
                ),
              ),
              Text(
                '$percent%',
                style: context.text.bodyMedium?.copyWith(
                  color: context.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.accent,
              thumbColor: context.accent,
              inactiveTrackColor: context.border,
              overlayColor: context.accent.withOpacity(0.12),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: '$percent%',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: context.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.titleMedium),
                  Text(
                    value,
                    style: context.text.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.content_copy_outlined,
              size: 16,
              color: context.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final bool outlined;
  const _ActionButton({
    required this.label,
    required this.loading,
    required this.onTap,
    this.outlined = false,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : context.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: outlined ? context.border : context.accent.withOpacity(0.5),
          ),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: context.accent,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: context.text.labelLarge?.copyWith(
                    color: outlined ? context.textMuted : context.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}