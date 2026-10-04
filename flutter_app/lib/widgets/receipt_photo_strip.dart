import 'dart:io';
import 'package:flutter/material.dart';

/// Horizontal photo thumbnail strip for multi-page receipts with page numbers and delete actions.
class ReceiptPhotoStrip extends StatelessWidget {
  final List<File> imageFiles;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const ReceiptPhotoStrip({
    super.key,
    required this.imageFiles,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    if (imageFiles.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageFiles.length + 1,
            separatorBuilder: (ctx, _) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              if (i == imageFiles.length) {
                return InkWell(
                  onTap: onAddPhoto,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 85,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: Color(0xFF00C896), size: 26),
                        SizedBox(height: 4),
                        Text('Add Page', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                      ],
                    ),
                  ),
                );
              }

              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      imageFiles[i],
                      width: 85,
                      height: 110,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'P${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemovePhoto(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
