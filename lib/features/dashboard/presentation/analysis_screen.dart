import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../auth/domain/auth_controller.dart';
import '../../expenses/data/expense_repository.dart';
import '../../expenses/domain/expense_model.dart';

// Axis unit for line chart x-axis
enum _AxisUnit { hourOfDay, hourSinceStart, daySinceStart }

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});
  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  String _view = 'list'; // list | bar | pie | line
  String _timeframe = 'month'; // week | month | year | all | custom
  DateTimeRange? _customRange;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return const Scaffold(body: Center(child: Text('User not found')));

    final repo = ref.watch(expenseRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        actions: [
          PopupMenuButton<String>(
            initialValue: _view,
            onSelected: (v) => setState(() => _view = v),
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'list', child: Text('Simple List')),
              PopupMenuItem(value: 'bar', child: Text('Bar Graph')),
              PopupMenuItem(value: 'pie', child: Text('Pie Chart')),
              PopupMenuItem(value: 'line', child: Text('Line Graph')),
            ],
          )
        ],
      ),
      body: StreamBuilder<List<ExpenseModel>>(
        stream: repo.getUserExpenses(user.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? const <ExpenseModel>[];
          final myExpenses = all;
          final now = DateTime.now();
          final ranges = {
            'week': DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
            'month': DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
            'year': DateTimeRange(start: now.subtract(const Duration(days: 365)), end: now),
            'all': DateTimeRange(start: DateTime(1970), end: now),
          };
          final activeRange = _timeframe == 'custom' && _customRange != null ? _customRange! : (ranges[_timeframe] ?? ranges['month']!);
          final list = myExpenses.where((e) => !e.date.isBefore(activeRange.start) && !e.date.isAfter(activeRange.end)).toList();

          // Aggregations
          double total = list.fold(0.0, (s, e) => s + (e.amount / (e.splitBetween.isEmpty ? 1 : e.splitBetween.length)));

          final byDow = List<double>.filled(7, 0);
          final byHour = List<double>.filled(24, 0);
          final byMonth = <DateTime, double>{};
          final byCategory = <String, double>{};
          for (final e in list) {
            final share = e.amount / (e.splitBetween.isEmpty ? 1 : e.splitBetween.length);
            byDow[e.date.weekday % 7] += share; // weekday: Mon=1..Sun=7 -> index 0..6
            byHour[e.date.hour] += share;
            final ym = DateTime(e.date.year, e.date.month);
            byMonth[ym] = (byMonth[ym] ?? 0) + share;
            byCategory[e.category] = (byCategory[e.category] ?? 0) + share;
          }

          Widget sectionTitle(String t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t, style: Theme.of(context).textTheme.titleLarge),
              );

          Widget listView() => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  sectionTitle('Total Expenses Overview'),
                  Card(child: ListTile(title: const Text('Total (selected range)'), trailing: Text('₹${total.toStringAsFixed(2)}'))),
                  const SizedBox(height: 12),
                  sectionTitle('Day-of-Week (Mon–Sun)'),
                  ...List.generate(7, (i) => ListTile(title: Text(['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][(i+1)%7]), trailing: Text('₹${byDow[i].toStringAsFixed(2)}'))),
                  const SizedBox(height: 12),
                  sectionTitle('Time-of-Day (0-23)'),
                  ...List.generate(24, (h) => ListTile(title: Text('$h:00'), trailing: Text('₹${byHour[h].toStringAsFixed(2)}'))),
                  const SizedBox(height: 12),
                  sectionTitle('Category Breakdown'),
                  ...byCategory.entries.map((e) => ListTile(title: Text(e.key), trailing: Text('₹${e.value.toStringAsFixed(2)}'))),
                ],
              );

          List<Color> palette = [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
            Colors.teal,
            Colors.orange,
            Colors.purple,
            Colors.indigo,
            Colors.cyan,
            Colors.pink,
          ];

          Widget barDow() => Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Day-of-Week Analysis', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Your average share by day. Use it to spot which days you tend to spend more.', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 220,
                        child: BarChart(
                          BarChartData(
                            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (byDow.reduce((a,b)=> a>b?a:b) / 4).clamp(1, double.infinity)),
                            borderData: FlBorderData(show: false),
                            alignment: BarChartAlignment.spaceAround,
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, m) => Text('₹${v.toInt()}'))),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, m) {
                                    const labels = ['S','M','T','W','T','F','S'];
                                    final i = v.toInt();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(i>=0&&i<7?labels[i]:'', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: byDow[i],
                                gradient: LinearGradient(colors: [palette[i%palette.length].withOpacity(.85), palette[(i+1)%palette.length].withOpacity(.65)]),
                                borderRadius: BorderRadius.circular(6),
                                width: 18,
                              ),
                            ])),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: Colors.black87,
                                getTooltipItem: (g, gi, r, ri) => BarTooltipItem('₹${r.toY.toStringAsFixed(2)}', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          for (int i=0; i<7; i++) Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[i%palette.length], shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][i]),
                            ],
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );

          Widget pieCategory() {
            final totalCat = byCategory.values.fold(0.0, (a, b) => a + b);
            final slices = byCategory.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
            if (slices.isEmpty) return const Center(child: Text('No category data'));
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Category-Based Insights', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Proportional distribution of your share across categories. Colors map to categories in the legend below.', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: PieChart(PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 48,
                        sections: [
                          for (int i = 0; i < slices.length; i++)
                            PieChartSectionData(
                              color: palette[i%palette.length],
                              value: slices[i].value,
                              title: '${((slices[i].value / (totalCat==0?1:totalCat)) * 100).toStringAsFixed(0)}%',
                              radius: 70,
                              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            )
                        ],
                      )),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        for (int i=0; i<slices.length; i++) Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[i%palette.length], shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('${slices[i].key} (₹${slices[i].value.toStringAsFixed(0)})'),
                          ],
                        )
                      ],
                    )
                  ],
                ),
              ),
            );
          }

          Widget lineTrend() {
            if (list.isEmpty) return const Center(child: Text('No trend data'));
            // Build per-expense spots based on actual date+time
            final s = activeRange.start;
            final e = activeRange.end;
            final duration = e.difference(s);

            // Helper: x axis unit chooser
            _AxisUnit unit;
            if (s.year == e.year && s.month == e.month && s.day == e.day) {
              unit = _AxisUnit.hourOfDay; // single day → 0–23 hours
            } else if (duration.inDays <= 7) {
              unit = _AxisUnit.hourSinceStart; // dense hourly timeline for short ranges
            } else {
              unit = _AxisUnit.daySinceStart; // longer timelines → per-day spacing
            }

            double xFor(DateTime d) => unit == _AxisUnit.hourOfDay
                ? d.hour + (d.minute / 60.0)
                : unit == _AxisUnit.hourSinceStart
                    ? d.difference(s).inMinutes / 60.0
                    : d.difference(s).inHours / 24.0;

            // Compute user's share for each expense and create a spot per expense
            final expensesSorted = [...list]..sort((a, b) => a.date.compareTo(b.date));
            final spots = <FlSpot>[];
            double maxY = 0;
            for (final exp in expensesSorted) {
              final perHead = exp.splitBetween.isEmpty ? exp.amount : exp.amount / exp.splitBetween.length;
              final y = perHead;
              final x = xFor(exp.date);
              if (y > maxY) maxY = y;
              spots.add(FlSpot(x, y));
            }

            // Axis bounds and labels
            double minX;
            double maxX;
            Widget bottomTitle(double v) => unit == _AxisUnit.hourOfDay
                ? Text('${v.round().clamp(0, 23).toString().padLeft(2, '0')}:00')
                : unit == _AxisUnit.hourSinceStart
                    ? Text('${v.round()}h')
                    : Text('${v.round()}d');

            if (unit == _AxisUnit.hourOfDay) {
              minX = 0;
              maxX = 23;
            } else if (unit == _AxisUnit.hourSinceStart) {
              minX = 0;
              maxX = duration.inMinutes / 60.0;
            } else {
              minX = 0;
              maxX = duration.inHours / 24.0;
            }

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spending Trend', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      unit == _AxisUnit.hourOfDay
                          ? 'Per-expense line through the day (0–23h).'
                          : unit == _AxisUnit.hourSinceStart
                              ? 'Per-expense line by hours since range start.'
                              : 'Per-expense line by days since range start.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 240,
                      child: LineChart(LineChartData(
                        minX: minX,
                        maxX: maxX,
                        minY: 0,
                        maxY: (maxY * 1.2 == 0 ? 1 : maxY * 1.2),
                        gridData: FlGridData(show: true, drawVerticalLine: true),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (v, m) => bottomTitle(v),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text('₹${v.toInt()}')),
                          ),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            tooltipBgColor: Colors.black87,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots
                                  .map((s) => LineTooltipItem('₹${s.y.toStringAsFixed(2)}', const TextStyle(color: Colors.white)))
                                  .toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary.withOpacity(.25),
                                  Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          )
                        ],
                      )),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        DropdownButton<String>(
                          value: _timeframe,
                          items: const [
                            DropdownMenuItem(value: 'week', child: Text('Past week')),
                            DropdownMenuItem(value: 'month', child: Text('Past month')),
                            DropdownMenuItem(value: 'year', child: Text('Past year')),
                            DropdownMenuItem(value: 'all', child: Text('All time')),
                            DropdownMenuItem(value: 'custom', child: Text('Custom range')),
                          ],
                          onChanged: (v) => setState(() => _timeframe = v ?? 'month'),
                        ),
                        DropdownButton<String>(
                          value: _view,
                          items: const [
                            DropdownMenuItem(value: 'list', child: Text('List')),
                            DropdownMenuItem(value: 'bar', child: Text('Bar')),
                            DropdownMenuItem(value: 'pie', child: Text('Pie')),
                            DropdownMenuItem(value: 'line', child: Text('Line')),
                          ],
                          onChanged: (v) => setState(() => _view = v ?? 'list'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            final initial = _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2010),
                              lastDate: DateTime(now.year + 1),
                              initialDateRange: initial,
                            );
                            if (picked != null) {
                              setState(() {
                                _timeframe = 'custom';
                                _customRange = picked;
                              });
                            }
                          },
                          icon: const Icon(Icons.date_range),
                          label: Text(_timeframe == 'custom' && _customRange != null
                              ? '${_customRange!.start.toLocal().toString().split(' ').first} → ${_customRange!.end.toLocal().toString().split(' ').first}'
                              : 'Pick date range'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: now,
                              firstDate: DateTime(2010),
                              lastDate: DateTime(now.year + 1),
                            );
                            if (picked != null) {
                              setState(() {
                                _timeframe = 'custom';
                                _customRange = DateTimeRange(
                                  start: DateTime(picked.year, picked.month, picked.day),
                                  end: DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.today),
                          label: const Text('Pick a day'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _view == 'list'
                      ? listView()
                      : _view == 'bar'
                          ? barDow()
                          : _view == 'pie'
                              ? pieCategory()
                              : lineTrend(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


