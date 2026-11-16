import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n.dart';
import '../theme.dart';

class TileSpec {
  const TileSpec(this.url, this.attribution, {this.subdomains = const [], this.maxNative = 19});
  final String url;
  final String attribution;
  final List<String> subdomains;
  final int maxNative;
}

class Basemaps {
  static const esriImagery = TileSpec(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'Esri, Maxar, Earthstar Geographics',
      maxNative: 18);
  static const esriLabels = TileSpec(
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
      'Esri',
      maxNative: 18);
  static const openTopo = TileSpec('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      '© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)',
      subdomains: ['a', 'b', 'c'], maxNative: 17);
  static const esriGray = TileSpec(
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
      'Esri, HERE, Garmin, © OpenStreetMap contributors',
      maxNative: 16);
  static const esriGrayLabels = TileSpec(
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
      'Esri',
      maxNative: 16);
  static const osm = TileSpec('https://tile.openstreetmap.org/{z}/{x}/{y}.png', '© OpenStreetMap contributors');
  static TileSpec carto(String style, String? key) => TileSpec(
      'https://basemaps.cartocdn.com/rastertiles/$style/{z}/{x}/{y}.png${key == null ? '' : '?key=$key'}',
      '© OpenStreetMap contributors, © CARTO',
      maxNative: 20);
}

/// One raster result layer produced by the backend (PNG + bounds).
class OverlaySpec {
  OverlaySpec({required this.id, required this.label, required this.bytes, required this.bounds, this.visible = true});
  final String id;
  final String label;
  final Uint8List bytes;
  final LatLngBounds bounds;
  bool visible;

  static OverlaySpec? fromJson(String id, String label, dynamic json, {bool visible = true}) {
    if (json is! Map || json['image_base64'] is! String) return null;
    final b = json['bounds'] as List;
    return OverlaySpec(
      id: id,
      label: label,
      bytes: base64Decode(json['image_base64'] as String),
      bounds: LatLngBounds(LatLng((b[0] as num).toDouble(), (b[1] as num).toDouble()),
          LatLng((b[2] as num).toDouble(), (b[3] as num).toDouble())),
      visible: visible,
    );
  }
}

List<List<LatLng>> polygonsFromGeoJson(dynamic geom) {
  final out = <List<LatLng>>[];
  if (geom is! Map) return out;
  List<LatLng> ring(dynamic r) => [for (final p in r as List) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())];
  if (geom['type'] == 'Polygon') {
    out.add(ring((geom['coordinates'] as List).first));
  } else if (geom['type'] == 'MultiPolygon') {
    for (final poly in geom['coordinates'] as List) {
      out.add(ring((poly as List).first));
    }
  }
  return out;
}

class MapPanel extends StatefulWidget {
  /// Widget tests run without network: tiles are skipped there.
  static bool offlineTiles = false;

  const MapPanel({
    super.key,
    required this.module,
    required this.controller,
    required this.selection,
    required this.draft,
    required this.overlays,
    this.outlines = const [],
    this.highlight,
    this.legend,
    this.periodLabel,
    this.onTap,
    this.fitBounds,
    this.cartoKey,
    this.height,
    this.busyLabel,
  });
  final String? busyLabel;

  final ModuleStyle module;
  final MapController controller;
  final List<LatLng> selection;
  final List<LatLng> draft;
  final List<OverlaySpec> overlays;
  final List<List<LatLng>> outlines;
  final List<LatLng>? highlight;
  final Widget? legend;
  final String? periodLabel;
  final void Function(LatLng)? onTap;
  final LatLngBounds? fitBounds;
  final String? cartoKey;
  final double? height;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  double _opacity = 0.85;
  bool _labels = true;
  bool _outlines = true;
  bool _showLayers = false;
  bool _legendOpen = true;
  bool _relief = false; // glaciers: satellite vs relief
  int _baseErrors = 0;
  bool _fallback = false;
  bool _ready = false;

  static final _world = LatLngBounds(const LatLng(-55, -150), const LatLng(70, 160));

  @override
  void didUpdateWidget(covariant MapPanel old) {
    super.didUpdateWidget(old);
    if (widget.fitBounds != null && widget.fitBounds != old.fitBounds && _ready) {
      _fit(widget.fitBounds!);
    }
    if (old.module.id != widget.module.id) {
      _fallback = false;
      _baseErrors = 0;
    }
  }

  void _fit(LatLngBounds b) {
    widget.controller.fitCamera(CameraFit.bounds(bounds: b, padding: const EdgeInsets.fromLTRB(48, 64, 48, 56), maxZoom: 15));
  }

  void _recenter() {
    if (widget.selection.length >= 3) {
      _fit(LatLngBounds.fromPoints(widget.selection));
    } else if (widget.fitBounds != null) {
      _fit(widget.fitBounds!);
    } else {
      _fit(_world);
    }
  }

