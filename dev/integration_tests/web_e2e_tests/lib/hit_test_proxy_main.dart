// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

/// Platform view type of the full-screen iframe painted under the dialog.
const String pv1ViewType = 'hit-test-proxy-pv1';

/// Platform view type of the iframe shown inside the dialog.
const String pv2ViewType = 'hit-test-proxy-pv2';

/// Key of the [SizedBox] that hosts PV2 inside the dialog.
const Key pv2Key = ValueKey<String>('pv2');

/// Key of the dialog's title text, which is painted over PV1.
const Key dialogTitleKey = ValueKey<String>('dialog-title');

/// Turns automatic pointer interceptors off when built with
/// `--dart-define=HIT_TEST_PROXY_OFF=true`.
const bool _offByDefine = bool.fromEnvironment('HIT_TEST_PROXY_OFF');

/// Whether this app turns on automatic pointer interceptors.
///
/// They are on unless the page URL has an `off` query parameter or the app was
/// built with `--dart-define=HIT_TEST_PROXY_OFF=true`.
bool get automaticPointerInterceptorsRequested =>
    !_offByDefine && !Uri.base.queryParameters.containsKey('off');

/// Number of `click` events received by PV1's document.
int pv1Clicks = 0;

/// Number of `click` events received by the documents of PV2 instances.
int pv2Clicks = 0;

Completer<void> _pv1Loaded = Completer<void>();
Completer<void> _pv2Loaded = Completer<void>();

/// Completes when PV1's document has loaded and counts clicks.
@visibleForTesting
Future<void> get pv1Loaded => _pv1Loaded.future;

/// Completes when the most recently created PV2's document has loaded and
/// counts clicks.
@visibleForTesting
Future<void> get pv2Loaded => _pv2Loaded.future;

/// Platform view type of the counting iframes in the scrolled list.
///
/// The creation params are the item's index.
const String listItemViewType = 'hit-test-proxy-list-item';

/// Key of the modal bottom sheet's content.
@visibleForTesting
const Key bottomSheetKey = ValueKey<String>('bottom-sheet');

/// Key of the [DropdownButton] painted over PV1.
const Key dropdownKey = ValueKey<String>('dropdown');

/// Values of the [DropdownButton] painted over PV1.
const List<String> dropdownValues = <String>['One', 'Two', 'Three'];

/// Key of the content of the dialog opened by [openGeneralDialog].
@visibleForTesting
const Key generalDialogKey = ValueKey<String>('general-dialog');

/// Key of the button inside the dialog opened by [openGeneralDialog].
@visibleForTesting
const Key generalDialogButtonKey = ValueKey<String>('general-dialog-button');

/// Key of the action button in the pinned app bar of the scrolled list.
@visibleForTesting
const Key appBarActionKey = ValueKey<String>('app-bar-action');

/// Key of the [SizedBox] hosting the scrolled list's item at [index].
@visibleForTesting
Key listItemKey(int index) => ValueKey<String>('list-item-$index');

/// Height of each iframe item in the scrolled list.
@visibleForTesting
const double listItemExtent = 300;

/// Number of iframe items in the scrolled list.
@visibleForTesting
const int listItemCount = 8;

/// The scroll offset [mainScrolledList] scrolls its list to, so that the first
/// item is partially under the pinned app bar.
@visibleForTesting
const double listScrollOffset = 150;

/// Number of times the last [openMenu] menu closed.
int menuClosedCount = 0;

/// The value the last [openMenu] menu closed with.
String? lastMenuSelection;

/// The value currently selected in the [DropdownButton] painted over PV1.
final ValueNotifier<String> dropdownValue = ValueNotifier<String>(dropdownValues.first);

/// Number of presses of the button inside the dialog opened by
/// [openGeneralDialog].
int generalDialogButtonPresses = 0;

/// Number of presses of the pinned app bar's action button.
int appBarActionPresses = 0;

/// Number of presses of the scrolled list's floating action button.
int fabPresses = 0;

/// Number of `click` events received by the document of each list item,
/// by item index.
final Map<int, int> listItemClicks = <int, int>{};

final Map<int, Completer<void>> _listItemLoaded = <int, Completer<void>>{};

