import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'models.dart';

const _pieceSetsPath = 'assets/piece_sets';

/// A piece set and its corresponding piece assets.
enum PieceSet {
  cburnett('Colin M.L. Burnett', PieceSet.cburnettAssets),
  merida('Merida', PieceSet.meridaAssets),
  pirouetti('Pirouetti', PieceSet.pirouettiAssets),
  chessnut('Chessnut', PieceSet.chessnutAssets),
  fantasy('Fantasy', PieceSet.fantasyAssets),
  spatial('Spatial', PieceSet.spatialAssets),
  celtic('Celtic', PieceSet.celticAssets),
  pixel('Pixel', PieceSet.pixelAssets),
  firi('Firi', PieceSet.firiAssets),
  rhosgfx('RhosGFX', PieceSet.rhosgfxAssets),
  mpchess('Mpchess', PieceSet.mpchessAssets),
  shapes('Shapes', PieceSet.shapesAssets),
  kiwenSuwi('Kiwen-suwi', PieceSet.kiwenSuwiAssets),
  letter('Letter', PieceSet.letterAssets),
  totoy('Totoy', PieceSet.totoyAssets),
  geo('Geo', PieceSet.geoAssets),
  ink('Ink', PieceSet.inkAssets),
  bubble('Bubble', PieceSet.bubbleAssets);

  const PieceSet(this.label, this.assets);

  /// The label of this [PieceSet].
  final String label;

  /// The [PieceAssets] for this [PieceSet].
  final PieceAssets assets;