  TileSpec get _base {
    switch (widget.module.id) {
      case ModuleId.hundimiento:
        // CARTO needs a key (keyless tiles are watermarked); Esri light gray is keyless.
        if (_fallback) return Basemaps.osm;
        return widget.cartoKey != null ? Basemaps.carto('voyager_nolabels', widget.cartoKey) : Basemaps.esriGray;
      case ModuleId.glaciares:
        if (_relief) return _fallback ? Basemaps.esriImagery : Basemaps.openTopo;
        return _fallback ? Basemaps.openTopo : Basemaps.esriImagery;
      case ModuleId.bosques:
        return _fallback ? Basemaps.openTopo : Basemaps.esriImagery;
    }
  }

  TileSpec? get _labelsLayer {
    if (!_labels) return null;
    if (widget.module.id == ModuleId.hundimiento) {
      if (_fallback) return null; // OSM fallback has its own labels
      return widget.cartoKey != null ? Basemaps.carto('voyager_only_labels', widget.cartoKey) : Basemaps.esriGrayLabels;
    }
    if (_relief && !_fallback) return null; // OpenTopoMap already has labels
    return Basemaps.esriLabels;
  }

  void _onBaseError() {
    if (_fallback) return;
    _baseErrors++;
    if (_baseErrors >= 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _fallback = true);
      });
    }
  }

  TileLayer _tiles(TileSpec s, {bool base = false}) => TileLayer(
        key: ValueKey(s.url),
        urlTemplate: s.url,
        subdomains: s.subdomains,
        maxNativeZoom: s.maxNative,
        userAgentPackageName: 'org.impact.app',
        errorTileCallback: base ? (_, __, ___) => _onBaseError() : null,
      );

  @override
  Widget build(BuildContext context) {
    final color = widget.module.color;
    final labels = _labelsLayer;
    final attribution = <String>{
      _base.attribution,
      if (labels != null && labels.attribution != _base.attribution) labels.attribution,
      if (widget.outlines.isNotEmpty) '© OpenStreetMap contributors',
    }.join(' · ');
    final initial = widget.fitBounds ?? (widget.selection.length >= 3 ? LatLngBounds.fromPoints(widget.selection) : _world);

    final map = FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: initial, padding: const EdgeInsets.all(40)),
        minZoom: 2,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onTap: widget.onTap == null ? null : (_, p) => widget.onTap!(p),
        onMapReady: () => _ready = true,
      ),
      children: [
        if (!MapPanel.offlineTiles) _tiles(_base, base: true),
        OverlayImageLayer(overlayImages: [
          for (final o in widget.overlays)
            if (o.visible)
              OverlayImage(
                bounds: o.bounds,
                opacity: o.id == 'no_data' ? 0.9 : _opacity,
                imageProvider: MemoryImage(o.bytes),
                gaplessPlayback: true,
              ),
        ]),
        if (_outlines && widget.outlines.isNotEmpty)
          PolygonLayer(polygons: [
            for (final p in widget.outlines)
              Polygon(points: p, borderColor: Colors.white, borderStrokeWidth: 2.2, isDotted: true, color: Colors.transparent),
          ]),
        PolygonLayer(polygons: [
          if (widget.selection.length >= 3)
            Polygon(
              points: widget.selection,
              borderColor: Colors.white,
              borderStrokeWidth: 4,
              color: Colors.transparent,
            ),
          if (widget.selection.length >= 3)
            Polygon(
              points: widget.selection,
              borderColor: color,
              borderStrokeWidth: 2.2,
              isFilled: widget.overlays.isEmpty,
              color: color.withValues(alpha: 0.08),
            ),
          if (widget.highlight != null)
            Polygon(points: widget.highlight!, borderColor: Colors.black, borderStrokeWidth: 2.5, color: Colors.transparent),
        ]),
        if (widget.draft.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(points: widget.draft, color: color, strokeWidth: 2.5, isDotted: true),
          ]),
        if (widget.draft.isNotEmpty)
          CircleLayer(circles: [
            for (final p in widget.draft)
              CircleMarker(point: p, radius: 6, color: Colors.white, borderColor: color, borderStrokeWidth: 3),
          ]),
        if (labels != null && !MapPanel.offlineTiles) _tiles(labels), // labels above results: names stay legible
      ],
    );

    return Semantics(
      label: tr(context, 'map'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          Positioned.fill(child: map),
          // period + background note
          Positioned(
            left: 10,
            top: 10,
            right: 70,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (widget.periodLabel != null)
                _Chip(icon: Icons.event_rounded, text: widget.periodLabel!, color: color),
              _Chip(icon: Icons.info_outline_rounded, text: tr(context, 'basemap.note'), color: Palette.muted, small: true),
              if (_fallback) _Chip(icon: Icons.warning_amber_rounded, text: tr(context, 'basemap.error'), color: Palette.warning, small: true),
            ]),
          ),
          // controls
          Positioned(
            right: 10,
            top: 10,
            child: Column(children: [
              _MapButton(icon: Icons.layers_rounded, tooltip: tr(context, 'layers'), onTap: () => setState(() => _showLayers = !_showLayers),
                  selected: _showLayers),
              const SizedBox(height: 8),
              _MapButton(icon: Icons.add, tooltip: tr(context, 'zoom_in'), onTap: () {
                final cam = widget.controller.camera;
                widget.controller.move(cam.center, cam.zoom + 1);
              }),
              const SizedBox(height: 4),
              _MapButton(icon: Icons.remove, tooltip: tr(context, 'zoom_out'), onTap: () {
                final cam = widget.controller.camera;
                widget.controller.move(cam.center, cam.zoom - 1);
              }),
              const SizedBox(height: 8),
              _MapButton(icon: Icons.center_focus_strong_rounded, tooltip: tr(context, 'recenter'), onTap: _recenter),
            ]),
          ),
          if (_showLayers)
            Positioned(right: 62, top: 10, child: _layersCard(context)),
          if (widget.busyLabel != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(color: Palette.ink.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(30)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                      const SizedBox(width: 12),
                      Text(widget.busyLabel!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
          if (widget.legend != null)
            Positioned(
              left: 10,
              bottom: 30,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tr(context, 'legend'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr(context, 'legend'),
                          icon: Icon(_legendOpen ? Icons.expand_more : Icons.expand_less, size: 20),
                          onPressed: () => setState(() => _legendOpen = !_legendOpen),
                        ),
                      ]),
                      if (_legendOpen) widget.legend!,
                    ]),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              color: Colors.white.withValues(alpha: 0.85),
              child: Text(attribution, style: const TextStyle(fontSize: 10.5, color: Palette.ink), maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _layersCard(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'layers'), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (widget.module.id == ModuleId.glaciares) ...[
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tr(context, 'basemap.satellite'))),
                ButtonSegment(value: true, label: Text(tr(context, 'basemap.relief'))),
              ],
              selected: {_relief},
              onSelectionChanged: (s) => setState(() {
                _relief = s.first;
                _fallback = false;
                _baseErrors = 0;
              }),
            ),
          ],
          for (final o in widget.overlays)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(o.label),
              value: o.visible,
              onChanged: (v) => setState(() => o.visible = v),
            ),
          if (widget.outlines.isNotEmpty)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'layer.outlines')),
              value: _outlines,
              onChanged: (v) => setState(() => _outlines = v),
            ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'layer.labels')),
            value: _labels,
            onChanged: (v) => setState(() => _labels = v),
          ),
          if (widget.overlays.isNotEmpty) ...[
            Text('${tr(context, 'opacity')}: ${(_opacity * 100).round()} %', style: const TextStyle(fontSize: 13)),
            Slider(
              value: _opacity,
              min: 0.2,
              max: 1,
              divisions: 8,
              label: '${(_opacity * 100).round()} %',
              semanticFormatterCallback: (v) => '${(v * 100).round()} %',
              onChanged: (v) => setState(() => _opacity = v),
            ),
          ],
        ]),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap, this.selected = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? Palette.ink : Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: selected ? Colors.white : Palette.ink, semanticLabel: tooltip),
            ),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.color, this.small = false});
  final IconData icon;
  final String text;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: small ? 4 : 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: small ? 14 : 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: small ? 11.5 : 13, fontWeight: small ? FontWeight.w500 : FontWeight.w700, color: Palette.ink)),
          ),
        ]),
      );
}

/// Discrete legend: color swatch + text (never color alone).
class LegendRows extends StatelessWidget {
  const LegendRows({super.key, required this.rows, this.note});
  final List<(Color, String, bool)> rows; // color, label, striped
  final String? note;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (final (c, label, striped) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22,
                height: 14,
                decoration: BoxDecoration(
                  color: striped ? null : c,
                  gradient: striped
                      ? LinearGradient(colors: [c, Colors.white, c, Colors.white], stops: const [0.25, 0.25, 0.75, 0.75],
                          tileMode: TileMode.repeated, begin: Alignment.topLeft, end: const Alignment(-0.6, -0.6))
                      : null,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(label, style: const TextStyle(fontSize: 12.5))),
            ]),
          ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note!, style: const TextStyle(fontSize: 11.5, color: Palette.muted)),
          ),
      ]);
}

Color hexColor(String hex) => Color(int.parse(hex.replaceFirst('#', 'ff'), radix: 16));
