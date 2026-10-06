import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/accounts.dart';
import '../accounts/game_sources.dart' show GameSpeed;
import '../home/speed_filter.dart';
import '../puzzles/generator_banner.dart';
import '../puzzles/puzzle_store.dart';
import '../settings/settings_page.dart';
import '../ads/ad_banner.dart';
import 'skill_stats.dart';

/// The user's skill profile as a radar ("web") over their analyzed games.
class SkillsPage extends ConsumerStatefulWidget {
  const SkillsPage({super.key});

  @override
  ConsumerState<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends ConsumerState<SkillsPage> {
  Skill? _expanded;

  /// The profiles for the last stats and speed seen: they go over every
  /// analyzed game, and this page rebuilds whenever the library changes.
  Object? _profilesFor;
  GameSpeed? _profilesSpeed;
  (SkillProfile, TimeProfile)? _profiles;

  (SkillProfile, TimeProfile) _profilesOf(Map<String, GameSkillStats> all, GameSpeed? speed, List<GameSkillStats> stats) {
    final cached = _profiles;
    if (cached != null && identical(all, _profilesFor) && speed == _profilesSpeed) return cached;
    _profilesFor = all;
    _profilesSpeed = speed;
    return _profiles = (SkillProfile.from(stats), TimeProfile.from(stats));
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final library = ref.watch(puzzleLibraryProvider);
    final generator = ref.watch(puzzleGeneratorProvider);
    final all = library.gameStats.values;
    final speed = ref.watch(speedFilterProvider);
    final stats = filterBySpeed(speed, all, (g) => g.speed);
    final shownSpeed = stats.length == all.length ? null : speed;
    final (profile, timeProfile) = _profilesOf(library.gameStats, speed, stats);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skill analysis'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(settingsRoute()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (generator.message != null) GeneratorBanner(state: generator),
            SpeedFilterBar(available: {for (final g in all) ?g.speed}),
            Expanded(
              child: profile.games == 0
                  ? _Empty(
                      connected: accounts.any,
                      running: generator.running,
                      onLoad: () => ref.read(puzzleGeneratorProvider.notifier).run(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        Text(
                          library.gameCountLabel,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) => Center(
                            child: SkillRadar(
                              profile: profile,
                              size: math.min(constraints.maxWidth, 360),
                              selected: _expanded,
                              onSelect: (skill) => setState(() => _expanded = skill),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _basisLine(profile, shownSpeed),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        for (final skill in Skill.values)
                          _SkillRow(
                            score: profile.scores[skill]!,
                            expanded: _expanded == skill,
                            onTap: () => setState(() => _expanded = _expanded == skill ? null : skill),
                          ),
                        const SizedBox(height: 24),
                        TimeSection(profile: timeProfile, speed: shownSpeed),
                        if (!generator.running) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton.icon(
                              onPressed: () => ref.read(puzzleGeneratorProvider.notifier).run(),
                              icon: const Icon(Icons.search),
                              label: const Text('Load more games'),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const AdBanner(),
          ],
        ),
      ),
    );
  }

  String _basisLine(SkillProfile profile, GameSpeed? speed) {
    String month(DateTime d) =>
        '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
    final range = profile.from == null
        ? ''
        : (month(profile.from!) == month(profile.to!)
            ? ' · ${month(profile.to!)}'
            : ' · ${month(profile.from!)} – ${month(profile.to!)}');
    final kind = speed == null ? '' : ' ${speed.label.toLowerCase()}';
    return 'Based on ${profile.games} analyzed$kind game${profile.games == 1 ? '' : 's'}$range';
  }
}

/// "Time per move": the overall average, then per opening, middlegame and
/// endgame, as bars against the slowest phase.
class TimeSection extends StatelessWidget {
  const TimeSection({super.key, required this.profile, this.speed});

  final TimeProfile profile;

  /// The speed filter in force, if any (times only compare within one).
  final GameSpeed? speed;

  static String format(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
    final m = seconds ~/ 60;
    final s = (seconds - m * 60).round();
    return '$m min ${s.toString().padLeft(2, '0')} s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final average = profile.average;
    final phases = {for (final p in GamePhase.values) p: profile.averageIn(p)};
    final slowest = phases.values.nonNulls.fold(0.0, math.max);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Time per move', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (average == null)
              Text(
                'Shown for games analyzed from now on: their clock times are downloaded with '
                'them. Load more games to see how long you think in the opening, middlegame '
                'and endgame.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(format(average), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                'on average over ${profile.totalMoves} moves in ${profile.games} '
                '${speed == null ? '' : '${speed!.label.toLowerCase()} '}game${profile.games == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final MapEntry(key: phase, value: seconds) in phases.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 92, child: Text(phase.label, style: theme.textTheme.bodyMedium)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 10,
                            value: seconds == null || slowest == 0 ? 0 : seconds / slowest,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          seconds == null ? '—' : format(seconds),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              if (speed == null && profile.games > 0)
                Text(
                  'Tip: pick a time control above; times from bullet and rapid games don\'t compare.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Five-axis radar of the skill scores, 0 at the centre, 100 at the rim.
/// Tap an axis to select it.
class SkillRadar extends StatefulWidget {
  const SkillRadar({
    super.key,
    required this.profile,
    required this.size,
    this.selected,
    this.onSelect,
  });

  final SkillProfile profile;
  final double size;
  final Skill? selected;
  final ValueChanged<Skill>? onSelect;

  @override
  State<SkillRadar> createState() => _SkillRadarState();
}

class _SkillRadarState extends State<SkillRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  /// The axis nearest to a tap, by angle from the centre.
  Skill _axisAt(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final angle = math.atan2(local.dy - c.dy, local.dx - c.dx);
    var best = Skill.values.first;
    var bestDiff = double.infinity;
    for (final (i, skill) in Skill.values.indexed) {
      final a = _axisAngle(i);
      final diff = (math.atan2(math.sin(angle - a), math.cos(angle - a))).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = skill;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scores = Skill.values.map((s) => widget.profile.scores[s]!).toList();
    return Semantics(
      label: 'Skill radar. ${scores.map((s) => '${s.skill.label} ${s.value?.round() ?? 'not enough data'}').join(', ')}',
      child: GestureDetector(
        onTapUp: widget.onSelect == null ? null : (d) => widget.onSelect!(_axisAt(d.localPosition)),
        child: AnimatedBuilder(
          animation: _grow,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _RadarPainter(
              scores: scores,
              progress: Curves.easeOutCubic.transform(_grow.value),
              selected: widget.selected,
              accent: theme.colorScheme.primary,
              grid: theme.colorScheme.outlineVariant,
              surface: theme.colorScheme.surface,
              labelStyle: theme.textTheme.labelLarge!.copyWith(color: theme.colorScheme.onSurfaceVariant),
              valueStyle: theme.textTheme.titleMedium!.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Axis i points up first, then clockwise.
double _axisAngle(int i) => -math.pi / 2 + i * 2 * math.pi / Skill.values.length;

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.scores,
    required this.progress,
    required this.selected,
    required this.accent,
    required this.grid,
    required this.surface,
    required this.labelStyle,
    required this.valueStyle,
  });

  final List<SkillScore> scores;
  final double progress;
  final Skill? selected;
  final Color accent;
  final Color grid;
  final Color surface;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Leave room around the web for the labels.
    final r = size.width / 2 - 58;
    final n = scores.length;
    Offset at(int i, double fraction) =>
        c + Offset(math.cos(_axisAngle(i)), math.sin(_axisAngle(i))) * r * fraction;

    // Recessive grid: rings at 25/50/75/100 and the spokes.
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final ring in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path()..moveTo(at(0, ring).dx, at(0, ring).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(at(i, ring).dx, at(i, ring).dy);
      }
      canvas.drawPath(path..close(), gridPaint);
    }
    for (var i = 0; i < n; i++) {
      final spoke = Paint()
        ..color = scores[i].skill == selected ? accent : grid.withValues(alpha: 0.55)
        ..strokeWidth = scores[i].skill == selected ? 2 : 1;
      canvas.drawLine(c, at(i, 1), spoke);
    }

    // The profile: missing scores sit at the centre (and are labelled "–").
    final points = [for (var i = 0; i < n; i++) at(i, (scores[i].value ?? 0) / 100 * progress)];
    final shape = Path()..addPolygon(points, true);
    canvas.drawPath(shape, Paint()..color = accent.withValues(alpha: 0.22));
    canvas.drawPath(
      shape,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < n; i++) {
      if (scores[i].value == null) continue;
      canvas.drawCircle(points[i], 6, Paint()..color = surface);
      canvas.drawCircle(points[i], 4, Paint()..color = accent);
    }

    // Labels outside the rim: name, then the score.
    for (var i = 0; i < n; i++) {
      final s = scores[i];
      final value = s.value == null ? '–' : '${s.value!.round()}';
      final text = TextPainter(
        text: TextSpan(children: [
          TextSpan(
            text: '${s.skill.label}\n',
            style: s.skill == selected ? labelStyle.copyWith(color: valueStyle.color) : labelStyle,
          ),
          TextSpan(text: value, style: valueStyle),
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 110);
      final anchor = at(i, 1) + Offset(math.cos(_axisAngle(i)), math.sin(_axisAngle(i))) * 12;
      final cos = math.cos(_axisAngle(i));
      final sin = math.sin(_axisAngle(i));
      // Push the label box away from the web on the side it sits.
      final dx = cos > 0.3 ? 0.0 : (cos < -0.3 ? -text.width : -text.width / 2);
      final dy = sin > 0.3 ? 0.0 : (sin < -0.3 ? -text.height : -text.height / 2);
      // Keep every label fully inside the chart.
      final topLeft = anchor + Offset(dx, dy);
      text.paint(
        canvas,
        Offset(
          topLeft.dx.clamp(0.0, math.max(0.0, size.width - text.width)),
          topLeft.dy.clamp(0.0, math.max(0.0, size.height - text.height)),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress || old.selected != selected || !listEquals(old.scores, scores) || old.accent != accent;
}

/// One skill: score, meter, evidence, and (expanded) what it measures.
class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.score, required this.expanded, required this.onTap});

  final SkillScore score;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = score.value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(score.skill.label, style: theme.textTheme.titleMedium)),
                Text(
                  value == null ? 'Not enough data' : '${value.round()}',
                  style: value == null
                      ? theme.textTheme.bodySmall
                      : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more, color: theme.colorScheme.outline),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value ?? 0) / 100,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(score.basis, style: theme.textTheme.bodySmall),
            if (expanded) ...[
              const SizedBox(height: 6),
              Text(score.skill.description, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.connected, required this.running, required this.onLoad});

  final bool connected;
  final bool running;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String text, Widget? action) = running
        ? ('Your skill profile appears here as your games are analyzed.', null)
        : connected
            ? (
                'Load your games to see how strong you are at tactics, openings, the '
                    'middlegame, endgames and positional play.',
                FilledButton.icon(
                  onPressed: onLoad,
                  icon: const Icon(Icons.search),
                  label: const Text('Load my games'),
                ),
              )
            : (
                'Connect your Lichess or Chess.com account to see your skill profile.',
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(settingsRoute()),
                  icon: const Icon(Icons.link),
                  label: const Text('Connect an account'),
                ),
              );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }
}
