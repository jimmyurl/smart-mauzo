import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'barcode_scan_page.dart';
import '../models/product.dart';
import '../models/product_unit.dart';
import '../models/order.dart';
import '../models/sale.dart';
import '../services/credit_service.dart';
import '../services/offline_store.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../widgets/customer_picker.dart';
import '../widgets/credit_terms_dialog.dart';
import '../widgets/mobile_money_sheet.dart';
import '../widgets/pending_sync_banner.dart';
import '../widgets/receipt_sheet.dart';
import '../utils/category_utils.dart';
import '../utils/money.dart';
import '../utils/payment_style.dart';
import '../widgets/category_chips.dart';
import 'pesapal_checkout_screen.dart';
import '../services/app_language.dart';

/// One line in the cart: a product in one unit (null = the base unit).
class _CartLine {
  Product product;
  ProductUnit? unit;
  int quantity; // how many of [unit]
  _CartLine(this.product, this.unit, this.quantity);
  int get factor => unit?.factor ?? 1;

  /// Quantity in base units, which is how stock is counted.
  int get baseQty => quantity * factor;
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Product> _products = [];
  List<Product> _results = [];
  final Map<String, _CartLine> _cart = {}; // keyed by product id + unit id
  String _level = 'retail'; // price level for the whole sale
  bool _loading = true;
  bool _saving = false;

  // A credit sale that may have reached the server without us hearing back is
  // retried with the same receipt id, so it can never be recorded twice.
  String? _creditKey;
  String? _creditReceiptId;
  DateTime? _creditSoldAt;
  bool _keepScanning = true;
  bool _usingCache = false; // product list comes from the phone, not the server
  bool _fetching = false;

  String _lineKey(Product p, ProductUnit? u) => '${p.id}|${u?.id ?? ''}';

  /// Price of one [l.unit] at the chosen level (same rules as the server).
  double _unitPrice(_CartLine l) => l.product.priceFor(_level, unit: l.unit);
  double _lineTotal(_CartLine l) => ((_unitPrice(l) * l.quantity) * 100).round() / 100;

  double get _total => _cart.values.fold(0.0, (sum, l) => sum + _lineTotal(l));
  int get _itemCount => _cart.values.fold(0, (sum, l) => sum + l.quantity);

  /// Base units of [p] in the cart, over all its lines.
  int _baseInCart(Product p) => _cart.values
      .where((l) => l.product.id == p.id)
      .fold(0, (sum, l) => sum + l.baseQty);

  /// Does any product have a wholesale / special price? Then the level choice shows.
  bool get _hasLevels => _products.any((p) =>
      p.priceWholesale != null ||
      p.priceSpecial != null ||
      p.units.any((u) => u.priceWholesale != null || u.priceSpecial != null));

  /// Card / online payments only know retail prices of single items.
  bool get _retailOnly => _level == 'retail' && _cart.values.every((l) => l.unit == null);

  /// The cart as the server wants it. Quantities are in the unit sold.
  List<Map<String, dynamic>> _cartItems() => [
        for (final l in _cart.values)
          {
            'product_id': l.product.id,
            'quantity': l.quantity,
            if (l.unit != null) 'unit_id': l.unit!.id,
            if (_level != 'retail') 'level': _level,
          }
      ];

  String _baseUnitName(Product p) => p.baseUnit ?? tr('piece');
  String _unitLabel(_CartLine l) => l.unit?.name ?? _baseUnitName(l.product);
  String _priceNote(_CartLine l) => l.product.units.isEmpty
      ? '${tzs(_unitPrice(l))} each'
      : '${tzs(_unitPrice(l))} / ${_unitLabel(l)}';

  /// Switches a cart line to another unit of the same product (keeps the quantity).
  void _setUnit(_CartLine line, String unitId) {
    final p = line.product;
    ProductUnit? target;
    if (unitId.isNotEmpty) {
      for (final u in p.units) {
        if (u.id == unitId) target = u;
      }
    }
    if (target?.id == line.unit?.id) return;
    final existing = _cart[_lineKey(p, target)];
    final merged = line.quantity + (existing?.quantity ?? 0);
    final newBase = _baseInCart(p) -
        line.baseQty -
        (existing?.baseQty ?? 0) +
        merged * (target?.factor ?? 1);
    if (newBase > p.stockQuantity) {
      _showMessage('Only ${p.stockQuantity} of ${p.title} in stock');
      return;
    }
    setState(() {
      _cart.remove(_lineKey(p, line.unit));
      if (existing != null) {
        existing.quantity = merged;
      } else {
        _cart[_lineKey(p, target)] = _CartLine(p, target, line.quantity);
      }
    });
  }

