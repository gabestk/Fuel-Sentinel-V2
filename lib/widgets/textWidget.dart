import 'package:flutter/material.dart';

class Textdata extends StatelessWidget {
  final String? freq;
  final String tipo;
  final String? texto;
  const Textdata({
    super.key,
    this.freq,
    required this.tipo,
    this.texto,
  });

  @override
  Widget build(BuildContext context) {
    final corTexto = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
        
          Text(
            tipo,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: corTexto,
                decoration: TextDecoration.none),
          ),
          Text(
            texto ?? 'NULL',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: corTexto,
                decoration: TextDecoration.none),
          ),
        ],
      ),
    );
  }
}
