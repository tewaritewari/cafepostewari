// db.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class CafeDatabase {
  static final CafeDatabase instance = CafeDatabase._internal();
  CafeDatabase._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tewari_say_cheese.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE menu (
            dbId INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT UNIQUE,
            name TEXT,
            price REAL,
            category TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE customers (
            dbId INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT UNIQUE,
            name TEXT,
            phone TEXT,
            notes TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE orders (
            dbId INTEGER PRIMARY KEY AUTOINCREMENT,
            createdAt TEXT,
            subtotal REAL,
            tax REAL,
            total REAL,
            paymentMode TEXT,
            cashReceived REAL,
            change REAL,
            customerId TEXT,
            image TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE order_items (
            dbId INTEGER PRIMARY KEY AUTOINCREMENT,
            orderId INTEGER,
            itemName TEXT,
            unitPrice REAL,
            quantity INTEGER,
            modifiersTotal REAL
          );
        ''');
      },
    );
  }

  // MENU
  Future<List<MenuItem>> getMenuItems() async {
    final database = await db;
    final rows = await database.query('menu');
    return rows.map((r) => MenuItem.fromMap(r)).toList();
  }

  Future<void> upsertMenuItem(MenuItem item) async {
    final database = await db;
    await database.insert(
      'menu',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMenuItem(String id) async {
    final database = await db;
    await database.delete('menu', where: 'id = ?', whereArgs: [id]);
  }

  // CUSTOMERS
  Future<List<Customer>> getCustomers() async {
    final database = await db;
    final rows = await database.query('customers');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  Future<void> upsertCustomer(Customer c) async {
    final database = await db;
    await database.insert(
      'customers',
      c.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ORDERS
  Future<int> insertOrder(Order order, List<OrderItem> items) async {
    final database = await db;
    return await database.transaction<int>((txn) async {
      final orderId = await txn.insert('orders', order.toMap());
      for (final item in items) {
        await txn.insert(
          'order_items',
          item.copyWithOrderId(orderId).toMap(),
        );
      }
      return orderId;
    });
  }

  Future<List<Order>> getOrdersForDay(DateTime day) async {
    final database = await db;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final rows = await database.query(
      'orders',
      where: 'createdAt >= ? AND createdAt < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'createdAt DESC',
    );
    return rows.map((r) => Order.fromMap(r)).toList();
  }

  Future<double> totalSalesForDay(DateTime day) async {
    final database = await db;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final rows = await database.rawQuery(
      '''
      SELECT SUM(total) as totalSales
      FROM orders
      WHERE createdAt >= ? AND createdAt < ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    if (rows.isEmpty || rows.first['totalSales'] == null) return 0.0;
    return (rows.first['totalSales'] as num).toDouble();
  }
}
