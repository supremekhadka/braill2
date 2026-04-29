import 'package:flutter/material.dart';
import 'realtime_screen.dart';
import 'capture_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // Title
              const Text(
                'Braill.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Read Braille',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),

              const Spacer(),

              // Real-time mode card
              _ModeCard(
                icon: Icons.videocam_rounded,
                title: 'Real-time',
                description: 'Detect braille live through your camera',
                color: Colors.greenAccent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RealtimeScreen()),
                ),
              ),

              const SizedBox(height: 16),

              // Capture/upload mode card
              _ModeCard(
                icon: Icons.photo_library_rounded,
                title: 'Capture / Upload',
                description: 'Take a photo or pick one from your gallery',
                color: Colors.blueAccent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CaptureScreen()),
                ),
              ),

              const Spacer(),

              // Footer
              // const Center(
              //   child: Text(
              //     'YOLO26s · 63 braille classes',
              //     style: TextStyle(color: Colors.white24, fontSize: 12),
              //   ),
              // ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}