/// Completes when the document of the scrolled list's item at [index] has
/// loaded and counts clicks.
@visibleForTesting
Future<void> listItemLoaded(int index) =>
    _listItemLoaded.putIfAbsent(index, () => Completer<void>()).future;

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

bool _factoriesRegistered = false;

/// Resets all counters and load notifications, so that every app started in
/// the same page starts from a clean state.
void _resetState() {
  pv1Clicks = 0;
  pv2Clicks = 0;
  _pv1Loaded = Completer<void>();
  _pv2Loaded = Completer<void>();
  menuClosedCount = 0;
  lastMenuSelection = null;
  dropdownValue.value = dropdownValues.first;
  generalDialogButtonPresses = 0;
  appBarActionPresses = 0;
  fabPresses = 0;
  listItemClicks.clear();
  _listItemLoaded.clear();
}

void _initialize() {
  WidgetsFlutterBinding.ensureInitialized();
  if (automaticPointerInterceptorsRequested) {
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
  }
  _resetState();
  _registerFactories();
}

void main() {
  _initialize();
  runApp(const HitTestProxyApp());
}

/// Starts the scrolled list scenario: a pinned app bar over a list of counting
/// iframes scrolled by [listScrollOffset], with a floating action button.
@visibleForTesting
void mainScrolledList() {
  _initialize();
  runApp(const ScrolledIFrameListApp());
}

void _registerFactories() {
  if (_factoriesRegistered) {
    return;
  }
  _factoriesRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(pv1ViewType, (int viewId) {
    if (_pv1Loaded.isCompleted) {
      _pv1Loaded = Completer<void>();
    }
    return _createCountingIFrame(
      label: 'PV1',
      background: '#cfe8ff',
      onClick: () => pv1Clicks += 1,
      loaded: _pv1Loaded,
    );
  });
  ui_web.platformViewRegistry.registerViewFactory(pv2ViewType, (int viewId) {
    if (_pv2Loaded.isCompleted) {
      _pv2Loaded = Completer<void>();
    }
    return _createCountingIFrame(
      label: 'PV2',
      background: '#ffe0b2',
      onClick: () => pv2Clicks += 1,
      loaded: _pv2Loaded,
    );
  });
  ui_web.platformViewRegistry.registerViewFactory(listItemViewType, (int viewId, {Object? params}) {
    final index = params! as int;
    Completer<void> loaded = _listItemLoaded.putIfAbsent(index, () => Completer<void>());
    if (loaded.isCompleted) {
      loaded = _listItemLoaded[index] = Completer<void>();
    }
    return _createCountingIFrame(
      label: 'Item $index',
      background: index.isEven ? '#c8e6c9' : '#fff9c4',
      onClick: () => listItemClicks[index] = (listItemClicks[index] ?? 0) + 1,
      loaded: loaded,
    );
  });
}

/// Creates a same-origin `<iframe srcdoc>` whose document counts clicks.
web.HTMLIFrameElement _createCountingIFrame({
  required String label,
  required String background,
  required void Function() onClick,
  required Completer<void> loaded,
}) {
  final iframe = web.HTMLIFrameElement();
  iframe.style
    ..border = 'none'
    ..width = '100%'
    ..height = '100%';
  iframe.srcdoc =
      '<!DOCTYPE html><html><body style="margin:0;height:100vh; '
              'background:$background;font:24px sans-serif">$label</body></html>'
          .toJS;
  iframe.addEventListener(
    'load',
    (web.Event _) {
      iframe.contentDocument!.addEventListener(
        'click',
        (web.Event _) {
          onClick();
        }.toJS,
      );
      if (!loaded.isCompleted) {
        loaded.complete();
      }
    }.toJS,
  );
  return iframe;
}

