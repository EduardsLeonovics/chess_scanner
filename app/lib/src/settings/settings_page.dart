import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Piece, Side;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../community/blocked_accounts_page.dart';
import '../privacy/privacy_section.dart';
import 'accounts_section.dart';
import 'appearance.dart';
import 'color_picker.dart';
import 'data_sections.dart';

/// Slides the settings in from the right, where the gear button is.
Route<void> settingsRoute() {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => const SettingsPage(),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

const _ink = Color(0xFF29313B);
const _muted = Color(0xFF8A919B);
const _line = Color(0xFFE6E8EB);
const _selectedFill = Color(0xFFEEF0F3);

/// A position with every piece type, for the live preview.
const _previewFen = 'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    final assets = ref.watch(pieceAssetsProvider).value ?? appearance.pieceSet.assets;
    final light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _ink, brightness: Brightness.light),
      scaffoldBackgroundColor: Colors.white,
    );

    Future<void> pickColor(String title, Color initial, void Function(Color) apply) async {
      final color = await showColorPicker(context, title: title, initial: initial);
      if (color != null) apply(color);
    }

    return Theme(
      data: light,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: const Text('Settings'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(
                'Accounts',
                style: light.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              const AccountsSection(),
              const SizedBox(height: 32),
              Text(
                'Customization',
                style: light.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: StaticChessboard(
                    size: math.min(constraints.maxWidth, 280),
                    orientation: Side.white,
                    fen: _previewFen,
                    settings: StaticChessboardSettings(
                      colorScheme: appearance.colorScheme,
                      pieceAssets: assets,
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      enableCoordinates: true,
                    ),
                  ),
                ),
              ),
              _Section(
                icon: Icons.texture,
                title: 'Board theme',
                child: SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: boardThemes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final theme = boardThemes[i];
                      return _Choice(
                        label: theme.label,
                        selected: appearance.boardThemeId == theme.id,
                        onTap: () => notifier.setBoardTheme(theme.id),
                        child: StaticChessboard(
                          size: 56,
                          orientation: Side.white,
                          fen: '8/8/8/8/8/8/8/8',
                          settings: StaticChessboardSettings(
                            colorScheme: theme.scheme,
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              _Section(
                icon: Icons.extension_outlined,
                title: 'Pieces',
                child: SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: pieceStyles.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final (set, label) = pieceStyles[i];
                      return _Choice(
                        label: label,
                        selected: appearance.pieceSet == set,
                        onTap: () => notifier.setPieceSet(set),
                        child: SizedBox.square(
                          dimension: 56,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image(image: set.assets[Piece.whiteKnight.kind]!, width: 28),
                              Image(image: set.assets[Piece.blackKing.kind]!, width: 28),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              _Section(
                icon: Icons.palette_outlined,
                title: 'Board color',
                child: Row(
                  children: [
                    _ColorButton(
                      label: 'Light squares',
                      color: appearance.colorScheme.lightSquare,
                      onTap: () => pickColor(
                        'Light squares',
                        appearance.colorScheme.lightSquare,
                        (c) => notifier.setBoardColors(light: c),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ColorButton(
                      label: 'Dark squares',
                      color: appearance.colorScheme.darkSquare,
                      onTap: () => pickColor(
                        'Dark squares',
                        appearance.colorScheme.darkSquare,
                        (c) => notifier.setBoardColors(dark: c),
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                icon: Icons.format_color_fill,
                title: 'Piece color',
                child: Row(
                  children: [
                    _ColorButton(
                      label: 'White pieces',
                      color: appearance.whitePieces,
                      onTap: () => pickColor(
                        'White pieces',
                        appearance.whitePieces,
                        (c) => notifier.setPieceColors(white: c),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ColorButton(
                      label: 'Black pieces',
                      color: appearance.blackPieces,
                      onTap: () => pickColor(
                        'Black pieces',
                        appearance.blackPieces,
                        (c) => notifier.setPieceColors(black: c),
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                icon: Icons.blur_circular,
                title: 'Piece outline',
                child: Row(
                  children: [
                    _ColorButton(
                      label: 'White pieces',
                      color: appearance.effectiveWhiteOutline,
                      onTap: () => pickColor(
                        'White piece outline',
                        appearance.effectiveWhiteOutline ?? const Color(0xFF000000),
                        notifier.setWhiteOutline,
                      ),
                      onClear: appearance.effectiveWhiteOutline == null
                          ? null
                          : () => notifier.setWhiteOutline(Appearance.noOutline),
                    ),
                    const SizedBox(width: 10),
                    _ColorButton(
                      label: 'Black pieces',
                      color: appearance.effectiveBlackOutline,
                      onTap: () => pickColor(
                        'Black piece outline',
                        appearance.effectiveBlackOutline ?? const Color(0xFFFFFFFF),
                        notifier.setBlackOutline,
                      ),
                      onClear: appearance.effectiveBlackOutline == null
                          ? null
                          : () => notifier.setBlackOutline(Appearance.noOutline),
                    ),
                  ],
                ),
              ),
              _Section(
                icon: Icons.wallpaper_outlined,
                title: 'App background',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final color in Appearance.backgroundPresets)
                      _Swatch(
                        color: color,
                        selected: appearance.background == color,
                        onTap: () => notifier.setBackground(color),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => pickColor('App background', appearance.background, notifier.setBackground),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Appearance.backgroundPresets.contains(appearance.background) ? _line : _ink,
                          width: Appearance.backgroundPresets.contains(appearance.background) ? 1 : 2,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.colorize, size: 18, color: _ink),
                      label: const Text('Custom', style: TextStyle(color: _ink)),
                    ),
                  ],
                ),
              ),
              _Section(
                icon: Icons.volume_up_outlined,
                title: 'Sound',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Move sounds', style: TextStyle(color: _ink)),
                  subtitle: const Text('Moves, captures, castling and checks'),
                  value: appearance.moveSounds,
                  onChanged: notifier.setMoveSounds,
                ),
              ),
              _Section(
                icon: Icons.north_east,
                title: 'Analysis board',
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show best move arrow', style: TextStyle(color: _ink)),
                  subtitle: const Text('The green arrow for Stockfish\'s top move'),
                  value: appearance.showBestMoveArrow,
                  onChanged: (on) => notifier.setShowBestMoveArrow(on ?? true),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton.icon(
                  onPressed: appearance == const Appearance() ? null : notifier.reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset customization to defaults'),
                ),
              ),
              const SettingsHeading('Community'),
              const CommunitySafetySection(),
              const SettingsHeading('Puzzles'),
              const PuzzleDataSection(),
              const SettingsHeading('Privacy'),
              const PrivacySection(),
              const SettingsHeading('Crash reports'),
              const CrashReportsSection(),
              const SettingsHeading('About'),
              const AboutSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _muted, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A selectable tile with a picture and a caption.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 76,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? _selectedFill : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _ink : _line, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              child,
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round colour swatch, ringed when selected.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Background colour',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? _ink : _line, width: selected ? 2 : 1),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33000000)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.label, required this.color, required this.onTap, this.onClear});

  final String label;

  /// Null shows a crossed-out swatch ("none").
  final Color? color;
  final VoidCallback onTap;

  /// Shows an × that clears the colour.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x33000000)),
              ),
              child: color == null ? const Icon(Icons.block, size: 18, color: _muted) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(color: _ink), overflow: TextOverflow.ellipsis),
            ),
            if (onClear != null)
              InkWell(
                onTap: onClear,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 18, color: _muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
