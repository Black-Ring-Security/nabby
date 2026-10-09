import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

BuildContext? get _ctx => navigatorKey.currentContext;

void toast(String message) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

class PromptResult {
  PromptResult(this.value, this.remember);
  final String value;
  final bool remember;
}

Future<PromptResult?> promptSecret({
  required String title,
  String? message,
  String label = 'Password',
  bool obscure = true,
  bool offerRemember = true,
  String initial = '',
}) async {
  final ctx = _ctx;
  if (ctx == null) return null;
  final controller = TextEditingController(text: initial);
  var remember = false;
  var hidden = obscure;
  return showDialog<PromptResult>(
    context: ctx,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null && message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(message),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: hidden,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: label,
                suffixIcon: obscure
                    ? IconButton(
                        icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => hidden = !hidden),
                      )
                    : null,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, PromptResult(v, remember)),
            ),
            if (offerRemember)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: const Text('Remember'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, PromptResult(controller.text, remember)),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

enum HostKeyDecision { reject, acceptOnce, acceptAndSave }

Future<HostKeyDecision> confirmHostKey({
  required String host,
  required String type,
  required String fingerprint,
  String? previous,
}) async {
  final ctx = _ctx;
  if (ctx == null) return HostKeyDecision.reject;
  final changed = previous != null;
  final result = await showDialog<HostKeyDecision>(
    context: ctx,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(changed ? Icons.gpp_bad : Icons.verified_user,
          color: changed ? Colors.redAccent : null, size: 36),
      title: Text(changed ? 'Host key has changed!' : 'Unknown host key'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (changed)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'The host key for this server differs from the one saved before. '
                  'Someone could be intercepting your connection (man-in-the-middle), '
                  'or the server was reinstalled. Only continue if you know why it changed.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            Text('Host: $host'),
            const SizedBox(height: 8),
            Text('Key type: $type'),
            const SizedBox(height: 8),
            const Text('Fingerprint:'),
            SelectableText(fingerprint,
                style: const TextStyle(fontFamily: 'SourceCodePro', fontSize: 12)),
            if (changed) ...[
              const SizedBox(height: 8),
              const Text('Previously saved:'),
              SelectableText(previous,
                  style: const TextStyle(fontFamily: 'SourceCodePro', fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, HostKeyDecision.reject),
            child: const Text('Reject')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, HostKeyDecision.acceptOnce),
            child: const Text('Accept once')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, HostKeyDecision.acceptAndSave),
            child: const Text('Accept & save')),
      ],
    ),
  );
  return result ?? HostKeyDecision.reject;
}

Future<List<String>?> keyboardInteractive(SSHUserInfoRequest request) async {
  final ctx = _ctx;
  if (ctx == null) return null;
  final controllers = [for (final _ in request.prompts) TextEditingController()];
  return showDialog<List<String>>(
    context: ctx,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(request.name.isNotEmpty ? request.name : 'Authentication'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request.instruction.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(request.instruction),
              ),
            for (var i = 0; i < request.prompts.length; i++)
              TextField(
                controller: controllers[i],
                autofocus: i == 0,
                obscureText: !request.prompts[i].echo,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: request.prompts[i].promptText.trim()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controllers.map((c) => c.text).toList()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(String title, String message,
    {String ok = 'OK', bool destructive = false}) async {
  final ctx = _ctx;
  if (ctx == null) return false;
  final r = await showDialog<bool>(
    context: ctx,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Colors.redAccent)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(String title,
    {String label = '', String initial = '', String ok = 'OK'}) async {
  final ctx = _ctx;
  if (ctx == null) return null;
  final c = TextEditingController(text: initial);
  c.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: ctx,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        autocorrect: false,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
      ],
    ),
  );
}
