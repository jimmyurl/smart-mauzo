import 'package:flutter/material.dart';

/// What kind of business a shop is. Chosen when the shop is created (and can be
/// changed in Profile). It decides the suggested product categories and which
/// shortcuts the home screen shows.
enum BusinessType { pharmacy, supermarket, hardware, general }

class BusinessTypeInfo {
  final BusinessType type;
  final String label; // English, translated with tr() when shown
  final String description;
  final IconData icon;
  final List<String> categoriesEn;
  final List<String> categoriesSw;
  const BusinessTypeInfo({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.categoriesEn,
    required this.categoriesSw,
  });
}

const List<BusinessTypeInfo> kBusinessTypes = [
  BusinessTypeInfo(
    type: BusinessType.pharmacy,
    label: 'Pharmacy / DLDM',
    description: 'Medicines, expiry dates and dispensing',
    icon: Icons.medical_services_outlined,
    categoriesEn: [
      'Pain & fever',
      'Antibiotics',
      'Cough & cold',
      'Stomach & digestion',
      'Malaria',
      'Vitamins & supplements',
      'First aid',
      'Skin care',
      'Baby care',
      'Family planning',
      'Hygiene',
    ],
    categoriesSw: [
      'Maumivu na homa',
      'Antibiotiki',
      'Kikohozi na mafua',
      'Tumbo',
      'Malaria',
      'Vitamini',
      'Huduma ya kwanza',
      'Ngozi',
      'Watoto',
      'Uzazi wa mpango',
      'Usafi',
    ],
  ),
  BusinessTypeInfo(
    type: BusinessType.supermarket,
    label: 'Supermarket',
    description: 'Many items, barcodes and fast checkout',
    icon: Icons.local_grocery_store_outlined,
    categoriesEn: [
      'Beverages',
      'Snacks & sweets',
      'Bakery',
      'Dairy & eggs',
      'Rice, flour & grains',
      'Cooking oil & spices',
      'Fruits & vegetables',
      'Frozen food',
      'Toiletries',
      'Cleaning & household',
      'Baby products',
      'Stationery',
    ],
    categoriesSw: [
      'Vinywaji',
      'Vitafunwa na pipi',
      'Mikate',
      'Maziwa na mayai',
      'Mchele, unga na nafaka',
      'Mafuta na viungo',
      'Matunda na mboga',
      'Vyakula vilivyogandishwa',
      'Vifaa vya usafi wa mwili',
      'Usafi wa nyumbani',
      'Bidhaa za watoto',
      'Vifaa vya ofisi',
    ],
  ),
  BusinessTypeInfo(
    type: BusinessType.hardware,
    label: 'Hardware store',
    description: 'Building materials, tools and credit customers',
    icon: Icons.construction_outlined,
    categoriesEn: [
      'Cement & building',
      'Roofing',
      'Timber',
      'Plumbing',
      'Electrical',
      'Paint & finishing',
      'Tools',
      'Nails, screws & fasteners',
      'Locks & hinges',
      'Tiles',
      'Steel & wire',
    ],
    categoriesSw: [
      'Saruji na ujenzi',
      'Mabati',
      'Mbao',
      'Mabomba',
      'Umeme',
      'Rangi',
      'Vifaa vya kazi',
      'Misumari na screws',
      'Kufuli na bawaba',
      'Vigae',
      'Chuma na waya',
    ],
  ),
  BusinessTypeInfo(
    type: BusinessType.general,
    label: 'General shop (duka)',
    description: 'Any other kind of shop',
    icon: Icons.storefront_outlined,
    categoriesEn: [
      'Food & drinks',
      'Household',
      'Personal care',
      'Phone & airtime',
      'Other',
    ],
    categoriesSw: [
      'Chakula na vinywaji',
      'Vifaa vya nyumbani',
      'Vifaa vya mwili',
      'Simu na vocha',
      'Nyingine',
    ],
  ),
];

BusinessTypeInfo businessInfo(BusinessType t) =>
    kBusinessTypes.firstWhere((i) => i.type == t);

BusinessType? businessTypeFromKey(String? key) {
  for (final t in BusinessType.values) {
    if (t.name == key) return t;
  }
  return null;
}

extension BusinessTypeRules on BusinessType {
  /// Shops whose stock goes off: the home screen gets an Expiry shortcut.
  bool get tracksExpiry => this == BusinessType.pharmacy || this == BusinessType.supermarket;
}