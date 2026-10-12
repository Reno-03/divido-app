// lib/widgets/dashboard_ui.dart
//
// Presentation-only widgets for DashboardPage. No business logic here.
// Palette is unchanged from the app: navy 0xFF171A3F, surface 0xFF3C3C63.

import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

const Color kDashNavy = Color(0xFF171A3F);
const Color kDashSurface = Color(0xFF3C3C63);
const Color kDashGlass = Color(0x0FFFFFFF);      // white at ~6% alpha
const Color kDashHeroGlass = Color(0x1AFFFFFF);  // white at ~10% alpha
const Color kDashPositive = Colors.greenAccent;
const Color kDashNegative = Colors.redAccent;

final NumberFormat _fmt = NumberFormat('#,##0.00', 'en_US');

String dashMoney(double v, {bool trimZeros = false}) {
  final s = _fmt.format(v);
  return trimZeros ? s.replaceAll(RegExp(r'\.00$'), '') : s;
}

Color dashParseColor(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) {
    return Colors.grey;
  }
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? Colors.grey : Color(0xFF000000 | v);
}

// ---------------------------------------------------------------- primitives

/// "₱" in a smaller, softer weight so the number carries the weight.
class DashAmount extends StatelessWidget {
  const DashAmount(
    this.value, {
    super.key,
    this.size = 20,
    this.color = Colors.white,
    this.weight = FontWeight.w700,
    this.trimZeros = false,
    this.animate = false,
  });

  final double value;
  final double size;
  final Color color;
  final FontWeight weight;
  final bool trimZeros;
  final bool animate;

  Widget _buildText(double v) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '₱ ',
            style: TextStyle(
              fontSize: size * 0.6,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          TextSpan(
            text: dashMoney(v, trimZeros: trimZeros),
            style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              color: color,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.of(context).disableAnimations) {
      return _buildText(value);
    }
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => _buildText(v),
      ),
    );
  }
}

class DashAvatar extends StatelessWidget {
  const DashAvatar({super.key, required this.size, this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.person, size: size * 0.55, color: kDashSurface);
    final hasUrl = url != null && url!.isNotEmpty;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2;
    final px = (size * dpr).round();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              memCacheWidth: px,
              memCacheHeight: px,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (_, _, _) => fallback,
              placeholder: (_, _) => fallback,
            )
          : fallback,
    );
  }
}

class DashSkeleton extends StatelessWidget {
  const DashSkeleton({super.key, required this.height, this.radius = 20});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF23264F),
      highlightColor: const Color(0xFF30346A),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sections

/// Title sits outside the surface; rows inside are separated by hairlines
/// instead of being boxed one by one.
class DashSection extends StatelessWidget {
  const DashSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          actionLabel!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: soft,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: soft),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kDashGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ],
    );
  }
}

class DashRows extends StatelessWidget {
  const DashRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          children[i],
        ],
      ],
    );
  }
}

