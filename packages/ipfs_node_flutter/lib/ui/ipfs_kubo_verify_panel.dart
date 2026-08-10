import 'package:flutter/material.dart';

typedef IpfsKuboVerifier = Future<String> Function(String cid);

class IpfsKuboVerifyPanel extends StatefulWidget {
  const IpfsKuboVerifyPanel({super.key, this.onVerify, this.initialCid});

  final IpfsKuboVerifier? onVerify;
  final String? initialCid;

  @override
  State<IpfsKuboVerifyPanel> createState() => _IpfsKuboVerifyPanelState();
}

class _IpfsKuboVerifyPanelState extends State<IpfsKuboVerifyPanel> {
  late final TextEditingController _cid =
      TextEditingController(text: widget.initialCid);
  String? _result;
  bool _loading = false;

  Future<void> _verify() async {
    final verifier = widget.onVerify;
    if (verifier == null || _cid.text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await verifier(_cid.text);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _result = '验证失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('外部 Kubo 验证', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
                controller: _cid,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'CID')),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: widget.onVerify == null || _loading ? null : _verify,
                child: const Text('使用 Kubo 验证')),
            if (widget.onVerify == null) const Text('当前平台不支持本机 Kubo 验证'),
            if (_loading) const LinearProgressIndicator(),
            if (_result != null) SelectableText(_result!),
          ]),
        ),
      );
}
