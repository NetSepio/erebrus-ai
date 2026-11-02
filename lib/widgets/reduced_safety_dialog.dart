import 'package:flutter/material.dart';

import '../data/catalog_entry.dart';

/// Asks before downloading a reduced-safety (uncensored) catalog build.
///
/// Returns true only when the user explicitly accepts; entries with normal
/// alignment pass through without a prompt.
Future<bool> confirmReducedSafetyDownload(
  BuildContext context,
  CatalogEntry entry,
) async {
  if (!entry.reducedSafety) return true;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Download ${entry.name}?'),
      content: Text(
        entry.safetyNotes.isNotEmpty
            ? entry.safetyNotes
            : 'This community build has reduced safety alignment and may '
                  'produce content an aligned model would refuse.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('I UNDERSTAND'),
        ),
      ],
    ),
  );
  return accepted == true;
}