class DashEmpty extends StatelessWidget {
  const DashEmpty(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- hero

/// The one standout element: your overall position at a glance.
class DashHeroBalance extends StatelessWidget {
  const DashHeroBalance({
    super.key,
    required this.owedToYou,
    required this.youOwe,
    required this.onSettle,
    this.actionLabel,
  });

  final double owedToYou;
  final double youOwe;
  final VoidCallback onSettle;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final net = owedToYou - youOwe;
    final settled = owedToYou < 0.01 && youOwe < 0.01;
    final even = !settled && net.abs() < 0.01;

    final Color accent = (settled || even)
        ? Colors.white70
        : (net > 0 ? kDashPositive : kDashNegative);

    final String label;
    final String hint;
    final IconData icon;
    if (settled) {
      label = 'All settled';
      hint = 'No pending balances in this group';
      icon = Icons.check_rounded;
    } else if (even) {
      label = 'Even overall';
      hint = 'Check the balances below';
      icon = Icons.swap_vert_rounded;
    } else if (net > 0) {
      label = "You're owed";
      hint = 'Nudge them to settle';
      icon = Icons.arrow_downward_rounded;
    } else {
      label = 'You owe';
      hint = 'You need to settle';
      icon = Icons.arrow_upward_rounded;
    }

    final tint = (settled || even) ? 0.0 : 0.14;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: tint), kDashHeroGlass),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: accent.withValues(alpha: (settled || even) ? 0.12 : 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.2),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DashAmount(
              net.abs(),
              size: 40,
              weight: FontWeight.w800,
              animate: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: accent,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: kDashNavy.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroLeg(
                    label: 'Owed to you',
                    value: owedToYou,
                    color: kDashPositive,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _HeroLeg(
                    label: 'You owe',
                    value: youOwe,
                    color: kDashNegative,
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSettle,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kDashNavy,
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      actionLabel ?? (youOwe >= 0.01 ? 'Settle up' : 'View balances'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroLeg extends StatelessWidget {
  const _HeroLeg({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = value < 0.01 ? Colors.white54 : color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: DashAmount(value, size: 20),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- stats

class DashStatTile extends StatelessWidget {
  const DashStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.changePct,
  });

  final IconData icon;
  final String label;
  final double value;
  final double? changePct;

  @override
  Widget build(BuildContext context) {
    final isNew = changePct == null;
    final pct = changePct ?? 0;
    final up = pct > 0;
    final flat = pct == 0 && !isNew;
    final trendColor = isNew
        ? Colors.white70
        : (flat ? Colors.white70 : (up ? kDashPositive : kDashNegative));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDashGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DashAmount(value, size: 22, animate: true),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                isNew
                    ? Icons.fiber_new_rounded
                    : (flat
                          ? Icons.trending_flat_rounded
                          : (up
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded)),
                size: 16,
                color: trendColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isNew
                      ? 'New this week'
                      : (flat
                            ? 'Same as last week'
                            : '${pct.abs().toStringAsFixed(0)}% vs last week'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: trendColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- rows

class _OwnerLine extends StatelessWidget {
  const _OwnerLine({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DashAvatar(size: 16, url: avatarUrl),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.white60),
          ),
        ),
      ],
    );
  }
}

class DashBalanceRow extends StatelessWidget {
  const DashBalanceRow({
    super.key,
    required this.name,
    required this.net,
    this.avatarUrl,
  });

  final String name;
  final double net;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final settled = net.abs() < 0.01;
    final theyOweMe = net > 0;
    final color = settled
        ? Colors.white70
        : (theyOweMe ? kDashPositive : kDashNegative);
    final caption = settled ? 'settled' : (theyOweMe ? 'owes you' : 'you owe');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          DashAvatar(size: 42, url: avatarUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DashAmount(settled ? 0 : net.abs(), size: 18, color: color),
              const SizedBox(height: 2),
              Text(caption, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class DashExpenseRow extends StatelessWidget {
  const DashExpenseRow({
    super.key,
    required this.title,
    required this.ownerName,
    required this.total,
    this.avatarUrl,
  });

  final String title;
  final String ownerName;
  final double total;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                _OwnerLine(name: ownerName, avatarUrl: avatarUrl),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DashAmount(total, size: 20, trimZeros: true),
        ],
      ),
    );
  }
}

class DashTopExpenseRow extends StatelessWidget {
  const DashTopExpenseRow({
    super.key,
    required this.rank,
    required this.title,
    required this.ownerName,
    required this.ownAmt,
    required this.total,
    this.avatarUrl,
  });

  final int rank;
  final String title;
  final String ownerName;
  final double ownAmt;
  final double total;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                _OwnerLine(name: ownerName, avatarUrl: avatarUrl),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DashAmount(ownAmt, size: 20, trimZeros: true),
              const SizedBox(height: 2),
              Text(
                'of ₱ ${dashMoney(total)}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The member's color is shown as a ring around the avatar.
class DashMemberRow extends StatelessWidget {
  const DashMemberRow({
    super.key,
    required this.name,
    required this.isCreator,
    this.avatarUrl,
    this.colorHex,
  });

  final String name;
  final bool isCreator;
  final String? avatarUrl;
  final String? colorHex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: dashParseColor(colorHex), width: 2),
            ),
            child: DashAvatar(size: 38, url: avatarUrl),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (isCreator)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Group creator',
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}