import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_language.dart';
import '../services/product_import.dart';
import '../services/shop_settings.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';

enum _Stage { pick, reading, review, importing, done }

/// Owner only: add many products at once from an Excel (.xlsx) or CSV file.
class ImportProductsScreen extends StatefulWidget {
  const ImportProductsScreen({super.key});

  @override
  State<ImportProductsScreen> createState() => _ImportProductsScreenState();
}

class _ImportProductsScreenState extends State<ImportProductsScreen> {
  _Stage _stage = _Stage.pick;
  ImportParseResult? _parsed;
  ImportOutcome? _outcome;
  String _error = '';
  int _done = 0;
  int _total = 0;

  Future<void> _shareTemplate() async {
    final csv = ProductImport.templateCsv(ShopSettings.type.value);
    try {
      await Share.shareXFiles([
        XFile.fromData(
          Uint8List.fromList(utf8.encode('\uFEFF$csv')),
          mimeType: 'text/csv',
          name: 'smart_mauzo_products_template.csv',
        ),
      ]);
    } catch (_) {
      await Share.share(csv); // no file sharing here: send the text instead
    }
  }

  Future<void> _pick() async {
    setState(() => _error = '');
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
    } catch (_) {
      setState(() => _error = tr('Could not open the file picker.'));
      return;
    }
    if (res == null || res.files.isEmpty) return;
    final file = res.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = tr('Could not read this file.'));
      return;
    }

    setState(() => _stage = _Stage.reading);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let the spinner show
    try {
      final existing = await SupabaseService().getProducts();
      final parsed = ProductImport.parse(fileName: file.name, bytes: bytes, existing: existing);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _stage = _Stage.review;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.pick;
        _error = tr('Import needs internet. Check your connection and try again.');
      });
    }
  }

  Future<void> _import() async {
    final rows = _parsed?.rows ?? const <ImportRow>[];
    if (rows.isEmpty) return;
    setState(() {
      _stage = _Stage.importing;
      _done = 0;
      _total = rows.length;
    });
    final out = await ProductImport.run(rows, onProgress: (d, t) {
      if (mounted) setState(() => _done = d);
    });
    if (!mounted) return;
    setState(() {
      _outcome = out;
      _stage = _Stage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final readyRows = _parsed?.rows.length ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(tr('Import products')),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _body(),
      bottomNavigationBar: (_stage == _Stage.review && readyRows > 0)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pick,
                        child: Text(tr('Choose another file')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _import,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[900],
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text('${tr('Import')} $readyRows',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.pick:
        return _pickView();
      case _Stage.reading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(tr('Reading file...')),
            ],
          ),
        );
      case _Stage.review:
        return _reviewView();
      case _Stage.importing:
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Importing...'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 8),
                const SizedBox(height: 8),
                Text('$_done / $_total'),
              ],
            ),
          ),
        );
      case _Stage.done:
        return _doneView();
    }
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _pickView() {
    const columns = [
      'Name *',
      'Selling price *',
      'Barcode',
      'Buying price',
      'Wholesale price',
      'Special price',
      'Unit',
      'Quantity',
      'Category',
      'Expiry date',
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.upload_file, color: Colors.blue[900]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('Import from Excel or CSV'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(tr('Your file needs a header row. Only Name and Selling price are required.'),
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const SizedBox(height: 10),
              Text(tr('Columns'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final c in columns) Chip(label: Text(c), visualDensity: VisualDensity.compact)],
              ),
              const SizedBox(height: 10),
              Text(
                tr('Products already in your shop are skipped, so it is safe to import the same file again.'),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error, style: const TextStyle(color: Colors.red)),
          ),
        ElevatedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open),
          label: Text(tr('Choose file (.xlsx or .csv)')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[900],
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _shareTemplate,
          icon: const Icon(Icons.download),
          label: Text(tr('Share template')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Widget _issueList(List<ImportIssue> issues) {
    const show = 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in issues.take(show))
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('${tr('Row')} ${i.line}: ${tr(i.reason)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[800])),
          ),
        if (issues.length > show)
          Text('... +${issues.length - show}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _reviewView() {
    final p = _parsed!;
    if (p.fatal != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: Colors.red[700]),
                const SizedBox(height: 8),
                Text(tr(p.fatal!)),
              ],
            ),
          ),
          ElevatedButton(onPressed: _pick, child: Text(tr('Choose another file'))),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tr('Ready to import')}: ${p.rows.length}',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[700])),
              if (p.rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(tr('Preview'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final r in p.rows.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13))),
                        Text('${tzs(r.price)}  x${r.stock}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (p.skipped.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tr('Skipped')}: ${p.skipped.length}',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800])),
                const SizedBox(height: 8),
                _issueList(p.skipped),
              ],
            ),
          ),
        if (p.rows.isEmpty)
          ElevatedButton(onPressed: _pick, child: Text(tr('Choose another file'))),
      ],
    );
  }

  Widget _doneView() {
    final o = _outcome!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(o.imported > 0 ? Icons.check_circle : Icons.info_outline,
                  size: 36, color: o.imported > 0 ? Colors.green[700] : Colors.orange[800]),
              const SizedBox(height: 8),
              Text('${o.imported} ${tr('products imported')}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (o.ownerOnly) ...[
                const SizedBox(height: 8),
                Text(tr('Only the shop owner can import products.'),
                    style: const TextStyle(color: Colors.red)),
              ],
              if (o.stoppedEarly) ...[
                const SizedBox(height: 8),
                Text(tr('The import stopped early (no internet?). Products already added are kept; import the file again to add the rest.'),
                    style: TextStyle(color: Colors.orange[900], fontSize: 13)),
              ],
            ],
          ),
        ),
        if (o.failed.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tr('Could not import')}: ${o.failed.length}',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[700])),
                const SizedBox(height: 8),
                _issueList(o.failed),
              ],
            ),
          ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, o.imported > 0),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[900],
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(tr('Done')),
        ),
      ],
    );
  }
}