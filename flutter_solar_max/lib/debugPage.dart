import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class DebugPage extends StatelessWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    final systemRef = FirebaseDatabase.instance.ref("system");

    return Scaffold(
      appBar: AppBar(
        title: const Text("System Debug"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<DatabaseEvent>(
          stream: systemRef.onValue,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

            final bool inverterOnline = data['inverter_online'] ?? false;
            final int modbusError = data['modbus_error_code'] ?? 0;
            final int uptime = data['uptime_seconds'] ?? 0;
            final int lastSeen = data['last_seen'] ?? 0;
            final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final bool systemOnline = (now - lastSeen) < 120; // 2 min timeout

            return GridView.count(
              crossAxisCount: 2, // ⬅️ more columns = smaller cards
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1, // ⬅️ closer to square & compact
              children: [
                debugCard(
                  icon: systemOnline ? Icons.wifi : Icons.wifi_off,
                  label: "System",
                  value: systemOnline ? "Online" : "Offline",
                  color: systemOnline ? Colors.green : Colors.red,
                ),

                debugCard(
                  icon: Icons.power,
                  label: "Inverter",
                  value: inverterOnline ? "Online" : "Offline",
                  color: inverterOnline ? Colors.green : Colors.red,
                ),
                debugCard(
                  icon: Icons.error,
                  label: "Modbus Error",
                  value: modbusError.toString(),
                  color: modbusError == 0 ? Colors.green : Colors.red,
                ),
                debugCard(
                  icon: Icons.timer,
                  label: "Uptime",
                  value: formatUptime(uptime),
                  color: Colors.blue,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /* ================= HELPERS ================= */

  Widget debugCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: Colors.white),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String formatUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return "${h}h ${m}m ${s}s";
  }
}
