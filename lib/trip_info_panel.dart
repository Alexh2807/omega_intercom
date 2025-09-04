import 'package:flutter/material.dart';

class TripInfoPanel extends StatelessWidget {
  final String duration;
  final String distance;
  final VoidCallback onCancel;
  const TripInfoPanel({super.key, required this.duration, required this.distance, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const Icon(Icons.route),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(duration, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(distance, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
            const Spacer(),
            IconButton(onPressed: onCancel, icon: const Icon(Icons.close, color: Colors.red)),
          ],
        ),
      ),
    );
  }
}