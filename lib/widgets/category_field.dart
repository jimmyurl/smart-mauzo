import 'package:flutter/material.dart';

/// Text field with suggestions from existing categories. The user can pick one
/// or simply type a brand-new category. Use it in AddProductScreen and in the
/// "change category" dialog.
class CategoryField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> options;

  const CategoryField({super.key, required this.controller, required this.options});

  @override
  State<CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends State<CategoryField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          return widget.options.where((o) => q.isEmpty || o.toLowerCase().contains(q));
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category',
            hintText: 'Pick one or type a new category',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.category_outlined),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 220, maxWidth: box.maxWidth),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}