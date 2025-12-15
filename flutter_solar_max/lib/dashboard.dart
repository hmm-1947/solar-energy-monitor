import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:solar_max/daily.dart';
import 'package:solar_max/today.dart';
import 'package:solar_max/monthly.dart';
import 'package:solar_max/yearly.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final liveRef = FirebaseDatabase.instance.ref("live");

    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final monthStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";
    final yearStr = "${now.year}";

    final dailyRef = FirebaseDatabase.instance.ref("energy/daily/$dateStr/kwh");
    final monthlyRef = FirebaseDatabase.instance.ref(
      "energy/monthly/$monthStr/kwh",
    );
    final yearlyRef = FirebaseDatabase.instance.ref(
      "energy/yearly/$yearStr/kwh",
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Solar Dashboard"),
        backgroundColor: Colors.green,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // WEB ONLY breakpoints
          final bool isWebWide = constraints.maxWidth > 900;
          final bool isWebUltra = constraints.maxWidth > 1200;

          // Android will ALWAYS be 2
          int gridColumns = 2;
          if (isWebUltra) {
            gridColumns = 4;
          } else if (isWebWide) {
            gridColumns = 3;
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<DatabaseEvent>(
              stream: liveRef.onValue,
              builder: (context, snapshot) {
                if (!snapshot.hasData ||
                    snapshot.data!.snapshot.value == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data =
                    snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

                double pvV = (data['pv_voltage'] ?? 0).toDouble();
                double pvI = (data['pv_current'] ?? 0).toDouble();
                double power = (data['ac_power'] ?? 0).toDouble();

                return Center(
                  // ✅ WEB ONLY – Android width never hits this
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      children: [
                        /* ================= TOP GAUGES (UNCHANGED) ================= */
                        Row(
                          children: [
                            gaugeCard(
                              title: "PV Voltage",
                              value: pvV,
                              unit: "V",
                              max: 500,
                              color: Colors.green,
                            ),
                            gaugeCard(
                              title: "PV Current",
                              value: pvI,
                              unit: "A",
                              max: 20,
                              color: Colors.blue,
                            ),
                            gaugeCard(
                              title: "Power",
                              value: power,
                              unit: "W",
                              max: 5000,
                              color: Colors.red,
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        /* ================= DATA GRID ================= */
                        Expanded(
                          child: GridView.count(
                            crossAxisCount: gridColumns,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: isWebWide ? 1.6 : 1.45,
                            children: [
                              infoCard(
                                "Grid Voltage",
                                "${data['grid_voltage']} V",
                                Colors.blue,
                              ),
                              infoCard(
                                "Grid Current",
                                "${data['grid_current']} A",
                                Colors.blue,
                              ),
                              infoCard(
                                "Grid Frequency",
                                "${data['grid_frequency']} Hz",
                                Colors.blue,
                              ),
                              infoCard(
                                "Work Hours",
                                "${data['work_hours']} h",
                                Colors.yellow,
                                darkText: true,
                              ),
                              energyCard(
                                context,
                                "Today Energy",
                                dailyRef,
                                Colors.green,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TodayPowerPage(),
                                  ),
                                ),
                              ),
                              energyCard(
                                context,
                                "Daily Energy",
                                monthlyRef,
                                Colors.green,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const DailyEnergyPage(),
                                  ),
                                ),
                              ),
                              energyCard(
                                context,
                                "Monthly Energy",
                                yearlyRef,
                                Colors.green,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const MonthlyEnergyPage(),
                                  ),
                                ),
                              ),
                              energyCard(
                                context,
                                "Yearly Energy",
                                yearlyRef,
                                Colors.green,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const YearlyEnergyPage(),
                                  ),
                                ),
                              ),
                              infoCard(
                                "Status",
                                data['status_text'] ?? "--",
                                Colors.yellow,
                                darkText: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /* ================= WIDGETS ================= */

  Widget gaugeCard({
    required String title,
    required double value,
    required String unit,
    required double max,
    required Color color,
  }) {
    double percent = (value / max).clamp(0, 1);

    return Expanded(
      child: Container(
        height: 160,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 80,
                  width: 80,
                  child: CircularProgressIndicator(
                    value: percent,
                    strokeWidth: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
                Text(
                  "${value.toStringAsFixed(1)}\n$unit",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget infoCard(
    String title,
    String value,
    Color color, {
    bool darkText = false,
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
          Text(
            title,
            style: TextStyle(color: darkText ? Colors.black : Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkText ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget energyCard(
    BuildContext context,
    String title,
    DatabaseReference ref,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder<DataSnapshot>(
        future: ref.get(),
        builder: (context, snapshot) {
          final value = snapshot.data?.value ?? 0;
          return infoCard(title, "$value kWh", color);
        },
      ),
    );
  }
}
