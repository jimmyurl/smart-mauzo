import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language of the app: English ('en') or Swahili ('sw'). The choice is kept on
/// the phone. Change it with [AppLanguage.set]; the whole app redraws by itself.
class AppLanguage {
  static const _key = 'app_language';
  static final ValueNotifier<String> notifier = ValueNotifier<String>('en');

  static bool get isSwahili => notifier.value == 'sw';

  /// Call once at start-up (before runApp).
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      if (v == 'sw' || v == 'en') notifier.value = v!;
    } catch (_) {}
  }

  static Future<void> set(String code) async {
    notifier.value = code == 'sw' ? 'sw' : 'en';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, notifier.value);
    } catch (_) {}
  }
}

/// Translates an English text of the app. Unknown texts stay in English, so a missing
/// translation can never break a screen.
String tr(String en) => AppLanguage.isSwahili ? (_sw[en] ?? en) : en;

/// Text safe to show to a shop owner or cashier, in the chosen language.
///
/// Technical details (socket errors, URLs, error codes, stack traces, database
/// wording) are never shown: they only go to the debug log. Messages that the
/// database or the app wrote for people are translated; anything else becomes a
/// short, general sentence.
String friendly(Object? e) {
  final raw = _rawText(e);
  final text = raw.toLowerCase();
  debugPrint('friendly(): $raw');

  // Short sentences the app wrote itself for people (e.g. "Enter a valid phone number").
  if (e is FormatException && _looksHuman(e.message)) return tr(e.message);

  const offline = [
    'socketexception', 'clientexception', 'timeoutexception', 'handshake',
    'connection', 'network', 'failed host lookup', 'waiting to sign in',
    'timed out', 'timeout', 'xmlhttprequest', 'software caused', 'unreachable',
    'jwt', 'not signed in', 'refresh_token', 'session', '502', '503', '504',
  ];
  if (e is SocketException || e is TimeoutException || offline.any(text.contains)) {
    return tr('No internet connection.\nYour data will load again when you are back online.');
  }

  // Wording written on purpose by the database functions (sql files) or the app.
  const known = <String, String>{
    'insufficient stock': 'Not enough stock for this item.',
    'cart is empty': 'Add at least one item first.',
    'invalid item': 'One of the items is not valid.',
    'product not found': 'This item was not found. Refresh and try again.',
    'only the shop owner': 'Only the shop owner can do this.',
    'no access': 'You do not have access to do this.',
    'permission denied': 'You do not have access to do this.',
    'row-level security': 'You do not have access to do this.',
    'amount paid is more than the total': 'The amount paid is more than the total.',
    'amount paid cannot be negative': 'The amount paid cannot be negative.',
    'owes only': 'The customer owes less than this amount.',
    'enter an amount': 'Enter an amount.',
    'choose a customer': 'Choose a customer first.',
    'choose cash or mobile': 'Choose cash or mobile.',
    "enter the customer": 'Enter the customer name.',
    'name is too long': 'The name is too long.',
    'phone number is too long': 'The phone number is too long.',
    'credit history': 'This customer has credit history and cannot be deleted.',
    'customer not found': 'Customer not found.',
    'duplicate key': 'This already exists.',
    'already exists': 'This already exists.',
    'barcode': 'This barcode is already used by another item.',
    'invalid login': 'Wrong phone number or password.',
    'already registered': 'This phone number already has an account. Please log in.',
    'already been registered': 'This phone number already has an account. Please log in.',
    'email not confirmed': 'Sign-in is not ready yet. Please try again in a moment.',
    'invalid code': 'This code is not correct. Check it with the shop owner.',
  };
  for (final entry in known.entries) {
    if (text.contains(entry.key)) return tr(entry.value);
  }

  return tr('Something went wrong. Please try again.');
}

String _rawText(Object? e) {
  if (e == null) return '';
  try {
    final dynamic d = e;
    final m = d.message;
    if (m is String && m.isNotEmpty) return m;
  } catch (_) {}
  return '$e';
}

