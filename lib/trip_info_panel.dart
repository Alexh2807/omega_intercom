import 'package:flutter/material.dart';

class TripInfoPanel extends StatelessWidget {
  final String duration;
  final String distance;
  final VoidCallback onCancel;

  const TripInfoPanel({
    super.key,
    required this.duration,
    required this.distance,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 15,
      right: 15,
      child: Card(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(duration, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(distance, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}