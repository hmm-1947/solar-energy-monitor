import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class YearlyEnergyPage extends StatelessWidget {
  const YearlyEnergyPage({super.key});

  double calculateNiceMaxY(double maxValue) {
    if (maxValue <= 30) return 30;
    if (maxValue <= 50) return 60;
    if (maxValue <= 100) return 120;
    if (maxValue <= 200) return 220;
    if (maxValue <= 400) return 420;
    if (maxValue <= 500) return 520;

    return ((maxValue / 100).ceil() * 100).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref("energy/yearly");

    return Scaffold(
      appBar: AppBar(title: const Text("Yearly Energy")),
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
            final year = int.parse(key);
            final kwh = (value['kwh'] ?? 0).toDouble();

            if (kwh > maxValue) maxValue = kwh;

            bars.add(
              BarChartGroupData(
                x: year,
                barRods: [
                  BarChartRodData(toY: kwh, color: Colors.purple, width: 18),
                ],
              ),
            );
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
                    sideTitles: SideTitles(showTitles: true, reservedSize: 50),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 11),
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
