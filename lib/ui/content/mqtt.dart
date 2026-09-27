import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/mqtt/mqtt_packet.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/content/web_socket.dart';
import 'package:proxypin/utils/lang.dart';

/// One MQTT connection is shown as a directed stream of control packets.
class MqttMessages extends StatelessWidget {
  final ValueWrap<HttpRequest> request;

  const MqttMessages(this.request, {super.key});

  @override
  Widget build(BuildContext context) {
    final messages = request.get()?.messages;
    if (messages == null) return const SizedBox();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 15),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        MqttPacket? packet;
        try {
          packet = MqttPacket.fromBytes(
            Uint8List.fromList(message.payloadData),
            message.isFromClient,
          );
        } on FormatException {
          // History files can contain older or truncated message data.
        }
        final fromClient = message.isFromClient;
        final color = fromClient ? Colors.green : Colors.blue;
        final details = <String>[
          if (packet?.topic != null) 'Topic: ${packet!.topic}',
          if (packet?.packetId != null) 'ID: ${packet!.packetId}',
          if (packet?.connackCode != null) 'CONNACK code: ${packet!.connackCode}',
          getPackage(message.payloadLength),
        ];
        final avatar = CircleAvatar(
          backgroundColor: color,
          child: Text(fromClient ? 'C' : 'S', style: const TextStyle(fontSize: 18, color: Colors.white)),
        );
        final preview = IconButton(
          tooltip: 'Preview raw MQTT packet',
          onPressed: () => showDialog(
            context: context,
            builder: (context) => PacketPreviewDialog(bytes: message.payloadData),
          ),
          icon: Icon(Icons.expand_more, color: ColorScheme.of(context).primary),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            mainAxisAlignment: fromClient ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (fromClient) avatar,
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: fromClient ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                  children: [
                    Text(message.time.format(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!fromClient) preview,
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.26),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(packet?.typeName ?? 'Invalid MQTT packet',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(details.join(' · ')),
                              ],
                            ),
                          ),
                        ),
                        if (fromClient) preview,
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!fromClient) avatar,
            ],
          ),
        );
      },
    );
  }
}
