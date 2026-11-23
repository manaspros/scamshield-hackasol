import 'package:flutter/material.dart';

/// Pushes [page] under a standard app bar titled [title]; resolves when the user comes back.
Future<void> pushTitled(BuildContext context, String title, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: page),
    ));
