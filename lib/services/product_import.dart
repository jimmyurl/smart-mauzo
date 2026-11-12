import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../models/business_type.dart';
import '../models/product.dart';
import 'supabase_service.dart';

/// One product read from the file, ready to be saved.
class ImportRow {
  final int line; // row number as the person sees it in Excel
  final String title;
  final double price;
  final double buyingPrice;
  final int stock;
  final String barcode;
  final String category;
  final String? description;
  final DateTime? expiry;
  final double? priceWholesale;
  final double? priceSpecial;
  final String? baseUnit;

  const ImportRow({
    required this.line,
    required this.title,
    required this.price,
    required this.buyingPrice,
    required this.stock,
    required this.barcode,
    required this.category,
    this.description,
    this.expiry,
    this.priceWholesale,
    this.priceSpecial,
    this.baseUnit,
  });

  Map<String, dynamic> toInsert() => {
        'title': title,
        'price': price,
        'buying_price': buyingPrice,
        'stock_quantity': stock,
        'barcode': barcode,
        'description': description,
        'category': category,
        'expiry_date': expiry == null
            ? null
            : '${expiry!.year.toString().padLeft(4, '0')}-'
                '${expiry!.month.toString().padLeft(2, '0')}-'
                '${expiry!.day.toString().padLeft(2, '0')}',
        // Only sent when filled in, so an import still works before the units SQL is installed.
        if (priceWholesale != null) 'price_wholesale': priceWholesale,
        if (priceSpecial != null) 'price_special': priceSpecial,
        if (baseUnit != null) 'unit_name': baseUnit,
      };
}

/// A row that was not imported, and why. [reason] is an English sentence the
/// screen passes through tr().
class ImportIssue {
  final int line;
  final String reason;
  const ImportIssue(this.line, this.reason);
}

class ImportParseResult {
  final List<ImportRow> rows;
  final List<ImportIssue> skipped;
  final String? fatal; // the file cannot be used at all
  const ImportParseResult({this.rows = const [], this.skipped = const [], this.fatal});
}

class ImportOutcome {
  int imported = 0;
  final List<ImportIssue> failed = [];
  bool stoppedEarly = false;
  bool ownerOnly = false;
}

/// Reads a product list from an .xlsx or .csv file and saves it.
/// Needs a header row. Only Name and Selling price are required.
class ProductImport {
  // Header names that mean each field (compared in lower case, letters and digits only).
  static const Map<String, List<String>> _aliases = {
    'name': ['name', 'productname', 'product', 'item', 'itemname', 'itemdescription',
      'productdescription', 'particulars', 'title', 'jina', 'bidhaa', 'majina'],
    'barcode': ['barcode', 'code', 'sku', 'itemcode', 'productcode', 'msimbo', 'bar'],
    'buying': ['buyingprice', 'buyprice', 'cost', 'costprice', 'purchaseprice', 'unitcost',
      'buying', 'beiyakununua', 'beiyanunua'],
    'price': ['sellingprice', 'sellprice', 'saleprice', 'retailprice', 'unitprice', 'selling',
      'price', 'beiyakuuza', 'beiyauzaji', 'bei'],
    'qty': ['quantity', 'qty', 'stock', 'stockquantity', 'instock', 'onhand', 'idadi', 'stoo',
      'bookbalanceqty', 'bookbalance', 'balance', 'qtyonhand', 'openingstock', 'openingqty'],
    'category': ['category', 'categoryname', 'group', 'department', 'aina', 'kundi'],
    'expiry': ['expiry', 'expirydate', 'expdate', 'exp', 'expires', 'tareheyakuisha', 'mudawakuisha'],
    'description': ['description', 'notes', 'note', 'maelezo'],
    'wholesale': ['wholesaleprice', 'wholesale', 'beiyajumla', 'jumla'],
    'special': ['specialprice', 'contractorprice', 'special', 'contractor', 'beimaalum', 'maalum'],
    'unit': ['unit', 'baseunit', 'uom', 'kipimo', 'kizio'],
  };

