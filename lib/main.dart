import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String supabaseUrl = 'https://doxcesroovpoghpjgfxf.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRveGNlc3Jvb3Zwb2docGpnZnhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMwMjE2NTksImV4cCI6MjA3ODU5NzY1OX0.o49mAaagzBrb0V0l-7CbIlKUJkgQIn2kaHRxJfQTeaE';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Congélateur",
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const StockPage(),
    );
  }
}

// -----------------------------------------------------------
// SERVICE : Durées sauvegardées localement
// -----------------------------------------------------------
class DurationService {
  static const String key = "durees_congelation";

  static Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);

    if (raw == null) {
      return {
        'Boeuf': 6,
        'Porc': 4,
        'Volaille': 6,
        'Poisson': 3,
        'Légumes': 12,
        'Fruit': 12,
        'Plat préparé': 3,
        'Dessert': 12,
        'Autre': 6,
      };
    }

    final entries = raw.substring(1, raw.length - 1).split(',');
    final map = <String, int>{};

    for (var e in entries) {
      final parts = e.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim();
        final value = int.tryParse(parts[1].trim()) ?? 6;
        map[key] = value;
      }
    }

    return map;
  }

  static Future<void> save(Map<String, int> m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, m.toString());
  }
}

// -----------------------------------------------------------
// PAGE PRINCIPALE
// -----------------------------------------------------------
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final SupabaseClient client = Supabase.instance.client;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];

  bool _loading = true;
  String _search = "";
  String _filterType = "Tous";
  bool _sortByExpiration = true;

  final List<String> _types = [
    "Tous",
    'Boeuf',
    'Porc',
    'Volaille',
    'Poisson',
    'Légumes',
    'Fruit',
    'Plat préparé',
    'Dessert',
    'Autre'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _listenRealtime();
  }

  Future<void> _load() async {
    final data = await client
        .from('aliments')
        .select()
        .order('date_peremption', ascending: true);

    setState(() {
      _items = List<Map<String, dynamic>>.from(data);
      _applyFilters();
      _loading = false;
    });
  }

  void _listenRealtime() {
    client.channel('realtime:aliments')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'aliments',
        callback: (_) => _load(),
      ).subscribe();
  }

  void _applyFilters() {
    List<Map<String, dynamic>> list = List.from(_items);

    if (_filterType != "Tous") {
      list = list.where((e) => e['type'] == _filterType).toList();
    }

    if (_search.isNotEmpty) {
      list = list.where((e) => (e['nom'] as String)
          .toLowerCase()
          .contains(_search.toLowerCase())).toList();
    }

    if (_sortByExpiration) {
      list.sort((a, b) =>
          a['date_peremption'].compareTo(b['date_peremption']));
    }

    _filtered = list;
  }

  String _fmt(String iso) {
    final d = DateTime.parse(iso);
    return "${d.day}/${d.month}/${d.year}";
  }

  Future<void> _updateQty(int id, int qty, int delta) async {
    final newQty = qty + delta;
    if (newQty <= 0) {
      await client.from('aliments').delete().eq('id', id);
    } else {
      await client.from('aliments').update({'quantite': newQty}).eq('id', id);
    }
    _load();
  }

  Future<void> _delete(int id) async {
    await client.from("aliments").delete().eq('id', id);
    _load();
  }

  Color typeColor(String t) {
    switch (t) {
      case "Boeuf":
        return Colors.red.shade300;
      case "Porc":
        return Colors.pink.shade300;
      case "Volaille":
        return Colors.orange.shade300;
      case "Poisson":
        return Colors.blue.shade300;
      case "Légumes":
        return Colors.green.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("❄️ Congélateur"),
        backgroundColor: Colors.blue.shade500,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 28),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ParametresPage()));
            },
          )
        ],
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue.shade500,
        child: const Icon(Icons.add, size: 45),
        onPressed: () {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AddItemPage()));
        },
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _filters(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: _filtered.map((item) {
                      return _itemCard(item);
                    }).toList(),
                  ),
                )
              ],
            ),
    );
  }

  // ------------------------------------------------------
  // DESIGN CARTE ALIMENT
  // ------------------------------------------------------
  Widget _itemCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [Colors.white, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne nom + quantité + poubelle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item['nom'],
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),

              // BOUTONS quantité
              Row(
                children: [
                  // -
                  _roundBtn(Icons.remove, () {
                    _updateQty(item['id'], item['quantite'], -1);
                  }),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      "${item['quantite']}",
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),

                  // +
                  _roundBtn(Icons.add, () {
                    _updateQty(item['id'], item['quantite'], 1);
                  }),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // TYPE
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: typeColor(item['type']),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item['type'],
              style:
                  const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),

          const SizedBox(height: 14),

          // DATES
          Text("❄️ Congelé : ${_fmt(item['date_congelation'])}",
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text("⏳ Péremption : ${_fmt(item['date_peremption'])}",
              style: const TextStyle(fontSize: 18)),

          const SizedBox(height: 12),

          // SUPPRIMER bien aligné sans décaler le texte
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 28),
              onPressed: () => _delete(item['id']),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.blue.shade900),
        onPressed: onTap,
      ),
    );
  }

  // ------------------------------------------------------
  // FILTRES
  // ------------------------------------------------------
  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Recherche
          TextField(
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: "Rechercher un aliment",
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onChanged: (v) {
              setState(() {
                _search = v;
                _applyFilters();
              });
            },
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField(
                  value: _filterType,
                  items: _types
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _filterType = v!;
                      _applyFilters();
                    });
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 16),
                ),
                onPressed: () {
                  setState(() {
                    _sortByExpiration = !_sortByExpiration;
                    _applyFilters();
                  });
                },
                child: Text(
                    _sortByExpiration ? "Trier par date" : "Trier normal"),
              ),
            ],
          )
        ],
      ),
    );
  }
}

