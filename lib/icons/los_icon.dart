import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LosIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const LosIcon({
    super.key,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color ?? Colors.black;
    return SvgPicture.asset(
      'assets/icons/los_elevation.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
    );
  }
}
