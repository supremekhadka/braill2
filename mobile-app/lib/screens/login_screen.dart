import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../models/api_models.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;

  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Login fields
  final _loginIdentifierCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  // Signup fields
  final _signupEmailCtrl = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  final _signupConfirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscureLogin = true;
  bool _obscureSignup = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginIdentifierCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPasswordCtrl.dispose();
    _signupConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    final id = _loginIdentifierCtrl.text.trim();
    final pw = _loginPasswordCtrl.text;
    if (id.isEmpty || pw.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.login(id, pw);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(
        () => _error = 'Could not reach server. Check your URL in Settings.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doSignup() async {
    final email = _signupEmailCtrl.text.trim();
    final pw = _signupPasswordCtrl.text;
    final confirm = _signupConfirmCtrl.text;

    if (email.isEmpty || pw.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.signup(email, pw);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(
        () => _error = 'Could not reach server. Check your URL in Settings.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Log in'),
            Tab(text: 'Sign up'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LoginTab(
            identifierCtrl: _loginIdentifierCtrl,
            passwordCtrl: _loginPasswordCtrl,
            obscure: _obscureLogin,
            onToggleObscure: () =>
                setState(() => _obscureLogin = !_obscureLogin),
            loading: _loading,
            error: _error,
            onSubmit: _doLogin,
          ),
          _SignupTab(
            emailCtrl: _signupEmailCtrl,
            passwordCtrl: _signupPasswordCtrl,
            confirmCtrl: _signupConfirmCtrl,
            obscurePassword: _obscureSignup,
            obscureConfirm: _obscureConfirm,
            onTogglePassword: () =>
                setState(() => _obscureSignup = !_obscureSignup),
            onToggleConfirm: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
            loading: _loading,
            error: _error,
            onSubmit: _doSignup,
          ),
        ],
      ),
    );
  }
}

// ── Login tab ─────────────────────────────────────────────────────────────────

class _LoginTab extends StatelessWidget {
  final TextEditingController identifierCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  const _LoginTab({
    required this.identifierCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(
            title: 'Welcome back',
            subtitle: 'Log in to use server-side braille inference.',
          ),
          const SizedBox(height: AppSpacing.xl),
          _AuthField(
            controller: identifierCtrl,
            label: 'Email or username',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          _AuthField(
            controller: passwordCtrl,
            label: 'Password',
            obscureText: obscure,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: context.textMuted,
              ),
              onPressed: onToggleObscure,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          _SubmitButton(label: 'Log in', loading: loading, onTap: onSubmit),
        ],
      ),
    );
  }
}

// ── Signup tab ────────────────────────────────────────────────────────────────

class _SignupTab extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  const _SignupTab({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(
            title: 'Create account',
            subtitle: 'Your email becomes your Braill. identity.',
          ),
          const SizedBox(height: AppSpacing.xl),
          _AuthField(
            controller: emailCtrl,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.newUsername],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          _AuthField(
            controller: passwordCtrl,
            label: 'Password',
            obscureText: obscurePassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: context.textMuted,
              ),
              onPressed: onTogglePassword,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _AuthField(
            controller: confirmCtrl,
            label: 'Confirm password',
            obscureText: obscureConfirm,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            suffixIcon: IconButton(
              icon: Icon(
                obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: context.textMuted,
              ),
              onPressed: onToggleConfirm,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          _SubmitButton(
            label: 'Create account',
            loading: loading,
            onTap: onSubmit,
          ),
        ],
      ),
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.headlineMedium),
        const SizedBox(height: 6),
        Text(subtitle, style: context.text.bodyMedium),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  const _AuthField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.suffixIcon,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: context.text.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: context.text.bodyMedium,
        filled: true,
        fillColor: context.bgSurface,
        suffixIcon: suffixIcon,
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
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.accentWarm.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.accentWarm.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: context.accentWarm,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: context.accentWarm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _SubmitButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: loading
                ? context.accent.withOpacity(0.5)
                : context.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: context.accent.withOpacity(loading ? 0.2 : 0.5),
            ),
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: context.accent,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    label,
                    style: context.text.labelLarge?.copyWith(
                      color: context.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
