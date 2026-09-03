import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl   = TextEditingController();
  final _passCtrl = TextEditingController();
  bool    _loading   = false;
  bool    _isStudent = false;
  bool    _obscure   = true;
  String? _error;

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    final auth = context.read<AuthService>();
    String? err;
    try {
      err = _isStudent
          ? await auth.loginStudent(
              _idCtrl.text.trim().toUpperCase(),
              _passCtrl.text.trim())
          : await auth.loginFaculty(
              _idCtrl.text.trim(),
              _passCtrl.text.trim());
    } catch (e) {
      err = 'Login failed: ${e.toString().replaceAll('Exception:', '').trim()}';
    }
    if (!mounted) return;
    setState(() { _loading = false; if (err != null) _error = err; });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = R.isMobile(context);
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: mobile ? _MobileLogin(state: this) : _DesktopLogin(state: this),
    );
  }
}

// ── Desktop: side panel + form side by side ───────────────────────────────────
class _DesktopLogin extends StatelessWidget {
  final _LoginScreenState state;
  const _DesktopLogin({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      // Left branding panel
      Container(
        width: 400,
        color: AppTheme.sidebar,
        child: Stack(children: [
          Positioned(top: -80, left: -80,
            child: _glow(260, AppTheme.primary.withOpacity(0.12))),
          Positioned(bottom: -60, right: -60,
            child: _glow(220, AppTheme.accentPink.withOpacity(0.10))),
          Positioned(top: 260, right: -40,
            child: _glow(140, AppTheme.cyan.withOpacity(0.07))),
          Padding(
            padding: const EdgeInsets.all(44),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 20),
              _LogoRow(),
              const SizedBox(height: 56),
              const Text('Automated\nCollege\nScheduling',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 38, fontWeight: FontWeight.w900,
                  height: 1.12, letterSpacing: -1.5)),
              const SizedBox(height: 20),
              Text('AI-powered timetable generation,\nattendance tracking, and\nacademic insights.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14, height: 1.65)),
              const Spacer(),
              _FeaturePills(),
              const SizedBox(height: 44),
            ])),
        ])),
      // Right form
      Expanded(child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _LoginForm(state: state))))),
    ]);
  }
}

// ── Mobile: full-screen scrollable form with compact branding header ──────────
class _MobileLogin extends StatelessWidget {
  final _LoginScreenState state;
  const _MobileLogin({required this.state});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(children: [
          // Compact brand header
          Container(
            width: double.infinity,
            color: AppTheme.sidebar,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Stack(children: [
              Positioned(top: -40, right: -40,
                child: _glow(180, AppTheme.primary.withOpacity(0.12))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _LogoRow(),
                const SizedBox(height: 24),
                const Text('Automated College\nScheduling',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26, fontWeight: FontWeight.w900,
                    height: 1.2, letterSpacing: -0.8)),
                const SizedBox(height: 12),
                Text('AI timetable · Attendance · Multi-role',
                  style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 18),
                _FeaturePills(),
              ]),
            ])),
          // Form below
          Padding(
            padding: const EdgeInsets.all(24),
            child: _LoginForm(state: state)),
        ]),
      ),
    );
  }
}

// ── Shared form widget ────────────────────────────────────────────────────────
class _LoginForm extends StatelessWidget {
  final _LoginScreenState state;
  const _LoginForm({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Welcome back',
          style: TextStyle(color: AppTheme.textPrimary,
            fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        const SizedBox(height: 5),
        const Text('Sign in to continue to your dashboard',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 28),

        // Role toggle
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            Expanded(child: _RoleBtn(
              label: 'Faculty / Admin', active: !s._isStudent,
              onTap: () => s.setState(() { s._isStudent = false; s._error = null; }))),
            Expanded(child: _RoleBtn(
              label: 'Student', active: s._isStudent,
              onTap: () => s.setState(() { s._isStudent = true; s._error = null; }))),
          ])),
        const SizedBox(height: 24),

        _Label(s._isStudent ? 'Roll Number' : 'Employee ID'),
        const SizedBox(height: 7),
        TextField(
          controller: s._idCtrl,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          textCapitalization: s._isStudent
              ? TextCapitalization.characters
              : TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: s._isStudent
                ? 'Roll number  e.g. 21CS001'
                : 'Employee ID  e.g. TCH001',
            prefixIcon: const Icon(Icons.badge_outlined,
              size: 17, color: AppTheme.textMuted))),

        const SizedBox(height: 16),
        _Label(s._isStudent ? 'Password' : 'Password'),
        const SizedBox(height: 7),
        TextField(
          controller: s._passCtrl,
          obscureText: s._obscure,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: s._isStudent
                ? 'Password or roll number + K to recover'
                : 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded,
              size: 17, color: AppTheme.textMuted),
            suffixIcon: IconButton(
              icon: Icon(s._obscure
                ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 17, color: AppTheme.textMuted),
              onPressed: () => s.setState(() => s._obscure = !s._obscure)))),
        // Hint box — shown for faculty (after password field) and student
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppTheme.primary.withOpacity(0.18))),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
              size: 14, color: AppTheme.primaryLt),
            const SizedBox(width: 8),
            Expanded(child: Text(
              s._isStudent
                ? 'Default password = your roll number.\n'
                  'Forgot password? Enter roll number + K (e.g. 23CS501K)'
                : 'Faculty: Employee ID as username.\n'
                  'Default password = your Employee ID.',
              style: const TextStyle(
                color: AppTheme.primaryLt, fontSize: 11.5, height: 1.4))),
          ])),

        if (s._error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error.withOpacity(0.25))),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                color: AppTheme.error, size: 16),
              const SizedBox(width: 9),
              Expanded(child: Text(s._error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 12.5))),
            ])),
        ],

        const SizedBox(height: 24),

        // Sign in button
        SizedBox(
          width: double.infinity, height: 50,
          child: s._loading
            ? Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border)),
                child: const Center(child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    color: AppTheme.primary, strokeWidth: 2))))
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [AppTheme.glowPurple]),
                child: ElevatedButton.icon(
                  onPressed: s._login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: const Text('Sign In',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))))),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────
class _LogoRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        gradient: AppTheme.purpleGradient,
        borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.school_rounded, color: Colors.white, size: 18)),
    const SizedBox(width: 10),
    const Text('TimeTable', style: TextStyle(
      color: AppTheme.textPrimary, fontSize: 15,
      fontWeight: FontWeight.w800, letterSpacing: -0.4)),
  ]);
}

class _FeaturePills extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    _pill('AI Scheduling',  Icons.auto_awesome_rounded, AppTheme.primary),
    _pill('Attendance',     Icons.bar_chart_rounded,    AppTheme.secondary),
    _pill('Multi-Role',     Icons.people_rounded,       AppTheme.cyan),
    _pill('Offline-First',  Icons.wifi_off_rounded,     AppTheme.emerald),
  ]);

  static Widget _pill(String label, IconData icon, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]));
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(color: AppTheme.textSecondary,
      fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3));
}

class _RoleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _RoleBtn({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 38, alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: active ? AppTheme.purpleGradient : null,
        borderRadius: BorderRadius.circular(9)),
      child: Text(label, style: TextStyle(
        color: active ? Colors.white : AppTheme.textSecondary,
        fontWeight: FontWeight.w600, fontSize: 13))));
}

Widget _glow(double size, Color color) => Container(
  width: size, height: size,
  decoration: BoxDecoration(shape: BoxShape.circle, color: color));