  /// The [PieceAssets] for the 'Colin M.L. Burnett' piece set.
  static const PieceAssets cburnettAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/cburnett/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/cburnett/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/cburnett/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/cburnett/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/cburnett/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/cburnett/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/cburnett/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/cburnett/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/cburnett/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/cburnett/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/cburnett/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/cburnett/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Celtic' piece set.
  static const PieceAssets celticAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/celtic/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/celtic/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/celtic/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/celtic/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/celtic/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/celtic/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/celtic/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/celtic/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/celtic/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/celtic/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/celtic/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/celtic/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Chessnut' piece set.
  static const PieceAssets chessnutAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/chessnut/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/chessnut/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/chessnut/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/chessnut/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/chessnut/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/chessnut/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/chessnut/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/chessnut/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/chessnut/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/chessnut/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/chessnut/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/chessnut/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Fantasy' piece set.
  static const PieceAssets fantasyAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/fantasy/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/fantasy/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/fantasy/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/fantasy/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/fantasy/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/fantasy/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/fantasy/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/fantasy/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/fantasy/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/fantasy/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/fantasy/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/fantasy/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Kiwen-suwi' piece set.
  static const PieceAssets kiwenSuwiAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/kiwen-suwi/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/kiwen-suwi/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/kiwen-suwi/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/kiwen-suwi/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/kiwen-suwi/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/kiwen-suwi/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/kiwen-suwi/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/kiwen-suwi/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/kiwen-suwi/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/kiwen-suwi/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/kiwen-suwi/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/kiwen-suwi/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Letter' piece set.
  static const PieceAssets letterAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/letter/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/letter/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/letter/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/letter/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/letter/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/letter/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/letter/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/letter/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/letter/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/letter/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/letter/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/letter/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Merida' piece set.
  static const PieceAssets meridaAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/merida/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/merida/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/merida/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/merida/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/merida/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/merida/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/merida/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/merida/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/merida/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/merida/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/merida/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/merida/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Pirouetti' piece set.
  static const PieceAssets pirouettiAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/pirouetti/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/pirouetti/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/pirouetti/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/pirouetti/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/pirouetti/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/pirouetti/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/pirouetti/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/pirouetti/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/pirouetti/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/pirouetti/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/pirouetti/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/pirouetti/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Mpchess' piece set.
  static const PieceAssets mpchessAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/mpchess/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/mpchess/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/mpchess/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/mpchess/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/mpchess/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/mpchess/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/mpchess/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/mpchess/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/mpchess/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/mpchess/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/mpchess/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/mpchess/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Pixel' piece set.
  static const PieceAssets pixelAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/pixel/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/pixel/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/pixel/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/pixel/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/pixel/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/pixel/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/pixel/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/pixel/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/pixel/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/pixel/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/pixel/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/pixel/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Firi' piece set.
  static const PieceAssets firiAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/firi/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/firi/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/firi/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/firi/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/firi/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/firi/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/firi/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/firi/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/firi/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/firi/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/firi/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/firi/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Shapes' piece set.
  static const PieceAssets shapesAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/shapes/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/shapes/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/shapes/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/shapes/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/shapes/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/shapes/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/shapes/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/shapes/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/shapes/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/shapes/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/shapes/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/shapes/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Spatial' piece set.
  static const PieceAssets spatialAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/spatial/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/spatial/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/spatial/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/spatial/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/spatial/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/spatial/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/spatial/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/spatial/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/spatial/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/spatial/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/spatial/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/spatial/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'RhosGFX' piece set.
  static const PieceAssets rhosgfxAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/rhosgfx/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/rhosgfx/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/rhosgfx/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/rhosgfx/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/rhosgfx/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/rhosgfx/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/rhosgfx/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/rhosgfx/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/rhosgfx/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/rhosgfx/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/rhosgfx/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/rhosgfx/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Totoy' piece set.
  static const PieceAssets totoyAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/totoy/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/totoy/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/totoy/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/totoy/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/totoy/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/totoy/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/totoy/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/totoy/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/totoy/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/totoy/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/totoy/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/totoy/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Geo' piece set (ChessGeek's own).
  static const PieceAssets geoAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/geo/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/geo/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/geo/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/geo/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/geo/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/geo/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/geo/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/geo/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/geo/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/geo/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/geo/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/geo/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Ink' piece set (ChessGeek's own).
  static const PieceAssets inkAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/ink/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/ink/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/ink/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/ink/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/ink/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/ink/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/ink/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/ink/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/ink/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/ink/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/ink/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/ink/wK.webp', package: 'chessground'),
  };

  /// The [PieceAssets] for the 'Bubble' piece set (ChessGeek's own).
  static const PieceAssets bubbleAssets = {
    PieceKind.blackRook: AssetImage('$_pieceSetsPath/bubble/bR.webp', package: 'chessground'),
    PieceKind.blackPawn: AssetImage('$_pieceSetsPath/bubble/bP.webp', package: 'chessground'),
    PieceKind.blackKnight: AssetImage('$_pieceSetsPath/bubble/bN.webp', package: 'chessground'),
    PieceKind.blackBishop: AssetImage('$_pieceSetsPath/bubble/bB.webp', package: 'chessground'),
    PieceKind.blackQueen: AssetImage('$_pieceSetsPath/bubble/bQ.webp', package: 'chessground'),
    PieceKind.blackKing: AssetImage('$_pieceSetsPath/bubble/bK.webp', package: 'chessground'),
    PieceKind.whiteRook: AssetImage('$_pieceSetsPath/bubble/wR.webp', package: 'chessground'),
    PieceKind.whitePawn: AssetImage('$_pieceSetsPath/bubble/wP.webp', package: 'chessground'),
    PieceKind.whiteKnight: AssetImage('$_pieceSetsPath/bubble/wN.webp', package: 'chessground'),
    PieceKind.whiteBishop: AssetImage('$_pieceSetsPath/bubble/wB.webp', package: 'chessground'),
    PieceKind.whiteQueen: AssetImage('$_pieceSetsPath/bubble/wQ.webp', package: 'chessground'),
    PieceKind.whiteKing: AssetImage('$_pieceSetsPath/bubble/wK.webp', package: 'chessground'),
  };
}
