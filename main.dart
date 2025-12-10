// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'models.dart';
import 'db.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CafePosApp());
}

class CafePosApp extends StatefulWidget {
  const CafePosApp({super.key});

  @override
  State<CafePosApp> createState() => _CafePosAppState();
}

class _CafePosAppState extends State<CafePosApp> {
  int _tabIndex = 0;
  final String _adminPin = '1234'; // change PIN if you want
  List<MenuItem> _menu = [];
  List<Customer> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final db = CafeDatabase.instance;
    final menu = await db.getMenuItems();
    final customers = await db.getCustomers();

    if (menu.isEmpty) {
      final defaults = [
        MenuItem(name: 'Espresso', price: 80, category: 'Coffee'),
        MenuItem(name: 'Caffè Latte', price: 160, category: 'Coffee'),
        MenuItem(name: 'Cappuccino', price: 150, category: 'Coffee'),
        MenuItem(name: 'Cold Brew', price: 170, category: 'Iced'),
        MenuItem(name: 'Butter Croissant', price: 110, category: 'Snacks'),
        MenuItem(name: 'Chocolate Brownie', price: 90, category: 'Snacks'),
        MenuItem(name: 'Grilled Sandwich', price: 160, category: 'Snacks'),
        MenuItem(name: 'Choco Chip Cookie', price: 60, category: 'Snacks'),
      ];
      for (final m in defaults) {
        await db.upsertMenuItem(m);
      }
      _menu = defaults;
    } else {
      _menu = menu;
    }