// -----------------------------------------------------------
// PAGE : AJOUT D'UN ALIMENT
// -----------------------------------------------------------
class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final SupabaseClient client = Supabase.instance.client;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _qty = TextEditingController(text: "1");
  DateTime? _date;

  String _type = 'Boeuf';
  Map<String, int> durees = {};

  @override
  void initState() {
    super.initState();
    DurationService.load().then((d) {
      setState(() => durees = d);
    });
  }

  Future<void> _addItem() async {
    if (_name.text.isEmpty || _date == null) return;

    final d = _date!;
    final cong =
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final months = durees[_type]!;
    final per = DateTime(d.year, d.month + months, d.day);
    final perIso =
        "${per.year}-${per.month.toString().padLeft(2, '0')}-${per.day.toString().padLeft(2, '0')}";

    await client.from("aliments").insert({
      'nom': _name.text,
      'type': _type,
      'date_congelation': cong,
      'date_peremption': perIso,
      'quantite': int.parse(_qty.text)
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (durees.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajouter un aliment"),
        backgroundColor: Colors.blue.shade500,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: "Nom",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          DropdownButtonFormField(
            value: _type,
            items: durees.keys
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
            decoration: const InputDecoration(
                labelText: "Type", border: OutlineInputBorder()),
          ),

          const SizedBox(height: 16),

          OutlinedButton(
            onPressed: () async {
              final pick = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2010),
                lastDate: DateTime(2100),
              );
              if (pick != null) setState(() => _date = pick);
            },
            child: Text(_date == null
                ? "Choisir la date de congélation"
                : "Congelé le : ${_date!.day}/${_date!.month}/${_date!.year}"),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: "Quantité", border: OutlineInputBorder()),
          ),

          const SizedBox(height: 22),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade500,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 30)),
            onPressed: _addItem,
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------
// PAGE : PARAMÈTRES
// -----------------------------------------------------------
class ParametresPage extends StatefulWidget {
  const ParametresPage({super.key});

  @override
  State<ParametresPage> createState() => _ParametresPageState();
}

class _ParametresPageState extends State<ParametresPage> {
  Map<String, int> durees = {};

  @override
  void initState() {
    super.initState();
    DurationService.load().then((d) {
      setState(() => durees = d);
    });
  }

  Future<void> _save() async {
    await DurationService.save(durees);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (durees.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("⚙️ Paramètres"),
        backgroundColor: Colors.blue.shade500,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: durees.entries.map((e) {
          return Card(
            child: ListTile(
              title: Text(e.key),
              trailing: SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: e.value.toString(),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      durees[e.key] = int.tryParse(v) ?? e.value,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
