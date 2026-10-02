import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

void main() {
  group('the icon catalogue is a real vocabulary', () {
    // The user asked for "lots of them to choose from" in the style of the
    // built-in categories. This is the guard on "lots": a catalogue that quietly
    // lost half its entries would still draw, and nobody would notice until the
    // picker felt thin again.
    test('it is big enough to choose from', () {
      expect(CategoryIcons.catalogue.length, greaterThanOrEqualTo(60));
      expect(CategoryIcons.keys.length, CategoryIcons.catalogue.length);
    });

    test('every grouped key is one the catalogue knows', () {
      // A key in a group with no glyph draws the generic sparkle, so the group
      // header would promise an icon the picker cannot show.
      for (final entry in CategoryIcons.groups.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: 'the group "${entry.key}" is empty',
        );
        for (final key in entry.value) {
          expect(
            CategoryIcons.isKnown(key),
            isTrue,
            reason:
                '"$key" is grouped under "${entry.key}" but not in the '
                'catalogue, so it draws a fallback',
          );
        }
      }
    });

    test('every catalogue entry appears in exactly one group', () {
      // Twice means the same glyph is offered twice; never means the picker
      // hides it. Either is a list that does not match itself.
      final seen = <String, int>{};
      for (final group in CategoryIcons.groups.values) {
        for (final key in group) {
          seen[key] = (seen[key] ?? 0) + 1;
        }
      }
      expect(
        seen.keys.toSet(),
        CategoryIcons.catalogue.keys.toSet(),
        reason: 'the groups and the catalogue disagree about what exists',
      );
      expect(
        seen.values.every((n) => n == 1),
        isTrue,
        reason: 'a glyph is offered in more than one group',
      );
    });

    test('a key this build does not know still draws something', () {
      // Every record written before an icon existed, and every key a future
      // build renames, has to render. A throw here would take down the
      // transactions list over a category name.
      expect(CategoryIcons.resolve('a-key-from-the-future'), isNotNull);
      expect(CategoryIcons.resolve(null), isNotNull);
      expect(CategoryIcons.isKnown('a-key-from-the-future'), isFalse);
    });

    test('the default is a real key, so a blank choice can be undone', () {
      expect(CategoryIcons.isKnown(CategoryIcons.defaultKey), isTrue);
    });
  });

  group('the glyphs are MONOCHROME, which is the whole point', () {
    // THE REASON THIS FILE EXISTS. The picker once offered full-colour emoji
    // beside the app's own icons -- a red apple next to an amber fork -- and the
    // grid stopped reading as part of the app. Every glyph here is an
    // `Icons.*_rounded` drawn in one colour by the caller, which is what makes a
    // category recognisable in a legend where nothing but colour is available.
    test('no entry is an emoji', () {
      // An emoji is a String, never an IconData, so anything that is not
      // `IconData` cannot be in here at all -- and the catalogue is typed
      // `Map<String, IconData>`, which is the guarantee. This asserts the
      // effective set, so a future edit that widens the type fails here rather
      // than on a device.
      for (final entry in CategoryIcons.catalogue.entries) {
        expect(
          entry.value,
          isA<IconData>(),
          reason: '"${entry.key}" is not a monochrome glyph',
        );
      }
    });

    test('the built-in categories and the catalogue are the same family', () {
      // Same family, not the same glyphs: the built-ins are `*_rounded`, and a
      // user picking from this grid should not be able to tell the two sets
      // apart by weight or by corner radius.
      final rounded = CategoryIcons.catalogue.values
          .where((i) => i.fontFamily == 'MaterialIcons')
          .length;
      expect(
        rounded,
        CategoryIcons.catalogue.length,
        reason: 'a glyph is not from the Material icon font the app uses',
      );
    });
  });

  group('the colours are a choice, not a decoration', () {
    test('there are enough of them', () {
      expect(CategoryColours.swatches.length, greaterThanOrEqualTo(16));
    });

    test('EVERY colour is distinct', () {
      // THE BUG. The list had `0xFF7DAEA3` twice, which is two buttons that do
      // the same thing and no way for a user to tell which is which. A duplicate
      // is invisible in review and maddening in use, so it is asserted.
      final seen = <int>{};
      final duplicates = <int>[];
      for (final value in CategoryColours.swatches) {
        if (!seen.add(value)) duplicates.add(value);
      }
      expect(
        duplicates,
        isEmpty,
        reason:
            'these colours are offered more than once: '
            '${duplicates.map((d) => d.toRadixString(16)).toList()}',
      );
    });

    test('they are a spread of hues, not a ramp of one', () {
      // A ramp is right for a SCALE and wrong for a picker: eight steps of one
      // orange are eight categories a person cannot tell apart in a legend,
      // which is the one job a category colour has.
      final buckets = <int>{};
      for (final value in CategoryColours.swatches) {
        buckets.add((HSLColor.fromColor(Color(value)).hue / 30).round() % 12);
      }
      expect(
        buckets.length,
        greaterThanOrEqualTo(6),
        reason: 'the colours cluster into too few hue families',
      );
    });

    test('they are all opaque', () {
      for (final value in CategoryColours.swatches) {
        expect(
          (value >> 24) & 0xFF,
          0xFF,
          reason: '${value.toRadixString(16)} is not opaque',
        );
      }
    });
  });

  group('a stored category round-trips its identity', () {
    test('a full record survives storage and comes back the same', () {
      final original = const CustomCategory(
        name: 'Tea',
        kind: CategoryKind.income,
        colorValue: 0xFFDE741D,
        iconKey: 'cafe',
      );

      final restored = CustomCategory.fromStored(original.encode());

      expect(restored, isNotNull);
      expect(restored!.name, 'Tea');
      expect(restored.kind, CategoryKind.income);
      expect(restored.colorValue, 0xFFDE741D);
      expect(restored.iconKey, 'cafe');
      expect(restored.id, 'custom:tea');
    });

    test('a bare legacy name is an expense with the generic look', () {
      // Every category created before this existed is a bare string in the box,
      // and it must keep looking the way it did rather than being given an
      // identity by a migration.
      final restored = CustomCategory.fromStored('Coffee');

      expect(restored, isNotNull);
      expect(restored!.name, 'Coffee');
      expect(restored.kind, CategoryKind.expense);
      expect(restored.colorValue, isNull);
      expect(restored.iconKey, isNull);
      expect(restored.icon, CategoryIcons.resolve(null));
    });

    test('an emoji written by the earlier build is read and ignored', () {
      // The one build that offered emoji stored the glyph under `emoji`. This
      // build has never heard of it, so the record falls back to the generic
      // sparkle -- which is exactly what that record was drawing.
      final restored = CustomCategory.fromStored(
        '{"name":"Bus","icon":"\ud83d\ude8c"}',
      );

      expect(restored, isNotNull);
      expect(restored!.iconKey, isNull);
      expect(restored.icon, CategoryIcons.resolve(null));
    });

    test('a record that cannot be read is dropped, not thrown on', () {
      // One unparseable string in a box of strings must not take the settings
      // screen down with it.
      expect(CustomCategory.fromStored(''), isNull);
      expect(CustomCategory.fromStored('   '), isNull);
      expect(CustomCategory.fromStored('{}'), isNull);
      expect(CustomCategory.fromStored('{"kind":"expense"}'), isNull);
      expect(CustomCategory.fromStored('{not json'), isNull);
    });
  });

  group('a chosen icon and colour reach the registry', () {
    tearDown(() => CategoryRegistry.setCustomCategories(const []));

    test('the registry draws a category with the identity it was given', () {
      // The point of storing a key rather than a glyph: the breakdown donut, the
      // budget row and the transaction tile all resolve through here, and none
      // of them can reach storage. If this does not work, a category the user
      // gave an identity in Settings looks generic everywhere else.
      CategoryRegistry.setCustomCategories(const [
        CustomCategory(name: 'Tea', colorValue: 0xFFDE741D, iconKey: 'cafe'),
      ]);

      final meta = CategoryRegistry.metaForCustom(
        CategoryRegistry.customById('custom:tea')!,
      );

      expect(meta.name, 'Tea');
      expect(meta.icon, CategoryIcons.resolve('cafe'));
      expect(meta.color, const Color(0xFFDE741D));
    });

    test('a category resolved BY ID is drawn with the identity it was given', () {
      // THE GAP THIS GROUP EXISTS FOR.
      //
      // A budget row, a breakdown segment and a transaction tile do not hold a
      // record -- they hold a category id and ask the registry to draw it. That
      // path used to hand every one of them the generic sparkle, so an icon and
      // a colour could be set in Settings, stored, survive a restart, and still
      // not appear anywhere except the two screens that happened to hold the
      // record. The fix is in `metaById`, and this is the test for it.
      CategoryRegistry.setCustomCategories(const [
        CustomCategory(name: 'Tea', colorValue: 0xFFDE741D, iconKey: 'cafe'),
      ]);

      final byId = CategoryRegistry.metaById('custom:tea');

      expect(byId, isNotNull);
      expect(byId!.name, 'Tea');
      expect(byId.icon, CategoryIcons.resolve('cafe'));
      expect(byId.color, const Color(0xFFDE741D));
    });

    test('a renamed category is drawn under its NEW name', () {
      // The id is `custom:<slug>` and does not change when the name does, so
      // drawing the name from the id would keep showing the old one on every
      // row that goes through the registry.
      CategoryRegistry.setCustomCategories(const [
        CustomCategory(
          name: 'Filter Coffee',
          colorValue: 0xFFDE741D,
          iconKey: 'cafe',
        ),
      ]);

      // A record for the same slug under a different name cannot happen -- the
      // slug is the name -- so the meaningful case is the reverse: the record
      // holds the name, and the meta must not re-derive it.
      final byId = CategoryRegistry.metaById('custom:filter coffee');
      expect(byId?.name, 'Filter Coffee');
    });

    test('an id with no record loaded still draws, generically', () {
      // Storage can be empty while transactions exist -- a trip imported from an
      // older build, or the moment before the provider has loaded. The row must
      // still draw, and must not claim an identity nobody chose.
      CategoryRegistry.setCustomCategories(const []);

      final byId = CategoryRegistry.metaById('custom:bus');

      expect(byId, isNotNull);
      expect(byId!.name, 'Bus');
      expect(byId.icon, CategoryIcons.resolve(null));
    });

    test('a category named after a suggested one keeps the suggested look', () {
      // Deliberately NOT the stored record: a category the app suggests and the
      // user has not touched is recognisable, and shadowing it with a generic
      // would throw that away. This ordering is load-bearing -- the suggestion
      // is checked BEFORE the record -- so it is asserted rather than assumed.
      final suggested = CategoryRegistry.suggestedForName('Coffee');
      expect(suggested, isNotNull, reason: 'Coffee is a suggested category');

      final byId = CategoryRegistry.metaById('suggested:Coffee');

      expect(byId, isNotNull);
      expect(byId!.icon, suggested!.icon);
      expect(byId.color, suggested.color);
    });

    test('a category the user has not added resolves generically', () {
      // Not throwing, and not inventing an identity.
      expect(CategoryRegistry.customById('custom:nope'), isNull);
      final meta = CategoryRegistry.metaFor(
        ExpenseCategory.other,
        customName: 'Never added',
      );
      expect(meta.name, 'Never added');
      expect(meta.icon, CategoryIcons.resolve(null));
    });
  });

  group('and it survives the trip through the provider', () {
    // THE DEVICE BUG, IN THE FORM THAT ACTUALLY BIT.
    //
    // The identity could be set, stored, and read back by every model test in
    // this file, and still never be drawn, because the one call that puts the
    // records into the registry lives in the provider -- and a model test that
    // calls `setCustomCategories` itself is testing a registry it filled by
    // hand. This goes through the provider, so the wiring is what is under test.
    tearDown(() => CategoryRegistry.setCustomCategories(const []));

    // A PLAIN test, not a widget test.
    //
    // There is no widget in this one, so it does not need the fake clock, and
    // the fake clock is what silently hangs every real storage read inside
    // `testWidgets`. Two attempts at this test cost ten minutes each before
    // that was obvious.
    test('a saved category is drawn with its own icon everywhere', () async {
      SharedPreferences.setMockInitialValues({});
      await initTestStorage();

      await StorageService().addCustomCategory(
        const CustomCategory(
          name: 'Filter Coffee',
          colorValue: 0xFFDE741D,
          iconKey: 'cafe',
        ),
      );

      final provider = TransactionProvider();
      await provider.initialize();

      // The registry now knows it, from storage, with nobody setting it by hand.
      expect(CategoryRegistry.customCategories.map((c) => c.name), [
        'Filter Coffee',
      ]);

      // And the two ways the app asks for a category both answer with the
      // choice: by ID, which is what a budget row and a breakdown segment hold,
      // and by category-plus-name, which is what a transaction tile holds.
      final byId = CategoryRegistry.metaById('custom:filter coffee');
      final byName = CategoryRegistry.metaFor(
        ExpenseCategory.other,
        customName: 'Filter Coffee',
      );

      for (final meta in [byId!, byName]) {
        expect(meta.icon, CategoryIcons.resolve('cafe'));
        expect(meta.color, const Color(0xFFDE741D));
        expect(meta.name, 'Filter Coffee');
      }
    });
  });
}
