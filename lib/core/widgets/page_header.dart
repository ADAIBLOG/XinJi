import 'package:flutter/material.dart';
import 'package:xinji/app/theme/app_tokens.dart';

/// 大标题页头：作为滚动内容的首项，跟随页面滑动（替代固定 AppBar 标题）。
/// [actions] 为右侧操作按钮，同样随内容滚动。
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.1,
                letterSpacing: -0.8,
                color: context.colors.onSurface,
              ),
            ),
          ),
          ...?actions,
        ],
      ),
    );
  }
}
