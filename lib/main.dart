import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TimetableApp());
}

class TimetableApp extends StatelessWidget {
  const TimetableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Расписание СПбГУ',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
      ),
      home: const TimetableScreen(),
    );
  }
}

// Модель для пары
class Lesson {
  final String time;
  final String subject;
  final String educator;
  final String locations;

  Lesson({
    required this.time,
    required this.subject,
    required this.educator,
    required this.locations,
  });

  Map<String, dynamic> toJson() => {
    'time': time,
    'subject': subject,
    'educator': educator,
    'locations': locations,
  };

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
    time: json['time'] ?? '',
    subject: json['subject'] ?? '',
    educator: json['educator'] ?? '',
    locations: json['locations'] ?? '',
  );
}

// Модель для учебного дня
class DaySchedule {
  final String dayName;
  final List<Lesson> lessons;

  DaySchedule({required this.dayName, required this.lessons});

  Map<String, dynamic> toJson() => {
    'dayName': dayName,
    'lessons': lessons.map((e) => e.toJson()).toList(),
  };

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
    dayName: json['dayName'],
    lessons: (json['lessons'] as List).map((e) => Lesson.fromJson(e)).toList(),
  );
}

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  static const String groupId = "474863"; // Ваш ID группы
  List<DaySchedule> currentSchedule = [];
  bool isLoading = true;
  String? errorMessage;
  bool hasChangesFromBaseline = false;

  @override
  void initState() {
    super.initState();
    fetchAndProcessSchedule();
  }

  // Загрузка и фильтрация расписания
  Future<void> fetchAndProcessSchedule() setState) async {
    setState(() => isLoading = true);
    final url = Uri.parse('https://timetable.spbu.ru/api/v1/groups/$groupId/events');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List daysRaw = data['Days'] ?? [];

        List<DaySchedule> parsedDays = [];

        for (var day in daysRaw) {
          String dayName = day['DayString'] ?? '';
          List events = day['DayStudyEvents'] ?? [];

          // Группировка и схлопывание Английского языка
          Map<String, Lesson> uniqueLessonsAtTime = {};

          for (var event in events) {
            String time = event['TimeIntervalString'] ?? '';
            String subject = event['Subject'] ?? '';
            String educators = event['EducatorsDisplayText'] ?? '';
            String locations = event['LocationsDisplayText'] ?? '';

            // Если предмет - английский/иностранный язык
            if (subject.toLowerCase().contains('иностранный') || 
                subject.toLowerCase().contains('английский')) {
              subject = 'Английский язык';
              educators = 'По подгруппам';
              locations = 'По подгруппам';
            }

            // Ключ для группировки: Время + Предмет
            String key = "$time-$subject";
            if (!uniqueLessonsAtTime.containsKey(key)) {
              uniqueLessonsAtTime[key] = Lesson(
                time: time,
                subject: subject,
                educator: educators,
                locations: locations,
              );
            }
          }

          parsedDays.add(DaySchedule(
            dayName: dayName,
            lessons: uniqueLessonsAtTime.values.toList(),
          ));
        }

        setState(() {
          currentSchedule = parsedDays;
          isLoading = false;
        });

        // Проверка на изменения относительно эталона
        await checkBaselineComparison(parsedDays);

      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
    }
  }

  // Сравнение с эталоном
  Future<void> checkBaselineComparison(List<DaySchedule> fresh) async {
    final prefs = await SharedPreferences.getInstance();
    final baselineJson = prefs.getString('baseline_schedule');

    if (baselineJson == null) {
      // Если эталона еще нет, сохраняем первый результат как эталон
      await saveAsBaseline(quiet: true);
    } else {
      String freshJson = json.encode(fresh.map((e) => e.toJson()).toList());
      if (freshJson != baselineJson) {
        setState(() {
          hasChangesFromBaseline = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Внимание! Расписание отличается от сохраненного эталона!'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          hasChangesFromBaseline = false;
        });
      }
    }
  }

  // Запомнить текущее расписание как эталон
  Future<void> saveAsBaseline({bool quiet = false}) async {
    final prefs = await SharedPreferences.getInstance();
    String freshJson = json.encode(currentSchedule.map((e) => e.toJson()).toList());
    await prefs.setString('baseline_schedule', freshJson);

    setState(() {
      hasChangesFromBaseline = false;
    });

    if (!quiet && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Расписание успешно сохранено как эталон!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание СПбГУ'),
        actions: [
          IconButton(
            tooltip: 'Запомнить как эталон',
            icon: const Icon(Icons.bookmark_added_outlined),
            onPressed: currentSchedule.isNotEmpty ? () => saveAsBaseline() : null,
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: fetchAndProcessSchedule,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text('Ошибка: $errorMessage'))
              : Column(
                  children: [
                    if (hasChangesFromBaseline)
                      Container(
                        color: Colors.amber.shade100,
                        padding: const EdgeInsets.all(10),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Обнаружены изменения по сравнению с эталоном!',
                                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: currentSchedule.length,
                        itemBuilder: (context, index) {
                          final day = currentSchedule[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ExpansionTile(
                              initiallyExpanded: true,
                              title: Text(
                                day.dayName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              children: day.lessons.isEmpty
                                  ? [const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('Пар нет', style: TextStyle(color: Colors.grey)),
                                    )]
                                  : day.lessons.map((lesson) {
                                      return ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            lesson.time,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueAccent,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          lesson.subject,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          '${lesson.locations}\n${lesson.educator}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        isThreeLine: true,
                                      );
                                    }).toList(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
