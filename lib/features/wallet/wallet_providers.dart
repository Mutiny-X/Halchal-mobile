import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/creator_profile/creator_profile_providers.dart';
import '../../core/realtime/participation_realtime.dart';

final walletProvider = FutureProvider<WalletData>((ref) async {
  watchAppRealtimeTick(ref);
  final activeProfile = ref.watch(activeCreatorProfileProvider);
  return ref.read(apiClientProvider).fetchWallet(
        creatorProfileId: activeProfile?.id,
      );
});

final walletTransactionsProvider = FutureProvider<List<TransactionItem>>((ref) async {
  watchAppRealtimeTick(ref);
  return ref.read(apiClientProvider).fetchTransactions();
});

final withdrawalsProvider = FutureProvider<List<Withdrawal>>((ref) async {
  watchAppRealtimeTick(ref);
  return ref.read(apiClientProvider).fetchWithdrawals();
});