bool _looksHuman(String s) {
  final t = s.toLowerCase();
  if (s.isEmpty || s.length > 160) return false;
  const technical = [
    'exception', 'unexpected', 'null', 'type \'', 'offset', 'http', '{', '}', 'stack',
    'dart', 'invalid radix', 'format',
  ];
  return !technical.any(t.contains);
}

const Map<String, String> _sw = {
  'Home': 'Mwanzo',
  'Products': 'Bidhaa',
  'Sales': 'Mauzo',
  'Profile': 'Wasifu',
  'Reports': 'Ripoti',
  'Credit': 'Mkopo',
  'Debts': 'Madeni',
  'Cancel': 'Ghairi',
  'OK': 'Sawa',
  'Done': 'Imekamilika',
  'Yes': 'Ndiyo',
  'No': 'Hapana',
  'Retry': 'Jaribu tena',
  'Try again': 'Jaribu tena',
  'Copy': 'Nakili',
  'Continue': 'Endelea',
  'Save': 'Hifadhi',
  'Remove': 'Ondoa',
  'Log in': 'Ingia',
  'Log in or Sign up': 'Ingia au Jisajili',
  'Sign out': 'Toka',
  'Sign out?': 'Unataka kutoka?',
  'You will need to log in again to make sales.':
      'Utahitaji kuingia tena ili kuuza.',
  'New Sale': 'Mauzo Mapya',
  'New sale': 'Mauzo mapya',
  'Cash': 'Pesa taslimu',
  'Mobile / Card': 'Simu / Kadi',
  'Mobile/Card': 'Simu/Kadi',
  'Mobile money': 'Pesa ya simu',
  'Card / Online': 'Kadi / Mtandaoni',
  'Credit (debt)': 'Mkopo (deni)',
  'Card / Online and Credit need internet': 'Kadi / Mtandaoni na Mkopo vinahitaji intaneti',
  'Mobile money sale recorded': 'Mauzo ya pesa ya simu yamehifadhiwa',
  'Which network was used?': 'Mtandao gani ulitumika?',
  'Transaction reference (optional)': 'Namba ya muamala (si lazima)',
  'I received the payment confirmation SMS': 'Nimepokea ujumbe wa uthibitisho wa malipo',
  'Save sale': 'Hifadhi mauzo',
  'Send reminder': 'Tuma kumbusho',
  'Reminder message': 'Ujumbe wa kumbusho',
  'How should they pay? (optional)': 'Walipe vipi? (si lazima)',
  'Last reminder': 'Kumbusho la mwisho',
  'No reminder sent yet': 'Bado hujatuma kumbusho',
  'Share...': 'Tuma...',
  'Expenses': 'Matumizi',
  'Add expense': 'Ongeza matumizi',
  'Total expenses': 'Jumla ya matumizi',
  'Net profit': 'Faida halisi',
  'Gross profit': 'Faida ghafi',
  'No expenses recorded for this period. Tap to add rent, salaries, transport and other costs.': 'Hakuna matumizi yaliyorekodiwa kwa kipindi hiki. Gusa kuongeza kodi ya pango, mishahara, usafiri na gharama nyingine.',
  'Amount': 'Kiasi',
  'Category': 'Aina',
  'Note (optional)': 'Maelezo (si lazima)',
  'Date': 'Tarehe',
  'Enter an amount greater than zero': 'Weka kiasi kikubwa kuliko sifuri',
  'Could not save. Check your internet and try again.': 'Imeshindwa kuhifadhi. Angalia intaneti kisha ujaribu tena.',
  'Delete this expense?': 'Futa matumizi haya?',
  'Delete': 'Futa',
  'Could not delete. Check your internet and try again.': 'Imeshindwa kufuta. Angalia intaneti kisha ujaribu tena.',
  'Expenses need internet. Pull down to try again.': 'Matumizi yanahitaji intaneti. Vuta chini kujaribu tena.',
  'No expenses this month': 'Hakuna matumizi mwezi huu',
  'By category': 'Kwa aina',
  'Swipe left to delete': 'Telezesha kushoto kufuta',
  'Rent': 'Kodi ya pango',
  'Salaries': 'Mishahara',
  'Transport': 'Usafiri',
  'Electricity & water': 'Umeme na maji',
  'Airtime & internet': 'Vocha na intaneti',
  'Licenses & fees': 'Leseni na ada',
  'Supplies': 'Vifaa',
  'Repairs': 'Matengenezo',
  'Taxes': 'Kodi (TRA)',
  'Other': 'Nyingine',
  'Forgot password?': 'Umesahau nenosiri?',
  'Reset your password': 'Weka nenosiri jipya',
  'Recovery code': 'Kodi ya kurejesha akaunti',
  'Enter the recovery code you saved when you created your account.': 'Andika kodi ya kurejesha uliyohifadhi ulipofungua akaunti.',
  'New password': 'Nenosiri jipya',
  'Reset password': 'Weka nenosiri jipya',
  'Wrong phone number or recovery code.': 'Namba ya simu au kodi ya kurejesha si sahihi.',
  'Too many wrong tries. Try again in 30 minutes.': 'Umejaribu mara nyingi sana. Jaribu tena baada ya dakika 30.',
  'Enter the 10-character recovery code': 'Andika kodi ya herufi 10',
  'Password changed. You are now logged in.': 'Nenosiri limebadilishwa. Umeingia.',
  'Password changed. Please log in.': 'Nenosiri limebadilishwa. Tafadhali ingia.',
  'Could not reset. Check your internet and try again.': 'Imeshindwa. Angalia intaneti kisha ujaribu tena.',
  'Protect your account': 'Linda akaunti yako',
  'If you forget your password, a recovery code is the only way back into your shop. Create yours now and keep it safe.': 'Ukisahau nenosiri, kodi ya kurejesha ndiyo njia pekee ya kurudi kwenye duka lako. Tengeneza yako sasa na uihifadhi vizuri.',
  'Create recovery code': 'Tengeneza kodi ya kurejesha',
  'Later': 'Baadaye',
  'Your recovery code': 'Kodi yako ya kurejesha',
  'Write it down or take a screenshot and keep it safe. It is shown only once. Anyone with this code and your phone number can change your password, so never share it.': 'Iandike au piga picha ya skrini na uihifadhi mahali salama. Inaonyeshwa mara moja tu. Mtu yeyote mwenye kodi hii na namba yako ya simu anaweza kubadilisha nenosiri lako, kwa hiyo usimpe mtu.',
  'I have saved my recovery code': 'Nimehifadhi kodi yangu ya kurejesha',
  'Account security': 'Usalama wa akaunti',
  'Recovery code is set': 'Kodi ya kurejesha imewekwa',
  'No recovery code yet': 'Bado hakuna kodi ya kurejesha',
  'New recovery code': 'Kodi mpya ya kurejesha',
  'The old recovery code stops working. Continue?': 'Kodi ya zamani itaacha kufanya kazi. Endelea?',
  'Change password': 'Badilisha nenosiri',
  'Current password': 'Nenosiri la sasa',
  'Password changed': 'Nenosiri limebadilishwa',
  'Current password is wrong': 'Nenosiri la sasa si sahihi',
  'Could not create the code. Check your internet and try again.': 'Imeshindwa kutengeneza kodi. Angalia intaneti kisha ujaribu tena.',
  'Create': 'Tengeneza',
  'Could not open the app': 'Imeshindwa kufungua programu',
  'Add a phone number to this customer to message them directly.': 'Weka namba ya simu ya mteja ili kumtumia ujumbe moja kwa moja.',
  'Paid now (optional)': 'Amelipa sasa (si lazima)',
  'Paid now': 'Amelipa sasa',
  'Balance added to debt': 'Deni litakaloongezwa',
  'How was the deposit paid?': 'Amelipaje?',
  'The deposit must be less than the total. If the customer pays everything, use Cash or Mobile money.': 'Kiasi cha awali lazima kiwe chini ya jumla. Mteja akilipa yote, tumia Pesa taslimu au Pesa ya simu.',
  'The deposit was not recorded. Add it from the customer page (Record payment).': 'Malipo ya awali hayakuhifadhiwa. Yaweke kupitia ukurasa wa mteja (Weka malipo).',
  'Confirm': 'Thibitisha',
  'Choose the network the customer paid on': 'Chagua mtandao aliolipia mteja',
  'Ask the customer to pay to your shop number. Check the confirmation SMS on your phone before saving.':
      'Mwombe mteja alipe kwenye namba ya duka lako. Hakikisha umepokea ujumbe wa uthibitisho kwenye simu yako kabla ya kuhifadhi.',
  'Mobile / Card needs internet': 'Simu / Kadi inahitaji intaneti',
  'Everyone': 'Wote',
  'Search by date': 'Tafuta kwa tarehe',
  'Payment methods': 'Njia za malipo',
  'Best sellers': 'Zinazouzwa zaidi',
  'Clear all': 'Futa vyote',
  'Clear all items?': 'Futa bidhaa zote?',
  'Keep scanning': 'Endelea kuskani',
  'Browse items': 'Angalia bidhaa',
  'Type name or barcode...': 'Andika jina au barcode...',
  'Filter by name or barcode': 'Chuja kwa jina au barcode',
  'Scan barcode / QR': 'Skani barcode / QR',
  'Browse by category': 'Angalia kwa kundi',
  'Quantity': 'Idadi',
  'No items': 'Hakuna bidhaa',
  'Customer phone (optional)': 'Simu ya mteja (si lazima)',
  'Total': 'Jumla',
  'Add at least one item first': 'Weka angalau bidhaa moja kwanza',
  'Payment received, sale recorded': 'Malipo yamepokelewa, mauzo yamehifadhiwa',
  'Payment was not completed': 'Malipo hayakukamilika',
  'Mobile / Card payments need an internet connection':
      'Malipo ya Simu / Kadi yanahitaji intaneti',
  'Cash sale recorded': 'Mauzo ya pesa taslimu yamehifadhiwa',
  'Could not save the sale. Check your connection and try again.':
      'Mauzo hayakuhifadhiwa. Angalia intaneti kisha jaribu tena.',
  'No connection: sale saved on this phone and will sync automatically':
      'Hakuna intaneti: mauzo yamehifadhiwa kwenye simu na yatatumwa yenyewe',
  'No internet connection.\nYour data will load again when you are back online.':
      'Hakuna intaneti.\nTaarifa zako zitapakia tena intaneti ikirudi.',
  'Something went wrong. Please try again.': 'Kuna tatizo. Tafadhali jaribu tena.',
  'Something went wrong. Check your internet connection.':
      'Kuna tatizo. Angalia intaneti yako.',
  'Not enough stock for this item.': 'Bidhaa hii haitoshi dukani.',
  'Add at least one item first.': 'Weka angalau bidhaa moja kwanza.',
  'One of the items is not valid.': 'Moja ya bidhaa si sahihi.',
  'This item was not found. Refresh and try again.':
      'Bidhaa haijapatikana. Pakia upya kisha jaribu tena.',
  'Only the shop owner can do this.': 'Ni mmiliki wa duka tu anaweza kufanya hivi.',
  'You do not have access to do this.': 'Huna ruhusa ya kufanya hivi.',
  'The amount paid is more than the total.': 'Kiasi kilicholipwa kinazidi jumla.',
  'The amount paid cannot be negative.': 'Kiasi kilicholipwa hakiwezi kuwa hasi.',
  'The customer owes less than this amount.': 'Mteja anadaiwa chini ya kiasi hiki.',
  'Enter an amount.': 'Weka kiasi.',
  'Choose a customer first.': 'Chagua mteja kwanza.',
  'Choose cash or mobile.': 'Chagua pesa taslimu au simu.',
  'Enter the customer name.': 'Weka jina la mteja.',
  'The name is too long.': 'Jina ni refu sana.',
  'The phone number is too long.': 'Namba ya simu ni ndefu sana.',
  'This customer has credit history and cannot be deleted.':
      'Mteja huyu ana historia ya mkopo, hawezi kufutwa.',
  'Customer not found.': 'Mteja hajapatikana.',
  'This already exists.': 'Tayari ipo.',
  'This barcode is already used by another item.':
      'Barcode hii tayari inatumika na bidhaa nyingine.',
  'Wrong phone number or password.': 'Namba ya simu au nenosiri si sahihi.',
  'This phone number already has an account. Please log in.':
      'Namba hii ya simu tayari ina akaunti. Tafadhali ingia.',
  'Sign-in is not ready yet. Please try again in a moment.':
      'Kuingia bado hakuko tayari. Jaribu tena baada ya muda mfupi.',
  'This code is not correct. Check it with the shop owner.':
      'Kodi hii si sahihi. Muulize mmiliki wa duka.',
  'Guest': 'Mgeni',
  'You are not logged in': 'Hujaingia',
  'Create a free account to:': 'Fungua akaunti bure ili:',
  'Could not load your shop.\nCheck your internet connection.':
      'Duka lako halikupakia.\nAngalia intaneti yako.',
  'Could not load your cashiers.': 'Wauzaji wako hawakupakia.',
  'Add a cashier': 'Ongeza muuzaji',
  'Create code': 'Tengeneza kodi',
  'Show login code': 'Onyesha kodi ya kuingia',
  'Remove cashier': 'Ondoa muuzaji',
  'Code copied': 'Kodi imenakiliwa',
  'Your sales only': 'Mauzo yako tu',
  'You can make sales and see the sales you made.':
      'Unaweza kuuza na kuona mauzo uliyofanya.',
  'Logged in with this email': 'Umeingia na barua pepe hii',
  'Could not remove. Check your internet and try again.':
      'Imeshindwa kuondoa. Angalia intaneti kisha jaribu tena.',
  'Language': 'Lugha',
  'English': 'Kiingereza',
  'Kiswahili': 'Kiswahili',
  'All items are well stocked.': 'Bidhaa zote zinatosha dukani.',
  'Sample': 'Mfano',
  'Sample product': 'Bidhaa ya mfano',
  'Enter a valid phone number': 'Weka namba sahihi ya simu',
  'Enter the 8-character code from your shop owner':
      'Weka kodi ya herufi 8 kutoka kwa mmiliki wa duka',
  'Code not recognised. Check it with your shop owner.':
      'Kodi haijatambuliwa. Muulize mmiliki wa duka.',
  'Sale not recorded': 'Mauzo hayakuhifadhiwa',
  'Account created. Please log in.': 'Akaunti imefunguliwa. Tafadhali ingia.',
  'Shop owner': 'Mmiliki wa duka',
  'Cashier': 'Muuzaji',
  'Your cashier code': 'Kodi yako ya muuzaji',
  'Your shop owner gives you this code.\nNo phone number or password needed.':
      'Mmiliki wa duka atakupa kodi hii.\nHuhitaji namba ya simu wala nenosiri.',
  'Enter the 8-character code': 'Weka kodi ya herufi 8',
  'Phone number': 'Namba ya simu',
  'Please enter your phone number': 'Tafadhali weka namba yako ya simu',
  'Please enter a valid phone number': 'Tafadhali weka namba sahihi ya simu',
  'Password': 'Nenosiri',
  'Please enter your password': 'Tafadhali weka nenosiri lako',
  'Confirm password': 'Thibitisha nenosiri',
  'Passwords do not match': 'Manenosiri hayafanani',
  'At least 8 characters, 1 capital letter and 1 number.':
      'Angalau herufi 8, herufi kubwa 1 na namba 1.',
  'Sign up': 'Jisajili',
  'New here? Create an account': 'Mpya hapa? Fungua akaunti',
  'Already have an account? Log in': 'Una akaunti tayari? Ingia',
  'Cashier login': 'Kuingia kwa muuzaji',
  'Log in to your shop': 'Ingia kwenye duka lako',
  'Create your account': 'Fungua akaunti yako',
  'Welcome, guest!': 'Karibu, mgeni!',
  'Welcome back!': 'Karibu tena!',
  'You own this shop': 'Wewe ni mmiliki wa duka hili',
  'You work here as a cashier': 'Unafanya kazi hapa kama muuzaji',
  'My shop': 'DUKA LANGU',
  'My cashiers': 'WAUZAJI WANGU',
  'Account': 'AKAUNTI',
  'Discard': 'Futa',
  'Sync now': 'Tuma sasa',
  'Review': 'Angalia',
  'Credit book': 'Daftari la madeni',
  'Customer': 'Mteja',
  'New customer': 'Mteja mpya',
  'Name': 'Jina',
  'Search customer': 'Tafuta mteja',
  'Total owed to you': 'Jumla unayodai',
  'Cleared': 'Imelipwa',
  'No customers yet. Add one above.': 'Hakuna wateja bado. Ongeza mmoja hapo juu.',
  'No customer matches your search.': 'Hakuna mteja anayelingana na utafutaji.',
  'Enter the customer name': 'Weka jina la mteja',
  'History': 'Historia',
  'Record payment': 'Weka malipo',
  'Payment not recorded': 'Malipo hayakuhifadhiwa',
  'Amount received': 'Kiasi kilichopokelewa',
  'Enter the amount received': 'Weka kiasi kilichopokelewa',
  'Pay full balance': 'Lipa deni lote',
  'e.g. M-Pesa, cash': 'mf. M-Pesa, pesa taslimu',
  'Paid in full': 'Amelipa yote',
  'Owes you': 'Anakudai',
  'No debt': 'Hana deni',
  'Goods on credit': 'Bidhaa kwa mkopo',
  'Payment received': 'Malipo yamepokelewa',
  'On credit': 'Kwa mkopo',
  'Nothing recorded yet.': 'Hakuna kilichorekodiwa bado.',
  'Daily summary': 'Muhtasari wa siku',
  'Pick a day': 'Chagua siku',
  'Per person': 'Kila mtu',
  'Total sales': 'Jumla ya mauzo',
  'Cash to collect': 'Pesa za kukusanya',
  'No sales on this day.': 'Hakuna mauzo siku hii.',
  'You': 'Wewe',
  'Before cashiers': 'Kabla ya wauzaji',
  'Former cashier': 'Muuzaji wa zamani',
  'Stock alerts': 'Tahadhari za stoo',
  'Reorder': 'Agiza tena',
  'Expiry': 'Kuisha muda',
  'Copy order': 'Nakili oda',
  'Quantity to order': 'Idadi ya kuagiza',
  'No supplier recorded yet': 'Muuzaji hajarekodiwa bado',
  'Out of stock': 'Imeisha',
  'Expires today': 'Inaisha leo',
  'Order copied. Paste it in WhatsApp or SMS.': 'Oda imenakiliwa. Ibandike WhatsApp au SMS.',
  'Nothing to reorder. Every product has more than 5 in stock.':
      'Hakuna cha kuagiza. Kila bidhaa ina zaidi ya 5 stoo.',
  'Print': 'Chapisha',
  'PDF': 'PDF',
  'Share (WhatsApp, SMS...)': 'Tuma (WhatsApp, SMS...)',
  'Could not create the receipt': 'Risiti haikutengenezwa',
  'Receipt': 'Risiti',
  'Could not save. Check your internet connection.': 'Haikuhifadhiwa. Angalia intaneti yako.',
  'still owed': 'bado anadaiwa',
  'Order': 'Oda',
  'on credit': 'kwa mkopo',
  'Low stock': 'Stoo inaisha',
  'Overview': 'Muhtasari',
  'Transactions': 'Miamala',
  'In stock': 'Stoo',
  'Please enter a password': 'Tafadhali weka nenosiri',
  'Daily': 'Siku',
  'New code': 'Kodi mpya',
  'The old code stops working straight away and {name} is signed out of the shop. Their past sales stay with them once they log in with the new code.':
      'Kodi ya zamani inaacha kufanya kazi mara moja na {name} anatolewa kwenye duka. Mauzo yake ya zamani yatabaki naye akiingia na kodi mpya.',
  'The connection is weak, so we could not confirm. Tap the key icon to see the current code.':
      'Intaneti ni dhaifu, hatukuweza kuthibitisha. Bonyeza alama ya ufunguo kuona kodi ya sasa.',
  'Unknown error': 'Hitilafu isiyojulikana',
};