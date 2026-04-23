import 'package:flutter/material.dart';
import '../design/tokens.dart';
import 'activity_panel.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        title: Text('Activity', style: KrakenText.displayMd()),
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: const CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: KrakenSpacing.s6,
              vertical: KrakenSpacing.s4,
            ),
            sliver: SliverToBoxAdapter(
              child: ActivityPanel(
                limit: 50,
                category: 'user_visible',
                compact: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
