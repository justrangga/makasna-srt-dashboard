import 'package:flutter/material.dart';
import '../core/theme.dart';

class TallyLamp extends StatefulWidget {
  final bool isRecording;

  const TallyLamp({Key? key, required this.isRecording}) : super(key: key);

  @override
  State<TallyLamp> createState() => _TallyLampState();
}

class _TallyLampState extends State<TallyLamp> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const BorderSide(color: Color(0xFF334155), width: 1.2).color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.stop, color: Color(0xFF94A3B8), size: 14),
            SizedBox(width: 6),
            Text(
              'STANDBY',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final opacity = 0.5 + (_animController.value * 0.5);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: MakasnaTheme.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MakasnaTheme.red, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: MakasnaTheme.red.withOpacity(opacity * 0.6),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: MakasnaTheme.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MakasnaTheme.red.withOpacity(opacity),
                      blurRadius: 6,
                    )
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'REC ACTIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
