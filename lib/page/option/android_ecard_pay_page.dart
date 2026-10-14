import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../design/persistent_headers.dart';
import '../../worker/ecard_widget_messenger.dart';

class AndroidECardPayPage extends StatefulWidget {
  const AndroidECardPayPage({super.key});

  @override
  State<AndroidECardPayPage> createState() => _AndroidECardPayPageState();
}

class _AndroidECardPayPageState extends State<AndroidECardPayPage> {
  bool _loading = false;
  String? _barcode;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    ECardWidgetMessenger.accountGeneration.addListener(_accountChanged);
    _refresh();
  }

  void _accountChanged() {
    _request++;
    setState(() {
      _loading = false;
      _barcode = null;
      _error = '账号已切换，请重新打开付款码';
    });
  }

  @override
  void dispose() {
    ECardWidgetMessenger.accountGeneration.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _barcode = null;
      _error = null;
    });
    String? barcode;
    String? error;
    try {
      barcode = await ECardWidgetMessenger.getBarcode();
      if (barcode.isEmpty) error = '付款码加载失败，请重试';
    } on PlatformException catch (e) {
      error = e.message ?? '付款码加载失败，请重试';
    } catch (_) {
      error = '付款码加载失败，请重试';
    }
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _barcode = error == null ? barcode : null;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        child: SafeArea(
          child: CustomScrollView(slivers: [
            const LitechronSliverTextHeader(subtitle: '付款码'),
            SliverFillRemaining(
              child: Column(children: [
                const Spacer(flex: 4),
                if (_loading)
                  const CupertinoActivityIndicator()
                else if (_barcode != null)
                  GestureDetector(
                    onTap: _refresh,
                    child: Container(
                      width: 200,
                      height: 200,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: QrImageView(data: _barcode!, size: 200),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(_loading ? '加载中...' : _error ?? '付款码：$_barcode'),
                const SizedBox(height: 30),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  color: CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular(20),
                  onPressed: _loading ? null : _refresh,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.refresh,
                        size: 18, color: CupertinoColors.white),
                    SizedBox(width: 8),
                    Text('刷新二维码',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: CupertinoColors.white)),
                  ]),
                ),
                const Spacer(flex: 6),
              ]),
            ),
          ]),
        ),
      );
}
