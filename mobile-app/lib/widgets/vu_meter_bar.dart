import 'package:flutter/material.dart';
import '../core/theme.dart';

class VuMeterBar extends StatelessWidget {
  final double levelL; // 0.0 to 1.0
  final double levelR; // 0.0 to 1.0
  final bool isClipped;

  const VuMeterBar({
    Key? key,
    this.levelL = 0.65,
    this.levelR = 0.62,
    this.isClipped = false,
  }) : super(key: key);

  Widget _buildChannelBar(String label, double level) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            label,
            style: const TextStyle(
              color: MakasnaTheme.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: level.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        MakasnaTheme.green,
                        MakasnaTheme.green,
                        MakasnaTheme.amber,
                        if (level > 0.85) MakasnaTheme.red,
                      ],
                      stops: const [0.0, 0.65, 0.85, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MakasnaTheme.panelElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MakasnaTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AUDIO STEREO TRUE PEAK',
                style: TextStyle(
                  color: MakasnaTheme.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isClipped ? MakasnaTheme.red : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isClipped ? 'PECAH! (CLIP)' : '-14.2 dBFS',
                  style: TextStyle(
                    color: isClipped ? Colors.white : MakasnaTheme.cyan,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildChannelBar('CH1', levelL),
          const SizedBox(height: 4),
          _buildChannelBar('CH2', levelR),
        ],
      ),
    );
  }
}
