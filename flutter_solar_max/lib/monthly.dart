import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class MonthlyEnergyPage extends StatelessWidget {
  const MonthlyEnergyPage({super.key});

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
    final year = DateTime.now().year.toString();
    final ref = FirebaseDatabase.instance.ref("energy/monthly");

    return Scaffold(
      appBar: AppBar(title: const Text("Monthly Energy")),
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
            if (key.startsWith(year)) {
              final month = int.parse(key.split('-')[1]);
              final kwh = (value['kwh'] ?? 0).toDouble();

              if (kwh > maxValue) maxValue = kwh;

              bars.add(
                BarChartGroupData(
                  x: month,
                  barRods: [
                    BarChartRodData(toY: kwh, color: Colors.blue, width: 14),
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
                    sideTitles: SideTitles(showTitles: true, reservedSize: 48),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const months = [
                          "",
                          "Jan",
                          "Feb",
                          "Mar",
                          "Apr",
                          "May",
                          "Jun",
                          "Jul",
                          "Aug",
                          "Sep",
                          "Oct",
                          "Nov",
                          "Dec",
                        ];
                        return Text(
                          months[value.toInt()],
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
