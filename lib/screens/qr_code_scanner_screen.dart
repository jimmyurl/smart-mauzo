import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';

class QRCodeScannerScreen extends StatefulWidget {
  const QRCodeScannerScreen({Key? key}) : super(key: key);

  @override
  _QRCodeScannerScreenState createState() => _QRCodeScannerScreenState();
}

class _QRCodeScannerScreenState extends State<QRCodeScannerScreen> {
  @override
  void initState() {
    super.initState();
    // Start scanning when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanQR();
    });
  }

  Future<void> _scanQR() async {
    String barcodeScanRes;
    
    try {
      barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666', // Line color
        'Cancel', // Cancel button text
        true, // Show flash icon
        ScanMode.QR, // Specify scan mode (QR, BARCODE, DEFAULT)
      );
    } on PlatformException {
      barcodeScanRes = 'Failed to get scan result';
      Navigator.pop(context, null);
      return;
    }

    if (!mounted) return;

    // Return null if scan was cancelled
    if (barcodeScanRes == '-1') {
      Navigator.pop(context, null);
      return;
    }
    
    // Return the scan result to the previous screen
    Navigator.pop(context, barcodeScanRes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Initializing scanner...'),
          ],
        ),
      ),
    );
  }
}