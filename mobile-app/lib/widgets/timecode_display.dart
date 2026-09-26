import 'package:flutter/material.dart';
import '../core/theme.dart';

class TimecodeDisplay extends StatelessWidget {
  final String timecode;
  final bool isRecording;
  final String format;
  final String? feedName;

  const TimecodeDisplay({
    Key? key,
    required this.timecode,
    required this.isRecording,
    required this.format,
    this.feedName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecording ? MakasnaTheme.red : MakasnaTheme.border,
          width: 1.5,
        ),
        boxShadow: isRecording
            ? [
                BoxShadow(
                  color: MakasnaTheme.red.withOpacity(0.2),
                  blurRadius: 14,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SMPTE Color Bars subtle top stripe
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: SizedBox(
              height: 4,
              child: Row(
                children: const [
                  Expanded(child: ColoredBox(color: Color(0xFFC0C0C0))),
                  Expanded(child: ColoredBox(color: Color(0xFFC0C000))),
                  Expanded(child: ColoredBox(color: Color(0xFF00C0C0))),
                  Expanded(child: ColoredBox(color: Color(0xFF00C000))),
                  Expanded(child: ColoredBox(color: Color(0xFFC000C0))),
                  Expanded(child: ColoredBox(color: Color(0xFFC00000))),
                  Expanded(child: ColoredBox(color: Color(0xFF0000C0))),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isRecording ? 'MASTER ISO RECORDING' : 'RECORDER STANDBY',
                      style: TextStyle(
                        color: isRecording ? MakasnaTheme.red : MakasnaTheme.textDim,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: MakasnaTheme.border),
                      ),
                      child: Text(
                        format.toUpperCase(),
                        style: const TextStyle(
                          color: MakasnaTheme.cyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  timecode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.0,
                    color: isRecording ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_outlined,
                      size: 13,
                      color: isRecording ? MakasnaTheme.cyan : MakasnaTheme.textDim,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        feedName != null && feedName!.isNotEmpty
                            ? 'FEED: $feedName'
                            : 'NO FEED SELECTED',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: feedName != null && feedName!.isNotEmpty
                              ? MakasnaTheme.cyan
                              : MakasnaTheme.textDim,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