  // ------------------------------------------------------------------ template
  /// A small example file (CSV) with a few rows that fit [type].
  static String templateCsv(BusinessType? type) {
    // Name, Barcode, Buying, Selling, Wholesale, Special, Unit, Quantity, Category, Expiry
    final samples = <BusinessType, List<List<String>>>{
      BusinessType.pharmacy: [
        ['Paracetamol 500mg', '6001234500011', '30', '50', '45', '', 'tablet', '1200', 'Pain & fever', '2027-06-30'],
        ['Amoxicillin 500mg', '', '90', '150', '130', '', 'capsule', '600', 'Antibiotics', '2027-03-31'],
      ],
      BusinessType.supermarket: [
        ['Soda 500ml', '5449000000996', '700', '1000', '900', '', 'bottle', '48', 'Beverages', '2027-01-31'],
        ['Rice 1kg', '', '2200', '2800', '2600', '', 'pack', '30', 'Rice, flour & grains', ''],
      ],
      BusinessType.hardware: [
        ['Cement 50kg', '', '14500', '16000', '15500', '15000', 'bag', '40', 'Cement & building', ''],
        ['Nail 3 inch', '', '10', '15', '12', '11', 'piece', '2500', 'Nails, screws & fasteners', ''],
      ],
      BusinessType.general: [
        ['Sugar 1kg', '', '2600', '3200', '3000', '', 'pack', '20', 'Food & drinks', ''],
        ['Airtime voucher 1000', '', '950', '1000', '', '', '', '100', 'Phone & airtime', ''],
      ],
    };
    final rows = <List<String>>[
      ['Name', 'Barcode', 'Buying price', 'Selling price', 'Wholesale price', 'Special price',
        'Unit', 'Quantity', 'Category', 'Expiry date'],
      ...(samples[type ?? BusinessType.general] ?? samples[BusinessType.general]!),
    ];
    String q(String f) => (f.contains(',') || f.contains('"')) ? '"${f.replaceAll('"', '""')}"' : f;
    return rows.map((r) => r.map(q).join(',')).join('\r\n');
  }

  // --------------------------------------------------------------------- parse
  static ImportParseResult parse({
    required String fileName,
    required Uint8List bytes,
    required List<Product> existing,
  }) {
    List<List<String>> grid;
    try {
      final lower = fileName.toLowerCase();
      if (lower.endsWith('.xlsx')) {
        grid = _readXlsx(bytes);
      } else if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
        grid = _readCsv(utf8.decode(bytes, allowMalformed: true));
      } else {
        return const ImportParseResult(
            fatal: 'Only .xlsx and .csv files are supported (in Excel use Save As, then choose .xlsx).');
      }
    } catch (_) {
      return const ImportParseResult(fatal: 'Could not read this file. Is it a valid .xlsx or .csv?');
    }

    // The header row is the first of the top rows that names at least two known columns
    // (a title or logo above it is fine). Otherwise the first row that has anything in it.
    var h = -1;
    var cols = <String, int>{};
    final scan = min(grid.length, 40);
    for (var i = 0; i < scan; i++) {
      final m = _headerMap(grid[i]);
      if (m.containsKey('name') && m.length >= 2) {
        h = i;
        cols = m;
        break;
      }
    }
    if (h < 0) {
      h = grid.indexWhere((r) => r.any((c) => c.trim().isNotEmpty));
      if (h < 0) return const ImportParseResult(fatal: 'The file is empty.');
      cols = _headerMap(grid[h]);
    }
    if (!cols.containsKey('name')) {
      return const ImportParseResult(
          fatal: 'Could not find a Name column. The table needs a header row such as Name, Selling price, Quantity.');
    }
    if (!cols.containsKey('price')) {
      return const ImportParseResult(
          fatal: 'Could not find a Selling price column. Add one (and Buying price if you have it), then import again.');
    }

    final barcodesInShop = <String>{
      for (final p in existing)
        if (p.barcode.trim().isNotEmpty) p.barcode.trim(),
    };
    final namesWithoutBarcode = <String>{
      for (final p in existing)
        if (p.barcode.trim().isEmpty) p.title.trim().toLowerCase(),
    };
    final seenBarcodes = <String>{};
    final seenNames = <String>{};

    final rows = <ImportRow>[];
    final skipped = <ImportIssue>[];

