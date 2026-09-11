import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/features/address_book/models/address_entry.dart';
import 'package:pirate_wallet/features/address_book/providers/address_book_provider.dart';

void main() {
  test('pinned funds lead contacts with general first across filters', () {
    AddressEntry contact(
      int id,
      String address,
      String label, {
      required bool pinned,
    }) => AddressEntry(
      id: id,
      walletId: 'wallet',
      address: address,
      label: label,
      isFavorite: pinned,
      colorTag: ColorTag.yellow,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final general = contact(
      1,
      'zs1ymgqg9dnt20q3y6lk8za2a7cq53evmqwy4lvnfruq5z4z9g3tj8znejw28e39r64yakgvcgurv2',
      "Pirate Chain's General Donation Fund",
      pinned: true,
    );
    final development = contact(
      2,
      'zs15v92wrnvuwlrdvsm88prkhazhthkeu3p4ts09jw73mnedlrxm7xydxwc2um4l28qan7n5ln95jk',
      "Pirate Chain's Development Donation Fund",
      pinned: true,
    );
    final state = AddressBookState(
      entries: [
        development,
        contact(3, 'other', 'Alice', pinned: true),
        general,
        contact(4, 'unpinned', 'Aaron', pinned: false),
      ],
    );
    expect(state.filteredEntries.map((e) => e.id), [1, 2, 3, 4]);
    expect(
      state.copyWith(searchQuery: 'Donation').filteredEntries.map((e) => e.id),
      [1, 2],
    );
    expect(
      state.copyWith(showFavoritesOnly: true).filteredEntries.map((e) => e.id),
      [1, 2, 3],
    );
    expect(
      state
          .copyWith(filterColor: ColorTag.yellow)
          .filteredEntries
          .map((e) => e.id),
      [1, 2, 3, 4],
    );
    expect(
      AddressBookState(
        entries: [general.copyWith(isFavorite: false), development],
      ).filteredEntries.first.id,
      2,
    );
  });
}
