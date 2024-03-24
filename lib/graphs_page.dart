import 'package:csv/csv.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart';
import 'package:flexify/add_exercise_page.dart';
import 'package:flexify/app_state.dart';
import 'package:flexify/database.dart';
import 'package:flexify/enter_weight_page.dart';
import 'package:flexify/main.dart';
import 'package:flexify/timer_page.dart';
import 'package:flexify/utils.dart';
import 'package:flexify/view_graph_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:provider/provider.dart';

import 'graph_tile.dart';

class GraphsPage extends StatefulWidget {
  const GraphsPage({super.key});

  @override
  createState() => _GraphsPageState();
}

class _GraphsPageState extends State<GraphsPage> {
  late Stream<List<drift.TypedResult>> stream;
  TextEditingController searchController = TextEditingController();
  String selectedExercise = "";
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    stream = (db.gymSets.selectOnly(distinct: true)
          ..addColumns([db.gymSets.name, db.gymSets.weight.max()])
          ..groupBy([db.gymSets.name]))
        .watch();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ExerciseState>();
    if (appState.selected?.isNotEmpty == true)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (selectedExercise == appState.selected) return;
        setState(() {
          selectedExercise = appState.selected ?? "";
        });

        if (navigatorKey.currentState!.canPop()) {
          navigatorKey.currentState!.pop();
        }

        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => ViewGraphPage(
              name: appState.selected!,
            ),
          ),
        );
      });

    return NavigatorPopHandler(
      onPop: () {
        if (navigatorKey.currentState!.canPop() == false) return;
        navigatorKey.currentState!.pop();
      },
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => graphsPage(),
          settings: settings,
        ),
      ),
    );
  }

  Scaffold graphsPage() {
    return Scaffold(
      body: material.Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SearchBar(
              hintText: "Search...",
              controller: searchController,
              padding: MaterialStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              onChanged: (_) {
                setState(() {});
              },
              leading: const Icon(Icons.search),
              trailing: searchController.text.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {});
                        },
                      )
                    ]
                  : [
                      PopupMenuButton(
                        icon: const Icon(Icons.more_vert),
                        itemBuilder: (context) => [
                          enterWeight(context),
                          timer(context),
                          downloadCsv(context),
                          uploadCsv(context),
                          deleteAll(context),
                        ],
                      )
                    ],
            ),
          ),
          StreamBuilder<List<drift.TypedResult>>(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              if (snapshot.hasError)
                return ErrorWidget(snapshot.error.toString());
              if (snapshot.data?.isEmpty == true)
                return const ListTile(
                  title: Text("No data yet."),
                  subtitle: Text(
                      "Complete plans for your progress graphs to appear here."),
                );
              final gymSets = snapshot.data!;

              final filteredGymSets = gymSets.where((gymSet) {
                final name = gymSet.read(db.gymSets.name)!.toLowerCase();
                final searchText = searchController.text.toLowerCase();
                return name.contains(searchText);
              }).toList();

              return Expanded(
                child: ListView.builder(
                  itemCount: filteredGymSets.length,
                  itemBuilder: (context, index) {
                    final gymSet = filteredGymSets[index];
                    final name = gymSet.read(db.gymSets.name)!;
                    final weight = gymSet.read(db.gymSets.weight.max())!;
                    return GraphTile(
                      name: name,
                      weight: weight,
                    );
                  },
                ),
              );
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddExercisePage(),
            ),
          );
        },
        tooltip: 'Add exercise',
        child: const Icon(Icons.add),
      ),
    );
  }

  PopupMenuItem<dynamic> timer(BuildContext context) {
    return PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.timer),
        title: const Text('Timer'),
        onTap: () {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TimerPage()),
          );
        },
      ),
    );
  }

  PopupMenuItem<dynamic> enterWeight(BuildContext context) {
    return PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.scale),
        title: const Text('Weight'),
        onTap: () {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EnterWeightPage()),
          );
        },
      ),
    );
  }

  PopupMenuItem<dynamic> deleteAll(BuildContext context) {
    return PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.delete),
        title: const Text('Delete all'),
        onTap: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Confirm Delete'),
                content: const Text(
                    'Are you sure you want to delete all records? This action is not reversible.'),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text('Delete'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await db.delete(db.gymSets).go();
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  PopupMenuItem<dynamic> uploadCsv(BuildContext context) {
    return PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.upload),
        title: const Text('Upload CSV'),
        onTap: () async {
          Navigator.pop(context);
          String csv = await android.invokeMethod('read');
          List<List<dynamic>> rows =
              const CsvToListConverter(eol: "\n").convert(csv);
          if (rows.isEmpty) return;
          try {
            final gymSets = rows.map(
              (row) => GymSetsCompanion(
                name: drift.Value(row[1]),
                reps: drift.Value(row[2]),
                weight: drift.Value(row[3]),
                created: drift.Value(parseDate(row[4])),
                unit: drift.Value(row[5]),
              ),
            );
            await db.batch(
              (batch) => batch.insertAll(db.gymSets, gymSets),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to upload csv.')),
            );
          }
        },
      ),
    );
  }

  PopupMenuItem<dynamic> downloadCsv(BuildContext context) {
    return PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.download),
        title: const Text('Download CSV'),
        onTap: () async {
          Navigator.pop(context);

          final gymSets = await db.gymSets.select().get();
          final List<List<dynamic>> csvData = [
            ['id', 'name', 'reps', 'weight', 'created', 'unit']
          ];
          for (var gymSet in gymSets) {
            csvData.add([
              gymSet.id,
              gymSet.name,
              gymSet.reps,
              gymSet.weight,
              gymSet.created.toIso8601String(),
              gymSet.unit,
            ]);
          }

          if (!await requestNotificationPermission()) return;
          final csv = const ListToCsvConverter(eol: "\n").convert(csvData);
          android.invokeMethod('save', ['gym_sets.csv', csv]);
        },
      ),
    );
  }
}