    _customers = customers;
    if (mounted) setState(() {});
  }

  Future<void> _addOrUpdateMenuItem(MenuItem item) async {
    await CafeDatabase.instance.upsertMenuItem(item);
    final menu = await CafeDatabase.instance.getMenuItems();
    setState(() => _menu = menu);
  }

  Future<void> _deleteMenuItem(String id) async {
    await CafeDatabase.instance.deleteMenuItem(id);
    final menu = await CafeDatabase.instance.getMenuItems();
    setState(() => _menu = menu);
  }

  Future<void> _addCustomer(Customer c) async {
    await CafeDatabase.instance.upsertCustomer(c);
    final customers = await CafeDatabase.instance.getCustomers();
    setState(() => _customers = customers);
  }

  Future<bool> _ensureAdminPin() async {
    String entered = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Admin PIN'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Enter PIN'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                entered = ctrl.text.trim();
                Navigator.of(ctx).pop(true);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (ok != true) return false;
    if (entered != _adminPin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect PIN')),
        );
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      PosScreen(menu: _menu, customers: _customers, onAddCustomer: _addCustomer),
      AdminMenuScreen(menu: _menu, onSave: _addOrUpdateMenuItem, onDelete: _deleteMenuItem),
      const OrderHistoryScreen(),
    ];

    return MaterialApp(
      title: 'TEWARI SAY CHEESE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('TEWARI SAY CHEESE')),
        body: screens[_tabIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (i) async {
            if (i == 1) {
              final ok = await _ensureAdminPin();
              if (!ok) return;
            }
            setState(() => _tabIndex = i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'POS'),
            NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
            NavigationDestination(icon: Icon(Icons.receipt_long), label: 'History'),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------
   POS Screen
   ------------------------------ */
class PosScreen extends StatefulWidget {
  final List<MenuItem> menu;
  final List<Customer> customers;
  final void Function(Customer) onAddCustomer;

  const PosScreen({super.key, required this.menu, required this.customers, required this.onAddCustomer});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final Map<String, CartItem> _cart = {};
  Customer? _selectedCustomer;
  double _cashReceived = 0.0;
  PaymentMode _paymentMode = PaymentMode.cash;

  ReceiptController? _receiptController;

  // modifiers
  final List<Modifier> _availableModifiers = [
    Modifier(name: 'Extra shot', price: 30),
    Modifier(name: 'Soy milk', price: 20),
    Modifier(name: 'Add cheese', price: 25),
  ];
  Modifier? _selectedModifier;

  static const double taxRate = 0.05;

  double get _subtotal => _cart.values.fold(0.0, (s, c) => s + c.lineTotal);
  double get _tax => _subtotal * taxRate;
  double get _total => _subtotal + _tax;
  double get _change => (_cashReceived - _total).clamp(0.0, double.infinity);

  void _addToCart(MenuItem item) {
    setState(() {
      final existing = _cart[item.id];
      if (existing == null) {
        _cart[item.id] = CartItem(item: item, qty: 1, modifiers: _selectedModifier == null ? [] : [_selectedModifier!]);
      } else {
        existing.qty += 1;
        if (_selectedModifier != null) existing.modifiers.add(_selectedModifier!);
      }
    });
  }

  void _changeQty(String itemId, int delta) {
    setState(() {
      final ci = _cart[itemId];
      if (ci == null) return;
      ci.qty += delta;
      if (ci.qty <= 0) _cart.remove(itemId);
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _cashReceived = 0.0;
      _paymentMode = PaymentMode.cash;
      _selectedCustomer = null;
    });
  }

  Future<void> _chooseCustomer() async {
    final result = await showModalBottomSheet<Customer?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => CustomerSheet(existingCustomers: widget.customers),
    );
    if (result != null) {
      widget.onAddCustomer(result);
      setState(() => _selectedCustomer = result);
    }
  }

  Future<void> _printAndSaveOrder() async {
    if (_cart.isEmpty) return;

    final subtotal = _subtotal;
    final tax = _tax;
    final total = _total;

    if (_paymentMode == PaymentMode.cash && _cashReceived < total) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cash received is less than total')));
      return;
    }

    final change = _change;

    final order = Order(
      createdAt: DateTime.now(),
      subtotal: subtotal,
      tax: tax,
      total: total,
      paymentMode: _paymentMode,
      cashReceived: _cashReceived,
      change: change,
      customerId: _selectedCustomer?.id,
    );

    final items = _cart.values.map((ci) {
      final modsTotal = ci.modifiers.fold(0.0, (s, m) => s + m.price) * ci.qty;
      return OrderItem(orderId: 0, itemName: ci.item.name, unitPrice: ci.item.price, quantity: ci.qty, modifiersTotal: modsTotal);
    }).toList();

    // Save to DB
    await CafeDatabase.instance.insertOrder(order, items);

    // Build receipt widget and call flutter_bluetooth_printer flow
    buildReceipt();

    try {
      final device = await FlutterBluetoothPrinter.selectDevice(context);
      if (device != null) {
        await _receiptController?.print(address: device.address);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }

    _clearCart();
  }

  void buildReceipt() {
    // We use the Receipt widget (offstage) to render and print.
    // _receiptController will be set when Receipt builds.
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<MenuItem>>{};
    for (final m in widget.menu) {
      byCategory.putIfAbsent(m.category, () => []).add(m);
    }

    return Column(
      children: [
        // header row
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_selectedCustomer?.name ?? 'No customer selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_selectedCustomer?.phone.isNotEmpty == true ? _selectedCustomer!.phone : 'Tap to add / select customer'),
                  leading: const Icon(Icons.person),
                  onTap: _chooseCustomer,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total'),
                  Text('?${_total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: Row(
            children: [
              // Left: Menu + modifier selector
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          const Text('Modifier for next item: '),
                          const SizedBox(width: 8),
                          DropdownButton<Modifier?>(
                            value: _selectedModifier,
                            hint: const Text('None'),
                            onChanged: (m) => setState(() => _selectedModifier = m),
                            items: [
                              const DropdownMenuItem<Modifier?>(value: null, child: Text('None')),
                              ..._availableModifiers.map((m) => DropdownMenuItem(value: m, child: Text('${m.name} (+?${m.price.toStringAsFixed(0)})'))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: byCategory.entries.map((entry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
                                child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              ),
                              ...entry.value.map((item) => Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: ListTile(
                                  title: Text(item.name),
                                  subtitle: Text('?${item.price.toStringAsFixed(2)}'),
                                  trailing: const Icon(Icons.add),
                                  onTap: () => _addToCart(item),
                                ),
                              )).toList(),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Right: Cart
              Expanded(
                flex: 2,
                child: Card(
                  margin: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      const ListTile(title: Text('Cart')),
                      const Divider(height: 0),
                      Expanded(
                        child: _cart.isEmpty
                            ? const Center(child: Text('No items in cart'))
                            : ListView(
                                children: _cart.values.map((ci) {
                                  return ListTile(
                                    title: Text(ci.item.name),
                                    subtitle: Text('${ci.qty} × ?${ci.item.price.toStringAsFixed(2)}' +
                                        (ci.modifiers.isNotEmpty ? ' • +${ci.modifiers.map((m) => m.name).join(', ')}' : '')),
                                    trailing: SizedBox(
                                      width: 110,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(icon: const Icon(Icons.remove), onPressed: () => _changeQty(ci.item.id, -1)),
                                          Text(ci.qty.toString()),
                                          IconButton(icon: const Icon(Icons.add), onPressed: () => _changeQty(ci.item.id, 1)),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      const Divider(height: 0),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            _summaryRow('Subtotal', _subtotal),
                            _summaryRow('Tax (${(taxRate * 100).toStringAsFixed(0)}%)', _tax),
                            _summaryRow('Total', _total, isBold: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Payment row
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cash received', prefixText: '?'),
                  onChanged: (v) => setState(() => _cashReceived = double.tryParse(v) ?? 0.0),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<PaymentMode>(
                value: _paymentMode,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _paymentMode = val);
                },
                items: PaymentMode.values.map((pm) {
                  return DropdownMenuItem(value: pm, child: Text(paymentModeToString(pm)));
                }).toList(),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Change'),
                  Text('?${_change.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),

        // action buttons
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
          child: Row(
            children: [
              ElevatedButton.icon(onPressed: _cart.isEmpty ? null : _clearCart, icon: const Icon(Icons.clear_all), label: const Text('Clear cart')),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: _cart.isEmpty ? null : _printAndSaveOrder, icon: const Icon(Icons.print), label: const Text('Print & Save')),
            ],
          ),
        ),

        // Offstage receipt widget for the Bluetooth printer library
        Offstage(
          offstage: true,
          child: Receipt(
            builder: (context) => _buildReceiptWidget(),
            onInitialized: (controller) => _receiptController = controller,
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: Text('TEWARI SAY CHEESE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        const Center(child: Text('HOWRAH', style: TextStyle(fontSize: 12))),
        const SizedBox(height: 6),
        if (_selectedCustomer != null) ...[
          Text('Customer: ${_selectedCustomer!.name}'),
          Text('Phone: ${_selectedCustomer!.phone}'),
          const SizedBox(height: 6),
        ],
        const Divider(),
        ..._cart.values.map((ci) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('${ci.qty} x ${ci.item.name}')),
              Text('?${ci.lineTotal.toStringAsFixed(2)}'),
            ],
          );
        }),
        const Divider(),
        _summaryRow('Subtotal', _subtotal),
        _summaryRow('Tax', _tax),
        _summaryRow('Total', _total, isBold: true),
        const SizedBox(height: 6),
        _summaryRow('Cash', _cashReceived),
        _summaryRow('Change', _change),
        const SizedBox(height: 8),
        const Center(child: Text('Thank you! Visit again')),
      ],
    );
  }

  Widget _summaryRow(String label, double value, {bool isBold = false}) {
    final style = TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text('?${value.toStringAsFixed(2)}', style: style)]),
    );
  }
}

/* ------------------------------
   CustomerSheet
   ------------------------------ */
class CustomerSheet extends StatefulWidget {
  final List<Customer> existingCustomers;
  const CustomerSheet({super.key, required this.existingCustomers});

  @override
  State<CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<CustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Customer? _selectedExisting;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final customer = Customer(name: _nameCtrl.text.trim(), phone: _phoneCtrl.text.trim(), notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    Navigator.of(context).pop(customer);
  }

  void _fillFromExisting(Customer c) {
    setState(() {
      _selectedExisting = c;
      _nameCtrl.text = c.name;
      _phoneCtrl.text = c.phone;
      _notesCtrl.text = c.notes ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Customer details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (widget.existingCustomers.isNotEmpty) ...[
              Align(alignment: Alignment.centerLeft, child: Text('Select existing:', style: Theme.of(context).textTheme.labelLarge)),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.existingCustomers.length,
                  itemBuilder: (ctx, i) {
                    final c = widget.existingCustomers[i];
                    final selected = _selectedExisting?.id == c.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(label: Text('${c.name} (${c.phone})'), selected: selected, onSelected: (_) => _fillFromExisting(c)),
                    );
                  },
                ),
              ),
              const Divider(),
            ],
            Form(
              key: _formKey,
              child: Column(children: [
                TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: ElevatedButton(onPressed: _submit, child: const Text('Save & use')))]),
          ]),
        ),
      ),
    );
  }
}

/* ------------------------------
   AdminMenuScreen
   ------------------------------ */
class AdminMenuScreen extends StatelessWidget {
  final List<MenuItem> menu;
  final void Function(MenuItem) onSave;
  final void Function(String) onDelete;

  const AdminMenuScreen({super.key, required this.menu, required this.onSave, required this.onDelete});

  void _openEditor(BuildContext context, {MenuItem? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    final categoryCtrl = TextEditingController(text: existing?.category ?? 'Coffee');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add menu item' : 'Edit menu item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
        ]),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
          ElevatedButton(child: const Text('Save'), onPressed: () {
            final name = nameCtrl.text.trim();
            final price = double.tryParse(priceCtrl.text) ?? 0;
            final category = categoryCtrl.text.trim().isEmpty ? 'Other' : categoryCtrl.text.trim();
            if (name.isEmpty || price <= 0) return;
            final id = existing?.id;
            onSave(MenuItem(id: id, name: name, price: price, category: category));
            Navigator.of(ctx).pop();
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...menu]..sort((a, b) => a.category.toLowerCase().compareTo(b.category.toLowerCase()));
    return Column(children: [
      ListTile(title: const Text('Menu editor'), subtitle: const Text('Add, edit, delete items'), trailing: ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('New item'), onPressed: () => _openEditor(context))),
      const Divider(height: 0),
      Expanded(child: ListView.builder(itemCount: sorted.length, itemBuilder: (ctx, i) {
        final m = sorted[i];
        return ListTile(
          title: Text(m.name),
          subtitle: Text('${m.category} • ?${m.price.toStringAsFixed(2)}'),
          trailing: Wrap(spacing: 4, children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: () => _openEditor(context, existing: m)),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => onDelete(m.id)),
          ]),
        );
      })),
    ]);
  }
}