  Widget _unitMenu(_CartLine l) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: PopupMenuButton<String>(
          enabled: !_saving,
          onSelected: (v) => _setUnit(l, v),
          itemBuilder: (_) => [
            PopupMenuItem<String>(value: '', child: Text(_baseUnitName(l.product))),
            for (final u in l.product.units)
              PopupMenuItem<String>(
                value: u.id,
                child: Text('${u.name}  (${u.factor} ${_baseUnitName(l.product)})'),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.only(left: 10, right: 2, top: 3, bottom: 3),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_unitLabel(l),
                    style: TextStyle(
                        fontSize: 12, color: Colors.blue[900], fontWeight: FontWeight.w600)),
                Icon(Icons.arrow_drop_down, size: 18, color: Colors.blue[900]),
              ],
            ),
          ),
        ),
      );

  Widget _levelBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(
          children: [
            Text('${tr('Prices')}:  ',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final lv in kPriceLevels)
                    ChoiceChip(
                      label: Text(tr(priceLevelLabel(lv))),
                      selected: _level == lv,
                      visualDensity: VisualDensity.compact,
                      onSelected: _saving ? null : (_) => setState(() => _level = lv),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  void initState() {
    super.initState();
    SyncService().addListener(_onSyncChanged);
    _fetchProducts();
  }

  /// Connection or queue changed: refresh the buttons, and when the connection is
  /// back reload the real product list.
  void _onSyncChanged() {
    if (!mounted) return;
    setState(() {});
    if (_usingCache && SyncService().online && !_fetching) _fetchProducts();
  }

  @override
  void dispose() {
    SyncService().removeListener(_onSyncChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _showMessage(String text, {bool success = false, Order? receipt}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: success ? Colors.green : null,
          duration: Duration(seconds: receipt == null ? 2 : 8),
          action: receipt == null
              ? null
              : SnackBarAction(
                  label: 'RECEIPT',
                  textColor: Colors.white,
                  onPressed: () => showReceiptSheet(context, receipt),
                ),
        ),
      );
  }

  /// The cart as an Order, so a receipt can be made after the cart is cleared.
  Order _cartAsOrder(String receiptId, DateTime soldAt, int? orderNo,
      {String paymentMethod = 'cash',
      String? payProvider,
      String? payRef,
      double paidNow = 0}) {
    final uid = SyncService().userId;
    var i = 0;
    return Order([
      for (final l in _cart.values)
        Sale(
          id: '$receiptId-${i++}',
          productId: l.product.id,
          productTitle: l.product.title,
          quantity: l.baseQty,
          total: _lineTotal(l),
          unitName: l.unit?.name,
          unitFactor: l.factor,
          priceLevel: _level,
          timestamp: soldAt,
          soldBy: uid,
          orderNo: orderNo,
          paymentMethod: paymentMethod,
          payProvider: payProvider,
          payRef: payRef,
        ),
    ], paidNow: paidNow);
  }

  Future<void> _fetchProducts() async {
    if (_fetching) return;
    _fetching = true;
    List<Product>? products;
    var fromCache = false;
    Object? error;
    try {
      products = await _supabaseService.getProducts().timeout(const Duration(seconds: 8));
    } catch (e) {
      error = e;
      // No connection (or a very slow one): use the last list saved on the phone.
      products = await OfflineStore().loadProducts();
      fromCache = products != null;
    } finally {
      _fetching = false;
    }
    if (!mounted) return;

    if (products == null) {
      setState(() => _loading = false);
      _showMessage('Error fetching products: $error');
      return;
    }

    // Sales still waiting to sync already left the shelf: show the lower stock.
    final list = SyncService().applyPending(products);
    setState(() {
      _products = list;
      _usingCache = fromCache;
      _loading = false;
      // Re-bind cart lines to fresh product data (stock may have changed).
      final byId = {for (final p in list) p.id: p};
      _cart.removeWhere((k, l) {
        final fresh = byId[l.product.id];
        return fresh == null ||
            (l.unit != null && !fresh.units.any((u) => u.id == l.unit!.id));
      });
      _cart.forEach((k, line) {
        final fresh = byId[line.product.id]!;
        line.product = fresh;
        if (line.unit != null) {
          line.unit = fresh.units.firstWhere((u) => u.id == line.unit!.id);
        }
      });
      if (!_hasLevels) _level = 'retail';
    });
  }

  // ---------------------------------------------------------------- cart

  /// Adds [qty] of [p] (in [unit], or the base unit) to the cart. Returns false (with
  /// a message) if stock is not enough. Stock is always counted in base units.
  bool _addToCart(Product p, {int qty = 1, ProductUnit? unit}) {
    final key = _lineKey(p, unit);
    final line = _cart[key];
    final wantedBase = _baseInCart(p) + qty * (unit?.factor ?? 1);
    if (wantedBase > p.stockQuantity) {
      _showMessage(p.stockQuantity <= 0
          ? '${p.title} is out of stock'
          : 'Only ${p.stockQuantity} of ${p.title} in stock');
      return false;
    }
    setState(() {
      if (line == null) {
        _cart[key] = _CartLine(p, unit, qty);
      } else {
        line.quantity += qty;
      }
    });
    return true;
  }

  void _changeQty(_CartLine line, int delta) {
    final q = line.quantity + delta;
    if (q <= 0) {
      setState(() => _cart.remove(_lineKey(line.product, line.unit)));
      return;
    }
    if (_baseInCart(line.product) - line.baseQty + q * line.factor >
        line.product.stockQuantity) {
      _showMessage('Only ${line.product.stockQuantity} of ${line.product.title} in stock');
      return;
    }
    setState(() => line.quantity = q);
  }

  Future<void> _editQty(_CartLine line) async {
    final controller = TextEditingController(text: line.quantity.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(line.product.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('Quantity')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, int.tryParse(controller.text)),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result <= 0) {
      setState(() => _cart.remove(_lineKey(line.product, line.unit)));
    } else if (_baseInCart(line.product) - line.baseQty + result * line.factor >
        line.product.stockQuantity) {
      _showMessage('Only ${line.product.stockQuantity} of ${line.product.title} in stock');
    } else {
      setState(() => line.quantity = result);
    }
  }

  Future<void> _clearCart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Clear all items?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('No'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Yes'))),
        ],
      ),
    );
    if (ok == true) setState(_cart.clear);
  }

  // -------------------------------------------------------------- search

  void _onSearchChanged(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _results = q.isEmpty
          ? []
          : (_products
              .where((p) => p.title.toLowerCase().contains(q) || p.barcode.contains(q))
              .toList()
            ..sort((a, b) {
              final as = a.title.toLowerCase().startsWith(q) ? 0 : 1;
              final bs = b.title.toLowerCase().startsWith(q) ? 0 : 1;
              return as != bs ? as.compareTo(bs) : a.title.compareTo(b.title);
            }));
    });
  }

  void _clearSearch({bool refocus = true}) {
    _searchController.clear();
    setState(() => _results = []);
    if (refocus) _searchFocus.requestFocus();
  }

  /// Enter key: this is what USB / Bluetooth barcode scanners send after the code.
  void _onSearchSubmitted(String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    final exact = _products.where((p) => p.barcode.isNotEmpty && p.barcode == code);
    if (exact.isNotEmpty) {
      _addToCart(exact.first);
      _clearSearch();
    } else if (_results.length == 1) {
      _addToCart(_results.first);
      _clearSearch();
    } else if (_results.isEmpty) {
      _showMessage('No product found for "$code"');
    }
  }

  // ---------------------------------------------------------------- scan

  Future<void> _scan() async {
    do {
      final code = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
      );
      if (!mounted || code == null || code.trim().isEmpty) return;
      final trimmed = code.trim();
      final matches = _products.where((p) => p.barcode.trim() == trimmed);
      if (matches.isEmpty) {
        _showMessage('No product found for barcode $trimmed');
      } else if (_addToCart(matches.first)) {
        _showMessage('${matches.first.title} added', success: true);
      }
    } while (_keepScanning);
  }

  // -------------------------------------------------------------- browse

  Future<void> _openBrowse() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BrowseSheet(
        products: _products,
        qtyInCart: _baseInCart,
        onAdd: (p) => _addToCart(p),
      ),
    );
  }

  // ------------------------------------------------------------ payment

  bool _validateCart() {
    if (_cart.isEmpty) {
      _showMessage(tr('Add at least one item first'));
      return false;
    }
    for (final line in _cart.values) {
      if (_baseInCart(line.product) > line.product.stockQuantity) {
        _showMessage('Only ${line.product.stockQuantity} of ${line.product.title} in stock');
        return false;
      }
    }
    return true;
  }

  /// Cash: the whole cart is saved in one database transaction (all lines or none).
  /// With no connection the sale is kept on the phone and sent automatically later.
  Future<void> _cashSale() => _directSale();

  /// Mobile money paid straight to the shop's own number (no gateway). Works like
  /// a cash sale, including offline, but remembers the network and reference.
  Future<void> _lipaSale() async {
    if (!_validateCart()) return;
    final info = await askMobileMoney(context, total: _total);
    if (info == null || !mounted) return; // cancelled
    await _directSale(method: 'lipa', provider: info.provider, ref: info.reference);
  }

  /// Saves the cart as a sale that is paid at once ([method] 'cash' or 'lipa').
  Future<void> _directSale({String method = 'cash', String? provider, String? ref}) async {
    if (!_validateCart()) return;
    setState(() => _saving = true);

    final items = _cartItems();
    final receiptId = const Uuid().v4(); // lets the server ignore a repeated send
    final soldAt = DateTime.now();
    final total = _total;

    final result = await _supabaseService.submitCartSale(
      items: items,
      receiptId: receiptId,
      soldAt: soldAt,
      paymentMethod: method,
      payProvider: provider,
      payRef: ref,
    );
    if (!mounted) return;

    if (result.outcome == SaleOutcome.network) {
      final uid = SyncService().userId;
      final saved = uid != null &&
          await SyncService().enqueue(PendingSale(
            receiptId: receiptId,
            userId: uid,
            items: items,
            total: total,
            soldAt: soldAt,
            paymentMethod: method,
            payProvider: provider,
            payRef: ref,
          ));
      if (!mounted) return;
      if (!saved) {
        // Could not even save it on the phone: keep the cart so nothing is lost.
        setState(() => _saving = false);
        _showMessage(tr('Could not save the sale. Check your connection and try again.'));
        return;
      }
      final offlineReceipt = _cartAsOrder(receiptId, soldAt, null,
          paymentMethod: method, payProvider: provider, payRef: ref);
      setState(() {
        _saving = false;
        // Show the lower stock straight away (it is applied again on every reload).
        for (final l in _cart.values) {
          l.product.stockQuantity = math.max(0, l.product.stockQuantity - l.quantity);
        }
        _cart.clear();
      });
      _showMessage(tr('No connection: sale saved on this phone and will sync automatically'),
          success: true, receipt: offlineReceipt);
      return;
    }

    setState(() => _saving = false);
    if (result.outcome == SaleOutcome.saved) {
      final n = result.orderNo;
      final receipt = _cartAsOrder(receiptId, soldAt, n,
          paymentMethod: method, payProvider: provider, payRef: ref);
      setState(_cart.clear);
      final what = method == 'lipa' ? tr('Mobile money sale recorded') : 'Cash sale recorded';
      _showMessage(n == null ? what : 'Order ${orderLabel(n)} recorded',
          success: true, receipt: receipt);
      SyncService().sync(); // send anything that was waiting
    } else {
      _showMessage('Sale not recorded: ${result.message}');
    }
    await _fetchProducts(); // stock may have changed
  }

  /// Sell the cart on credit to a customer. Needs internet (the debt and the
  /// stock change are saved together on the server).
  Future<void> _creditSale() async {
    if (!SyncService().online) {
      _showMessage('Credit sales need an internet connection');
      return;
    }
    if (!_validateCart()) return;
    final customer = await pickCustomer(context);
    if (customer == null || !mounted) return;

    final total = _total;
    final terms =
        await askCreditTerms(context, customerName: customer.name, total: total);
    if (terms == null || !mounted) return;

    final items = _cartItems();
    final lines = [
      for (final l in _cart.values) '${l.product.id}:${l.unit?.id ?? ''}x${l.quantity}'
    ]..sort();
    final key = '${customer.id}|$_level|${lines.join(',')}';
    if (_creditKey != key) {
      _creditKey = key;
      _creditReceiptId = const Uuid().v4();
      _creditSoldAt = DateTime.now();
    }
    final receiptId = _creditReceiptId!;
    final soldAt = _creditSoldAt!;

    setState(() => _saving = true);
    try {
      final res = await CreditService().creditSale(
        items: items,
        customerId: customer.id,
        receiptId: receiptId,
        soldAt: soldAt,
        paidNow: terms.paidNow,
        paidMethod: terms.method,
      );
      if (!mounted) return;
      final orderNo = res.orderNo;
      final deposit = res.depositRecorded ? terms.paidNow : 0.0;
      final receipt = _cartAsOrder(receiptId, soldAt, orderNo,
          paymentMethod: 'credit', paidNow: deposit);
      _creditKey = null;
      setState(() {
        _saving = false;
        _cart.clear();
      });
      var msg = orderNo == null
          ? 'Credit sale recorded for ${customer.name}'
          : 'Order ${orderLabel(orderNo)} on credit for ${customer.name}';
      if (deposit > 0) msg += ' - ${tr('Paid now')} ${tzs(deposit)}';
      if (terms.paidNow > 0 && !res.depositRecorded) {
        msg += '. ${tr('The deposit was not recorded. Add it from the customer page (Record payment).')}';
      }
      _showMessage(msg, success: true, receipt: receipt);
      SyncService().sync();
      await _fetchProducts(); // stock changed
    } on CreditRejected catch (e) {
      _creditKey = null; // the server said no: nothing was recorded
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('${tr('Sale not recorded')}: ${friendly(e)}');
    } catch (_) {
      // Unknown result (timeout, lost signal). Keep the same receipt id so that
      // pressing the button again cannot record the sale twice.
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
          'Could not confirm the sale. Check your connection and press Credit again. It will not be recorded twice.');
    }
  }

  Future<String?> _askPhone() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Pay ${tzs(_total)}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: tr('Customer phone (optional)'),
            hintText: '07XXXXXXXX',
            prefixIcon: Icon(Icons.phone_android),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, controller.text.trim()),
            child: Text(tr('Continue')),
          ),
        ],
      ),
    );
  }

  /// M-Pesa / Tigo Pesa / Airtel Money / card via Pesapal.
  /// The server records the sale only after Pesapal confirms payment, so do NOT call recordSale here.
  Future<void> _mobileSale() async {
    if (!SyncService().online) {
      _showMessage(tr('Mobile / Card payments need an internet connection'));
      return;
    }
    if (!_validateCart()) return;
    if (!_retailOnly) {
      _showMessage(tr('Card / Online works with retail prices and single items only.'));
      return;
    }
    final phone = await _askPhone();
    if (phone == null || !mounted) return; // cancelled
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PesapalCheckoutScreen(
          items: [
            for (final l in _cart.values)
              {
                'product_id': l.product.id,
                'quantity': l.quantity,
                'unit_price': l.product.price,
              }
          ],
          total: _total,
          customerPhone: phone.isEmpty ? null : phone,
        ),
      ),
    );
    if (!mounted) return;
    if (paid == true) {
      setState(_cart.clear);
      _showMessage(tr('Payment received, sale recorded'), success: true);
      await _fetchProducts();
    } else {
      _showMessage(tr('Payment was not completed'));
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('New Sale')),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          if (_cart.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: tr('Clear all'),
              onPressed: _saving ? null : _clearCart,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const PendingSyncBanner(),
                if (_usingCache) _cacheNotice(),
                _buildSearchBar(),
                Expanded(child: _results.isNotEmpty ? _buildResults() : _buildCart()),
                if (!keyboardOpen) _buildPayPanel(),
              ],
            ),
    );
  }

  Widget _cacheNotice() {
    return Container(
      width: double.infinity,
      color: Colors.amber[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: Colors.amber[900]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline: using your saved product list. Cash sales are saved on '
              'this phone and sent later.',
              style: TextStyle(fontSize: 12, color: Colors.amber[900]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: tr('Type name or barcode...'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.clear), onPressed: _clearSearch),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchSubmitted,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: tr('Scan barcode / QR'),
                style: IconButton.styleFrom(backgroundColor: Colors.blue[900]),
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _scan,
              ),
              IconButton.filledTonal(
                tooltip: tr('Browse by category'),
                icon: const Icon(Icons.category_outlined),
                onPressed: _openBrowse,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: Text(tr('Keep scanning')),
              visualDensity: VisualDensity.compact,
              selected: _keepScanning,
              onSelected: (v) => setState(() => _keepScanning = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _results[i];
        final out = p.stockQuantity <= 0;
        return ListTile(
          enabled: !out,
          title: Text(p.title),
          subtitle: Text('${categoryOf(p)}  •  ${tzs(p.priceFor(_level))}  •  '
              '${out ? 'out of stock' : '${p.stockQuantity} in stock'}'),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: () {
            if (_addToCart(p)) _clearSearch();
          },
        );
      },
    );
  }

  Widget _buildCart() => Column(
        children: [
          if (_hasLevels) _levelBar(),
          Expanded(child: _buildCartBody()),
        ],
      );

  Widget _buildCartBody() {
    if (_cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'Cart is empty.\nScan, search or browse to add items.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
    final lines = _cart.values.toList().reversed.toList(); // newest on top
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.product.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(_priceNote(line),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      if (line.product.units.isNotEmpty) _unitMenu(line),
                      const SizedBox(height: 2),
                      Text(tzs(_lineTotal(line)),
                          style: TextStyle(
                              color: Colors.blue[900], fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _saving ? null : () => _changeQty(line, -1),
                ),
                InkWell(
                  onTap: _saving ? null : () => _editQty(line),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 36),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey)),
                    ),
                    child: Text('${line.quantity}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _saving ? null : () => _changeQty(line, 1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayPanel() {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total ($_itemCount ${_itemCount == 1 ? 'item' : 'items'})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(tzs(_total),
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: CircularProgressIndicator(),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _cart.isEmpty ? null : _cashSale,
                          icon: const Icon(Icons.payments),
                          label: Text(tr('Cash'),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _cart.isEmpty ? null : _lipaSale,
                          icon: const Icon(Icons.account_balance_wallet_outlined),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(tr('Mobile money'),
                                maxLines: 1,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kLipaColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (!_saving)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: (_cart.isEmpty || !SyncService().online || !_retailOnly)
                                ? null
                                : _mobileSale,
                            icon: const Icon(Icons.credit_card),
                            label: Text(tr('Card / Online')),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: (_cart.isEmpty || !SyncService().online)
                                ? null
                                : _creditSale,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text(tr('Credit (debt)')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_saving && !SyncService().online)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('Card / Online and Credit need internet'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to browse the catalogue by category and tap items into the cart.
class _BrowseSheet extends StatefulWidget {
  final List<Product> products;
  final int Function(Product) qtyInCart;
  final bool Function(Product) onAdd;

  const _BrowseSheet({
    required this.products,
    required this.qtyInCart,
    required this.onAdd,
  });

  @override
  State<_BrowseSheet> createState() => _BrowseSheetState();
}

class _BrowseSheetState extends State<_BrowseSheet> {
  String? _category;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final groups = groupByCategory(widget.products);
    final counts = {for (final e in groups.entries) e.key: e.value.length};
    final q = _query.trim().toLowerCase();

    // Flatten into headers (String) and products for a lazy list.
    final rows = <Object>[];
    groups.forEach((cat, items) {
      if (_category != null && _category != cat) return;
      final shown = q.isEmpty
          ? items
          : items
              .where((p) => p.title.toLowerCase().contains(q) || p.barcode.contains(q))
              .toList();
      if (shown.isEmpty) return;
      if (_category == null) rows.add(cat);
      rows.addAll(shown);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('Browse items'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              hintText: tr('Filter by name or barcode'),
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        CategoryChips(
          counts: counts,
          total: widget.products.length,
          selected: _category,
          onSelected: (c) => setState(() => _category = c),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(tr('No items'), style: TextStyle(color: Colors.grey[600])))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(row,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: Colors.blue[900])),
                      );
                    }
                    final p = row as Product;
                    final inCart = widget.qtyInCart(p);
                    final out = p.stockQuantity <= 0;
                    return ListTile(
                      enabled: !out,
                      title: Text(p.title),
                      subtitle: Text(
                          '${tzs(p.price)}  •  ${out ? 'out of stock' : '${p.stockQuantity} in stock'}'),
                      trailing: inCart > 0
                          ? CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.blue[900],
                              child: Text('$inCart',
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                            )
                          : const Icon(Icons.add_circle_outline),
                      onTap: () {
                        if (widget.onAdd(p)) setState(() {});
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}