    for (var r = h + 1; r < grid.length; r++) {
      final cells = grid[r];
      if (cells.every((c) => c.trim().isEmpty)) continue;
      final line = r + 1;
      String cell(String field) {
        final i = cols[field];
        return (i == null || i >= cells.length) ? '' : cells[i].trim();
      }

      final title = cell('name');
      if (title.isEmpty) {
        skipped.add(ImportIssue(line, 'Missing name'));
        continue;
      }
      final price = _num(cell('price'));
      if (price == null || price <= 0 || price > 1e10) {
        skipped.add(ImportIssue(line, 'Missing or invalid selling price'));
        continue;
      }
      double buying = 0;
      if (cell('buying').isNotEmpty) {
        final b = _num(cell('buying'));
        if (b == null || b < 0 || b > 1e10) {
          skipped.add(ImportIssue(line, 'Invalid buying price'));
          continue;
        }
        buying = b;
      }
      var stock = 0;
      if (cell('qty').isNotEmpty) {
        final q = _num(cell('qty'));
        if (q == null || q < 0 || q > 1e9 || q != q.roundToDouble()) {
          skipped.add(ImportIssue(line, 'Invalid quantity'));
          continue;
        }
        stock = q.round();
      }
      DateTime? expiry;
      if (cell('expiry').isNotEmpty) {
        expiry = _date(cell('expiry'));
        if (expiry == null) {
          skipped.add(ImportIssue(line, 'Expiry date not understood (use 2027-06-30)'));
          continue;
        }
      }

      double? wholesale;
      if (cell('wholesale').isNotEmpty) {
        final w = _num(cell('wholesale'));
        if (w == null || w <= 0 || w > 1e10) {
          skipped.add(ImportIssue(line, 'Invalid wholesale price'));
          continue;
        }
        wholesale = (w * 100).round() / 100;
      }
      double? special;
      if (cell('special').isNotEmpty) {
        final sp = _num(cell('special'));
        if (sp == null || sp <= 0 || sp > 1e10) {
          skipped.add(ImportIssue(line, 'Invalid special price'));
          continue;
        }
        special = (sp * 100).round() / 100;
      }
      final unitText = cell('unit');

      var barcode = cell('barcode').replaceAll(RegExp(r'\s'), '');
      if (RegExp(r'^\d+\.0+$').hasMatch(barcode)) barcode = barcode.split('.').first;

      if (barcode.isNotEmpty) {
        if (barcodesInShop.contains(barcode)) {
          skipped.add(ImportIssue(line, 'Barcode already in your shop'));
          continue;
        }
        if (!seenBarcodes.add(barcode)) {
          skipped.add(ImportIssue(line, 'Barcode repeated in the file'));
          continue;
        }
      } else {
        final key = title.toLowerCase();
        if (namesWithoutBarcode.contains(key)) {
          skipped.add(ImportIssue(line, 'Already in your shop'));
          continue;
        }
        if (!seenNames.add(key)) {
          skipped.add(ImportIssue(line, 'Repeated in the file'));
          continue;
        }
      }

      final category = cell('category');
      final description = cell('description');
      rows.add(ImportRow(
        line: line,
        title: title.length > 120 ? title.substring(0, 120) : title,
        price: (price * 100).round() / 100,
        buyingPrice: (buying * 100).round() / 100,
        stock: stock,
        barcode: barcode,
        category: category.isEmpty ? 'Uncategorized' : category,
        description: description.isEmpty ? null : description,
        expiry: expiry,
        priceWholesale: wholesale,
        priceSpecial: special,
        baseUnit: unitText.isEmpty ? null : (unitText.length > 30 ? unitText.substring(0, 30) : unitText),
      ));
    }
    return ImportParseResult(rows: rows, skipped: skipped);
  }

  // ---------------------------------------------------------------------- save
  /// Saves the rows in batches of 100. A batch the server refuses is retried row
  /// by row, so one bad row never blocks the others. Never throws.
  static Future<ImportOutcome> run(
    List<ImportRow> rows, {
    void Function(int done, int total)? onProgress,
  }) async {
    final svc = SupabaseService();
    final out = ImportOutcome();
    const batch = 100;
    try {
      for (var i = 0; i < rows.length; i += batch) {
        final chunk = rows.sublist(i, min(i + batch, rows.length));
        try {
          await svc.addProductsBulk([for (final r in chunk) r.toInsert()]);
          out.imported += chunk.length;
        } on PostgrestException catch (e) {
          if (e.code == '42501') {
            out.ownerOnly = true;
            return out;
          }
          for (final r in chunk) {
            try {
              await svc.addProductsBulk([r.toInsert()]);
              out.imported++;
            } on PostgrestException catch (e2) {
              out.failed.add(ImportIssue(
                  r.line, e2.code == '23505' ? 'Barcode already in your shop' : e2.message));
            }
          }
        }
        onProgress?.call(min(i + batch, rows.length), rows.length);
      }
    } catch (_) {
      out.stoppedEarly = true; // no internet or timeout: what was added stays
    }
    return out;
  }

  // ------------------------------------------------------------------- helpers
  /// Which column holds which field, judging by the header texts of [row].
  static Map<String, int> _headerMap(List<String> row) {
    final cols = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final key = row[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (key.isEmpty) continue;
      for (final e in _aliases.entries) {
        if (!cols.containsKey(e.key) && e.value.contains(key)) {
          cols[e.key] = i;
          break;
        }
      }
    }
    return cols;
  }

  /// "14,500", "TZS 14 500", "1.500,50", "1500.5" -> number. Null if it is not one.
  static double? _num(String input) {
    var t = input.trim().replaceAll(RegExp(r'[^0-9.,\-]'), '');
    if (t.isEmpty || t == '-') return null;
    if (t.contains(',') && t.contains('.')) {
      if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
        t = t.replaceAll('.', '').replaceAll(',', '.'); // 1.500,50
      } else {
        t = t.replaceAll(',', ''); // 1,500.50
      }
    } else if (t.contains(',')) {
      final parts = t.split(',');
      if (parts.length > 1 && parts.last.length == 3) {
        t = t.replaceAll(',', ''); // 1,500
      } else {
        t = t.replaceAll(',', '.'); // 1500,5
      }
    } else if (t.split('.').length > 2) {
      t = t.replaceAll('.', ''); // 1.500.000
    }
    return double.tryParse(t);
  }

  /// Excel date number, 2027-06-30, 30/06/2027, 30-06-2027, 30.06.2027 or 06/2027
  /// (last day of that month). Null if it is none of these.
  static DateTime? _date(String input) {
    final s = input.trim();
    final serial = RegExp(r'^(\d{4,6})(\.\d+)?$').firstMatch(s);
    if (serial != null) {
      final n = int.parse(serial.group(1)!);
      if (n >= 20000 && n <= 80000) return DateTime(1899, 12, 30).add(Duration(days: n));
      return null;
    }
    DateTime? make(int y, int m, int d) {
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
      final date = DateTime(y, m, d);
      return date.month == m ? date : null; // 31 Feb -> not a real date
    }

    var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
    if (m != null) return make(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s);
    if (m != null) return make(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    m = RegExp(r'^(\d{1,2})[-/.](\d{4})$').firstMatch(s);
    if (m != null) {
      final month = int.parse(m.group(1)!);
      final year = int.parse(m.group(2)!);
      if (month < 1 || month > 12) return null;
      return make(year, month, DateTime(year, month + 1, 0).day);
    }
    return null;
  }

  static List<List<String>> _readCsv(String text) {
    var t = text.startsWith('\uFEFF') ? text.substring(1) : text;
    final firstLine = t.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final counts = {',': 0, ';': 0, '\t': 0};
    for (final ch in firstLine.split('')) {
      if (counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
    }
    var delim = ',';
    var best = counts[',']!;
    for (final e in counts.entries) {
      if (e.value > best) {
        best = e.value;
        delim = e.key;
      }
    }

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == delim) {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  /// First sheet of an .xlsx file as rows of text. Row i of the result is Excel row i + 1.
  static List<List<String>> _readXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String? read(String name) {
      final f = archive.findFile(name);
      if (f == null) return null;
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final shared = <String>[];
    final ss = read('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    // The first sheet listed in the workbook (usually sheet1.xml).
    var sheetPath = 'xl/worksheets/sheet1.xml';
    try {
      final wb = XmlDocument.parse(read('xl/workbook.xml')!);
      final rid = wb.findAllElements('sheet').first.getAttribute('r:id');
      final rels = XmlDocument.parse(read('xl/_rels/workbook.xml.rels')!);
      for (final r in rels.findAllElements('Relationship')) {
        if (r.getAttribute('Id') == rid) {
          final target = r.getAttribute('Target') ?? '';
          sheetPath = target.startsWith('/')
              ? target.substring(1)
              : (target.startsWith('xl/') ? target : 'xl/$target');
        }
      }
    } catch (_) {}
    final sheetXml = read(sheetPath) ?? read('xl/worksheets/sheet1.xml');
    if (sheetXml == null) throw const FormatException('no sheet');

    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
      final index = int.tryParse(row.getAttribute('r') ?? '') ?? (rows.length + 1);
      while (rows.length < index) {
        rows.add(<String>[]);
      }
      final cells = rows[index - 1];
      for (final c in row.findElements('c')) {
        var col = _colIndex(c.getAttribute('r') ?? '');
        if (col < 0) col = cells.length;
        final type = c.getAttribute('t');
        var value = '';
        if (type == 'inlineStr') {
          value = c.findAllElements('t').map((e) => e.innerText).join();
        } else {
          final v = c.getElement('v')?.innerText ?? '';
          if (type == 's') {
            final idx = int.tryParse(v);
            value = (idx != null && idx >= 0 && idx < shared.length) ? shared[idx] : '';
          } else if (type == 'b') {
            value = v == '1' ? 'TRUE' : 'FALSE';
          } else {
            value = v;
          }
        }
        while (cells.length <= col) {
          cells.add('');
        }
        cells[col] = value;
      }
    }
    return rows;
  }

  /// "B7" -> 1, "AA3" -> 26, no letters -> -1.
  static int _colIndex(String ref) {
    var n = 0;
    var any = false;
    for (final u in ref.toUpperCase().codeUnits) {
      if (u < 65 || u > 90) break;
      n = n * 26 + (u - 64);
      any = true;
    }
    return any ? n - 1 : -1;
  }
}