/* ------------------------------
   OrderHistoryScreen
   ------------------------------ */
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  DateTime _selectedDay = DateTime.now();
  List<Order> _orders = [];
  double _totalSales = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  Future<void> _loadDay() async {
    final db = CafeDatabase.instance;
    final orders = await db.getOrdersForDay(_selectedDay);
    final total = await db.totalSalesForDay(_selectedDay);
    if (mounted) setState(() {
      _orders = orders;
      _totalSales = total;
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(context: context, initialDate: _selectedDay, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (picked == null) return;
    _selectedDay = picked;
    await _loadDay();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(title: const Text('Order history'), subtitle: Text('Date: ${_selectedDay.toLocal().toString().split(' ').first}'), trailing: ElevatedButton.icon(onPressed: _pickDay, icon: const Icon(Icons.calendar_month), label: const Text('Change date'))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Orders: ${_orders.length}'), Text('Total: ?${_totalSales.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))])),
      const Divider(),
      Expanded(child: _orders.isEmpty ? const Center(child: Text('No orders for this date')) : ListView.builder(itemCount: _orders.length, itemBuilder: (ctx, i) {
        final o = _orders[i];
        return ListTile(leading: const Icon(Icons.receipt_long), title: Text('?${o.total.toStringAsFixed(2)} • ${paymentModeToString(o.paymentMode)}'), subtitle: Text('${o.createdAt.toLocal().toString().substring(11, 16)}'));
      })),
    ]);
  }
}
