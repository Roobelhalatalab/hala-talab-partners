part of 'partner_dashboard.dart';

/// Opt-in screen for Hala Talab directed offers; legacy driver flow is untouched.
class _HalaDirectedOffersScreen extends StatefulWidget {
  const _HalaDirectedOffersScreen();
  @override
  State<_HalaDirectedOffersScreen> createState() => _HalaDirectedOffersScreenState();
}

class _HalaDirectedOffersScreenState extends State<_HalaDirectedOffersScreen> {
  List<Map<String, dynamic>> _offers = const [];
  String? _error;
  bool _loading = false;
  final Set<String> _busy = {};

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await DriverDeliveryRepository.instance.getMyHalaDirectedOffers();
      if (mounted) setState(() => _offers = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر جلب الطلبات الموجهة: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String offerId, bool accept) async {
    if (_busy.contains(offerId)) return;
    setState(() => _busy.add(offerId));
    try {
      await DriverDeliveryRepository.instance.decideHalaDirectedOffer(offerId: offerId, accept: accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accept ? 'تم قبول الطلب' : 'تم رفض الطلب')));
      setState(() => _offers = _offers.where((x) => x['offer_id']?.toString() != offerId).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لم تنجح العملية: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(offerId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات سائقي هلا طلب'), actions: [IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh))]),
    body: _loading && _offers.isEmpty ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
      : _offers.isEmpty ? const Center(child: Text('لا توجد طلبات موجهة بانتظار القبول'))
      : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
          itemCount: _offers.length,
          itemBuilder: (context, i) {
            final row = _offers[i];
            final id = row['offer_id']?.toString() ?? '';
            final number = row['order_number']?.toString() ?? '—';
            final store = row['store_name']?.toString() ?? 'المتجر';
            final area = row['area_name']?.toString() ?? '—';
            final address = row['delivery_address']?.toString() ?? ''; 
            final busy = _busy.contains(id);
            return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Padding(
              padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('طلب رقم $number — $store', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('منطقة التوصيل: $area'),
                if (address.isNotEmpty) Text('العنوان: $address'),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton(onPressed: busy || id.isEmpty ? null : () => _decide(id, true), child: const Text('قبول الطلب')),
                  const SizedBox(width: 12),
                  OutlinedButton(onPressed: busy || id.isEmpty ? null : () => _decide(id, false), child: const Text('رفض')),
                ]),
              ]),
            ));
          },
        )),
  );
}
