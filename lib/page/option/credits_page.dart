import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:celechron/design/persistent_headers.dart';

class CreditsPage extends StatelessWidget {
  final String version;
  const CreditsPage({required this.version, super.key});

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondaryLabel, context),
    );

    return CupertinoPageScaffold(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            const LitechronSliverTextHeader(subtitle: '关于'),
            SliverToBoxAdapter(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 64),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/logo.svg',
                        height: 108,
                        width: 108,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Litechron',
                            style: TextStyle(fontSize: 32),
                          ),
                          Text(
                            '$version 版本',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    '开发',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'bno3bno3',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '本项目基于 Celechron 二次开发，遵循 GPLv3 协议开源',
                    textAlign: TextAlign.center,
                    style: secondaryStyle,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
