import 'package:flutter/material.dart';

class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Items')),
    body: ListView.builder(
      key: const ValueKey('items-list'),
      itemCount: 100,
      itemBuilder: (_, i) => ListTile(
        key: ValueKey('item-$i'),
        title: Text('Item $i'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ItemDetailsPage(index: i)),
        ),
      ),
    ),
  );
}

class ItemDetailsPage extends StatefulWidget {
  const ItemDetailsPage({super.key, required this.index});

  final int index;

  @override
  State<ItemDetailsPage> createState() => _ItemDetailsPageState();
}

class _ItemDetailsPageState extends State<ItemDetailsPage> {
  bool _favorite = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Item ${widget.index} details')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Details for Item ${widget.index}'),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const ValueKey('favorite'),
          title: const Text('Favorite'),
          value: _favorite,
          onChanged: (value) => setState(() => _favorite = value),
        ),
        Text(
          _favorite ? 'Added to favorites' : 'Not a favorite',
          key: const ValueKey('favorite-status'),
        ),
      ],
    ),
  );
}
