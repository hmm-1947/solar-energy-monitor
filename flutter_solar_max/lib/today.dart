import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TodayPowerPage extends StatefulWidget {
  const TodayPowerPage({super.key});

  @override
  State<TodayPowerPage> createState() => _TodayPowerPageState();
}

class _TodayPowerPageState extends State<TodayPowerPage> {
  double _zoomLevel = 1.0;
  double _scrollOffset = 0.0;

  double calculateNiceMaxY(double maxValue) {
    if (maxValue <= 500) return 600;
    if (maxValue <= 1000) return 1200;
    if (maxValue <= 2000) return 2200;
    if (maxValue <= 3000) return 3200;
    if (maxValue <= 4000) return 4200;
    if (maxValue <= 5000) return 5200;

    return ((maxValue / 1000).ceil() * 1000).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final ref = FirebaseDatabase.instance.ref("history/$date");

    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final fullMinX = startOfDay.millisecondsSinceEpoch.toDouble();
    final fullMaxX = endOfDay.millisecondsSinceEpoch.toDouble();
    final fullRange = fullMaxX - fullMinX;

    final visibleRange = fullRange / _zoomLevel;
    final minX = (fullMinX + _scrollOffset * fullRange).clamp(
      fullMinX,
      fullMaxX - visibleRange,
    );
    final maxX = (minX + visibleRange).clamp(fullMinX, fullMaxX);

    Duration getTimeInterval() {
      final visibleHours = visibleRange / (1000 * 60 * 60);

      if (visibleHours <= 2) return const Duration(minutes: 5);
      if (visibleHours <= 6) return const Duration(minutes: 15);
      if (visibleHours <= 12) return const Duration(minutes: 30);
      return const Duration(hours: 1);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today Power"),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () {
              setState(() {
                _zoomLevel = (_zoomLevel * 1.5).clamp(1.0, 10.0);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () {
              setState(() {
                _zoomLevel = (_zoomLevel / 1.5).clamp(1.0, 10.0);
                _scrollOffset = 0.0;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _zoomLevel = 1.0;
                _scrollOffset = 0.0;
              });
            },
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final raw = Map<String, dynamic>.from(
            snapshot.data!.snapshot.value as Map,
          );

          final List<FlSpot> spots = [];
          double maxPower = 0;

          for (final entry in raw.entries) {
            final parts = entry.key.split(":");
            final hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);

            final time = DateTime(now.year, now.month, now.day, hour, minute);
            final power = (entry.value as num).toDouble();

            if (power > maxPower) maxPower = power;

            spots.add(FlSpot(time.millisecondsSinceEpoch.toDouble(), power));
          }

          spots.sort((a, b) => a.x.compareTo(b.x));

          final maxY = calculateNiceMaxY(maxPower);
          final yInterval = maxY / 10;

          return Column(
            children: [
              if (_zoomLevel > 1.0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text("Scroll"),
                      Expanded(
                        child: Slider(
                          value: _scrollOffset,
                          onChanged: (v) => setState(() => _scrollOffset = v),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LineChart(
                    LineChartData(
                      minX: minX,
                      maxX: maxX,
                      minY: 0,
                      maxY: maxY,

                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: false,
                          barWidth: 2,
                          color: Colors.orange,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: true),
                        ),
                      ],

                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: yInterval,
                      ),
                      borderData: FlBorderData(show: true),
                      lineTouchData: LineTouchData(enabled: true),

                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: yInterval,
                            reservedSize: 50,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: getTimeInterval().inMilliseconds
                                .toDouble(),
                            getTitlesWidget: (value, meta) {
                              final time = DateTime.fromMillisecondsSinceEpoch(
                                value.toInt(),
                              );
                              return Text(
                                "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
