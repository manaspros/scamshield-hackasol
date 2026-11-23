import 'package:flutter/material.dart';

import '../widgets/shell_bar.dart';

/// Pushes [page] under the shell bar titled [title]; resolves when the user comes back.
Future<void> pushTitled(BuildContext context, String title, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: shellBar(titleText: title), body: page),
    ));