/// Opens a barrier-dismissible dialog over PV1 whose content includes PV2.
void openDialog() {
  showDialog<void>(
    context: _navigatorKey.currentContext!,
    builder: (BuildContext context) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 300,
                height: 60,
                child: Center(child: Text('Dialog over PV1', key: dialogTitleKey)),
              ),
              SizedBox(
                key: pv2Key,
                width: 300,
                height: 200,
                child: HtmlElementView(viewType: pv2ViewType),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Opens a modal bottom sheet over PV1.
@visibleForTesting
void openBottomSheet() {
  showModalBottomSheet<void>(
    context: _navigatorKey.currentContext!,
    builder: (BuildContext context) {
      return const SizedBox(
        key: bottomSheetKey,
        height: 200,
        child: Center(child: Text('Bottom sheet over PV1')),
      );
    },
  );
}

/// Opens a popup menu over PV1 with the items `Alpha` and `Beta`.
///
/// When the menu closes, [menuClosedCount] increments and
/// [lastMenuSelection] is set to the selected value, or null when the menu was
/// dismissed.
@visibleForTesting
void openMenu() {
  showMenu<String>(
    context: _navigatorKey.currentContext!,
    position: const RelativeRect.fromLTRB(200, 200, 600, 600),
    items: const <PopupMenuEntry<String>>[
      PopupMenuItem<String>(value: 'Alpha', child: Text('Alpha')),
      PopupMenuItem<String>(value: 'Beta', child: Text('Beta')),
    ],
  ).then((String? value) {
    lastMenuSelection = value;
    menuClosedCount += 1;
  });
}

/// Opens a barrier-dismissible [showGeneralDialog] over PV1 whose content has
/// a button counting presses in [generalDialogButtonPresses].
@visibleForTesting
void openGeneralDialog() {
  showGeneralDialog<void>(
    context: _navigatorKey.currentContext!,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    pageBuilder: (BuildContext context, Animation<double> _, Animation<double> _) {
      return Center(
        child: ColoredBox(
          key: generalDialogKey,
          color: const Color(0xFFFFFFFF),
          child: SizedBox(
            width: 320,
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                const Text('General dialog over PV1', textDirection: TextDirection.ltr),
                ElevatedButton(
                  key: generalDialogButtonKey,
                  onPressed: () => generalDialogButtonPresses += 1,
                  child: const Text('Press'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A full-screen counting iframe (PV1) with a button that opens a dialog
/// containing another counting iframe (PV2), and a [DropdownButton].
class HitTestProxyApp extends StatelessWidget {
  const HitTestProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const HtmlElementView(viewType: pv1ViewType),
            const Positioned(
              left: 16,
              bottom: 16,
              child: ElevatedButton(onPressed: openDialog, child: Text('Open dialog')),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: Material(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ValueListenableBuilder<String>(
                    valueListenable: dropdownValue,
                    builder: (BuildContext context, String value, Widget? _) {
                      return DropdownButton<String>(
                        key: dropdownKey,
                        value: value,
                        // The button shows different text than the menu items,
                        // so that finding an item's text finds the menu item.
                        selectedItemBuilder: (BuildContext context) => <Widget>[
                          for (final String value in dropdownValues) Text('Selected: $value'),
                        ],
                        items: <DropdownMenuItem<String>>[
                          for (final String value in dropdownValues)
                            DropdownMenuItem<String>(value: value, child: Text(value)),
                        ],
                        onChanged: (String? value) => dropdownValue.value = value!,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pinned app bar over a list of counting iframes scrolled by
/// [listScrollOffset], so that the first item is partially under the app bar,
/// with a floating action button over a later item.
@visibleForTesting
class ScrolledIFrameListApp extends StatefulWidget {
  const ScrolledIFrameListApp({super.key});

  @override
  State<ScrolledIFrameListApp> createState() => _ScrolledIFrameListAppState();
}

class _ScrolledIFrameListAppState extends State<ScrolledIFrameListApp> {
  final ScrollController _controller = ScrollController(initialScrollOffset: listScrollOffset);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => fabPresses += 1,
          // Text rather than an icon: this app doesn't bundle the icon font.
          child: const Text('+'),
        ),
        body: CustomScrollView(
          controller: _controller,
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              title: const Text('Pinned app bar'),
              actions: <Widget>[
                IconButton(
                  key: appBarActionKey,
                  onPressed: () => appBarActionPresses += 1,
                  icon: const Text('A'),
                ),
              ],
            ),
            SliverFixedExtentList(
              itemExtent: listItemExtent,
              delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
                return SizedBox(
                  key: listItemKey(index),
                  child: HtmlElementView(viewType: listItemViewType, creationParams: index),
                );
              }, childCount: listItemCount),
            ),
          ],
        ),
      ),
    );
  }
}
