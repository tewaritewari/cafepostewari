// models.dart
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

enum PaymentMode { cash, upi, card }

String paymentModeToString(PaymentMode m) {
  switch (m) {
    case PaymentMode.cash:
      return 'Cash';
    case PaymentMode.upi:
      return 'UPI';
    case PaymentMode.card:
      return 'Card';
  }
}

PaymentMode paymentModeFromString(String s) {
  switch (s) {
    case 'Cash':
      return PaymentMode.cash;
    case 'UPI':
      return PaymentMode.upi;
    case 'Card':
      return PaymentMode.card;
    default:
      return PaymentMode.cash;
  }
}

class MenuItem {
  final int? dbId;
  final String id;
  String name;
  double price;
  String category;

  MenuItem({
    this.dbId,
    String? id,
    required this.name,
    required this.price,
    required this.category,
  }) : id = id ?? _uuid.v4();

  Map<String, Object?> toMap() => {
        'dbId': dbId,
        'id': id,
        'name': name,
        'price': price,
        'category': category,
      };

  factory MenuItem.fromMap(Map<String, Object?> map) => MenuItem(
        dbId: map['dbId'] as int?,
        id: map['id'] as String,
        name: map['name'] as String,
        price: (map['price'] as num).toDouble(),
        category: map['category'] as String,
      );
}

class Modifier {
  final String name;
  final double price;

  Modifier({required this.name, required this.price});
}

class CartItem {
  final MenuItem item;
  int qty;
  List<Modifier> modifiers;

  CartItem({
    required this.item,
    this.qty = 1,
    List<Modifier>? modifiers,
  }) : modifiers = modifiers ?? [];

  double get modifierTotal =>
      modifiers.fold(0.0, (sum, m) => sum + m.price) * qty;

  double get lineTotal => item.price * qty + modifierTotal;
}

class Customer {
  final int? dbId;
  final String id;
  String name;
  String phone;
  String? notes;

  Customer({
    this.dbId,
    String? id,
    required this.name,
    required this.phone,
    this.notes,
  }) : id = id ?? _uuid.v4();

  Map<String, Object?> toMap() => {
        'dbId': dbId,
        'id': id,
        'name': name,
        'phone': phone,
        'notes': notes,
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        dbId: map['dbId'] as int?,
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        notes: map['notes'] as String?,
      );
}

class OrderItem {
  final int? dbId;
  final int orderId;
  final String itemName;
  final double unitPrice;
  final int quantity;
  final double modifiersTotal;

  OrderItem({
    this.dbId,
    required this.orderId,
    required this.itemName,
    required this.unitPrice,
    required this.quantity,
    required this.modifiersTotal,
  });

  double get lineTotal => unitPrice * quantity + modifiersTotal;

  Map<String, Object?> toMap() => {
        'dbId': dbId,
        'orderId': orderId,
        'itemName': itemName,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'modifiersTotal': modifiersTotal,
      };

  factory OrderItem.fromMap(Map<String, Object?> map) => OrderItem(
        dbId: map['dbId'] as int?,
        orderId: map['orderId'] as int,
        itemName: map['itemName'] as String,
        unitPrice: (map['unitPrice'] as num).toDouble(),
        quantity: map['quantity'] as int,
        modifiersTotal: (map['modifiersTotal'] as num).toDouble(),
      );

  OrderItem copyWithOrderId(int orderId) => OrderItem(
        dbId: dbId,
        orderId: orderId,
        itemName: itemName,
        unitPrice: unitPrice,
        quantity: quantity,
        modifiersTotal: modifiersTotal,
      );
}

class Order {
  final int? dbId;
  final DateTime createdAt;
  final double subtotal;
  final double tax;
  final double total;
  final PaymentMode paymentMode;
  final double cashReceived;
  final double change;
  final String? customerId;

  Order({
    this.dbId,
    required this.createdAt,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.paymentMode,
    required this.cashReceived,
    required this.change,
    this.customerId,
  });

  Map<String, Object?> toMap() => {
        'dbId': dbId,
        'createdAt': createdAt.toIso8601String(),
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'paymentMode': paymentModeToString(paymentMode),
        'cashReceived': cashReceived,
        'change': change,
        'customerId': customerId,
      };

  factory Order.fromMap(Map<String, Object?> map) => Order(
        dbId: map['dbId'] as int?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        subtotal: (map['subtotal'] as num).toDouble(),
        tax: (map['tax'] as num).toDouble(),
        total: (map['total'] as num).toDouble(),
        paymentMode: paymentModeFromString(map['paymentMode'] as String),
        cashReceived: (map['cashReceived'] as num).toDouble(),
        change: (map['change'] as num).toDouble(),
        customerId: map['customerId'] as String?,
      );
}
