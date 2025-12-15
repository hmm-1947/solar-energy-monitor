import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class DailyEnergyPage extends StatelessWidget {
  const DailyEnergyPage({super.key});

  double calculateNiceMaxY(double maxValue) {
    if (maxValue <= 5) return 5;
    if (maxValue <= 10) return 12;
    if (maxValue <= 20) return 22;
    if (maxValue <= 30) return 32;
    if (maxValue <= 40) return 42;
    if (maxValue <= 50) return 52;

    return ((maxValue / 10).ceil() * 10).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthPrefix = "${now.year}-${now.month.toString().padLeft(2, '0')}";

    final ref = FirebaseDatabase.instance.ref("energy/daily");

    return Scaffold(
      appBar: AppBar(title: const Text("Daily Energy")),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final raw = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

          final bars = <BarChartGroupData>[];
          double maxValue = 0;

          raw.forEach((key, value) {
            if (key.startsWith(monthPrefix)) {
              final day = int.parse(key.split('-')[2]);
              final kwh = (value['kwh'] ?? 0).toDouble();

              if (kwh > maxValue) maxValue = kwh;

              bars.add(
                BarChartGroupData(
                  x: day,
                  barRods: [
                    BarChartRodData(toY: kwh, color: Colors.green, width: 12),
                  ],
                ),
              );
            }
          });

          bars.sort((a, b) => a.x.compareTo(b.x));

          final maxY = calculateNiceMaxY(maxValue);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: BarChart(
              BarChartData(
                barGroups: bars,
                minY: 0,
                maxY: maxY,

                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: true),

                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 42),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
