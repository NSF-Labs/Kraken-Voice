import 'package:flutter/material.dart';
import '../design/tokens.dart';

class KrakenSearchDelegate extends SearchDelegate<String?> {
  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: KrakenColors.surfaceElevated,
        iconTheme: const IconThemeData(color: KrakenColors.textPrimary),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: KrakenText.bodyLg(color: KrakenColors.textMuted),
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: KrakenText.bodyLg(color: KrakenColors.textPrimary),
      ),
      scaffoldBackgroundColor: KrakenColors.bg,
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: KrakenColors.textSecondary),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: KrakenColors.textSecondary),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildBody();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (query.isEmpty) {
      return Center(
        child: Text(
          'Search libraries, activity, and settings...',
          style: KrakenText.bodyLg(color: KrakenColors.textMuted),
        ),
      );
    }

    return Center(
      child: Text(
        'No results found for "$query"',
        style: KrakenText.bodyLg(color: KrakenColors.textMuted),
      ),
    );
  }
}
