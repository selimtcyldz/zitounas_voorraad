import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

const Color kPrimary = Color(0xFF2E7D32);
const Color kAccent = Color(0xFFFFC107);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const AppRoot());
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kPrimary);
    return MaterialApp(
      title: 'Zitounas voorraad',
      theme: ThemeData(colorScheme: scheme, primaryColor: kPrimary, appBarTheme: const AppBarTheme(backgroundColor: kPrimary, foregroundColor: Colors.white)),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData && snap.data != null) {
          return const ProductListPage();
        } else {
          return const LoginPage();
        }
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email, password: _password);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zitounas - Giriş')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset('assets/logo.png', height: 84, fit: BoxFit.contain),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v==null||!v.contains('@')) ? 'Geçerli email' : null,
                      onSaved: (v) => _email = v!.trim(),
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Şifre'),
                      obscureText: true,
                      validator: (v) => (v==null||v.length<6) ? 'En az 6 karakter' : null,
                      onSaved: (v) => _password = v!.trim(),
                    ),
                    const SizedBox(height: 10),
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 6),
                    if (_loading) const CircularProgressIndicator(),
                    if (!_loading) ElevatedButton(onPressed: _submit, child: const Text('Giriş')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});
  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  final _productsRef = FirebaseFirestore.instance.collection('products');

  @override
  void initState() {
    super.initState();
    _trySeed();
  }

  Future<void> _trySeed() async {
    final markerRef = FirebaseFirestore.instance.doc('meta/seed_v1');
    final marker = await markerRef.get();
    if (marker.exists) return;
    final snap = await _productsRef.limit(1).get();
    if (snap.size == 0) {
      final user = FirebaseAuth.instance.currentUser;
      final now = FieldValue.serverTimestamp();
      List<dynamic> decoded = jsonDecode(r"""["abricosen zwart", "amandel natuur", "amandel poeder", "amandel schijf", "amandel wit", "banaan chips", "cachou natuur", "coco poeder", "coco schijf", "fruit mix", "gember", "granola", "granola chokola", "granola mix", "havermout klein", "havervlokken", "hazelnoot", "hazelnoot wit", "hennepzaad", "kiwi schijf", "lijn zaad gebroken", "lijnzaad", "maanzaad", "noten mix", "papaja", "pecanoot", "pistach gepeld", "rozijn appeldiksap", "rozijn sultana", "rozijn zwart", "rozijnen geel jumbo", "sesamzaad", "veenbessen", "vijgen spaans", "zonnebloempit", "abricosen", "amandal gerookt", "ananas blokjes", "ananas gedroogd", "dadels", "dadels zonder pit", "macademia", "pistach", "pruimen", "vijgen turks", "appel schijf", "brazil paranoten", "cachou zout", "chiazaad", "coco blokjes", "mango", "pijnboompit", "pompoenpit", "rozijn geel", "student haver", "walnoot"]""");
      final List<String> items = decoded.cast<String>().toList();
      int written = 0;
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final name in items) {
        final doc = _productsRef.doc();
        batch.set(doc, {
          'name': name,
          'quantity': 0,
          'salePrice': 0.0,
          'createdBy': user?.email ?? user?.uid ?? 'seed',
          'createdAt': now,
          'updatedBy': user?.email ?? user?.uid ?? 'seed',
          'updatedAt': now,
        });
        written++;
        if (written % 400 == 0) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
        }
      }
      await batch.commit();
      await markerRef.set({'done': true, 'at': now, 'count': items.length});
    }
  }

  void _signOut() => FirebaseAuth.instance.signOut();

  String _formatCurrency(num value) {
    final nf = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    return nf.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/logo.png', height: 28),
          const SizedBox(width: 8),
          const Text('Zitounas voorraad')
        ]),
        actions: [ IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)) ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditProductPage(isEdit: false))),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _productsRef.orderBy('name').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('Kayıtlı ürün yok. + ile ürün ekle'));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] ?? '') as String;
              final qty = (data['quantity'] ?? 0) as num;
              final price = (data['salePrice'] ?? 0) as num;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditProductPage(isEdit: true, productId: doc.id, initialData: data))),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 6),
                    Text('Miktar: {qty.toString()}'),
                    Text('Satış Fiyatı: {_formatCurrency(price)}'),
                  ]),
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) async {
                      if (val == 'delete') {
                        await _productsRef.doc(doc.id).delete();
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ürün silindi')));
                      }
                    },
                    itemBuilder: (_) => const [ PopupMenuItem(value: 'delete', child: Text('Sil')) ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AddEditProductPage extends StatefulWidget {
  final bool isEdit;
  final String? productId;
  final Map<String, dynamic>? initialData;
  const AddEditProductPage({super.key, required this.isEdit, this.productId, this.initialData});
  @override
  State<AddEditProductPage> createState() => _AddEditProductPageState();
}

class _AddEditProductPageState extends State<AddEditProductPage> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  int _quantity = 0;
  double _salePrice = 0.0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit && widget.initialData != null) {
      final d = widget.initialData!;
      _name = (d['name'] ?? '') as String;
      _quantity = (d['quantity'] ?? 0) as int;
      _salePrice = ((d['salePrice'] ?? 0) as num).toDouble();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser!;
    final now = FieldValue.serverTimestamp();
    final productsRef = FirebaseFirestore.instance.collection('products');
    try {
      if (widget.isEdit && widget.productId != null) {
        await productsRef.doc(widget.productId).update({
          'name': _name,
          'quantity': _quantity,
          'salePrice': _salePrice,
          'updatedBy': user.email ?? user.uid,
          'updatedAt': now,
        });
      } else {
        await productsRef.add({
          'name': _name,
          'quantity': _quantity,
          'salePrice': _salePrice,
          'createdBy': user.email ?? user.uid,
          'createdAt': now,
          'updatedBy': user.email ?? user.uid,
          'updatedAt': now,
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydetme hatası: ${e.toString()}')));
    } finally {
      setState(() => _loading = false);
    }
  }

  String? _notEmpty(String? v) => (v==null || v.trim().isEmpty) ? 'Bu alan boş olamaz' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Ürünü Düzenle' : 'Yeni Ürün Ekle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(initialValue: _name, decoration: const InputDecoration(labelText: 'Ürün adı'), validator: _notEmpty, onSaved: (v)=>_name=v!.trim()),
                  TextFormField(initialValue: _quantity.toString(), decoration: const InputDecoration(labelText: 'Miktar'), keyboardType: TextInputType.number, validator: (v){ if (v==null||v.isEmpty) return 'Miktar girin'; if (int.tryParse(v)==null) return 'Geçerli sayı'; return null; }, onSaved: (v)=>_quantity=int.parse(v!.trim())),
                  TextFormField(initialValue: _salePrice.toStringAsFixed(2), decoration: const InputDecoration(labelText: 'Satış Fiyatı (örn: 12.50)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v){ if (v==null||v.isEmpty) return 'Fiyat girin'; final t = double.tryParse(v.replaceAll(',', '.')); if (t==null) return 'Geçerli fiyat'; return null; }, onSaved: (v)=>_salePrice=double.parse(v!.replaceAll(',', '.'))),
                  const SizedBox(height:12),
                  if (_loading) const CircularProgressIndicator(),
                  if (!_loading) ElevatedButton(onPressed: _save, child: Text(widget.isEdit ? 'Güncelle' : 'Ekle')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
