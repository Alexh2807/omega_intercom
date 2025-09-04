import 'package:flutter/material.dart';

class DebugOverlay extends StatelessWidget {
  const DebugOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Opacity(
            opacity: 0.5,
            child: Text(
              'DEBUG',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}