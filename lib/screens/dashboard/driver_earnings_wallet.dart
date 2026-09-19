part of 'partner_dashboard.dart';

enum _DriverFinanceView { dues, payments }

class _DriverEarningsWalletScreen extends StatefulWidget {
  const _DriverEarningsWalletScreen({required this.onBack, this.view = _DriverFinanceView.dues});
  final VoidCallback onBack;
  final _DriverFinanceView view;

  @override
  State<_DriverEarningsWalletScreen> createState() => _DriverEarningsWalletScreenState();
}

class _DriverEarningsWalletScreenState extends State<_DriverEarningsWalletScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  int _paymentDays = 30;

  String _txt(String ar, String ku, String en) {
    final code = AppStrings.of(context).languageCode;
    if (code == 'ku') return ku;
    if (code == 'en') return en;
    return ar;
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = _data.isEmpty; _error = null; });
    try {
      final d = await DriverDeliveryRepository.instance.getEarningsWallet();
      if (mounted) setState(() => _data = d);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.code == 'PGRST202' ? AppStrings.of(context).t('driverStage16SqlRequired') : e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally { if (mounted) setState(() => _loading = false); }
  }

  double _n(String k) => double.tryParse((_data[k] ?? 0).toString()) ?? 0;
  int _i(String k) => int.tryParse((_data[k] ?? 0).toString()) ?? 0;
  String _m(num v) {
    final raw = v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
    final parts = raw.split('.');
    final rev = parts[0].split('').reversed.toList();
    final out = <String>[];
    for (var i=0;i<rev.length;i++){ if(i>0 && i%3==0) out.add(','); out.add(rev[i]); }
    final whole = out.reversed.join();
    return '${parts.length == 2 ? '$whole.${parts[1]}' : whole} د.ع';
  }
  DateTime? _dt(dynamic v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  String _date(dynamic v) { final d=_dt(v); if(d==null)return '—'; String t(int n)=>n.toString().padLeft(2,'0'); return '${t(d.day)}/${t(d.month)}/${d.year}  ${t(d.hour)}:${t(d.minute)}'; }

  List<Map<String,dynamic>> _maps(String key) => ((_data[key] as List?) ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();

  @override
  Widget build(BuildContext context) {
    final isPayments = widget.view == _DriverFinanceView.payments;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: SafeArea(child: LayoutBuilder(builder: (context,c){
        final wide=c.maxWidth>=900;
        return Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide?1180:760), child: Column(children:[
          Padding(padding: const EdgeInsets.fromLTRB(12,8,12,4), child: Row(children:[
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded)),
            Expanded(child: Text(isPayments?_txt('الدفعات','پارەدانەکان','Payments'):_txt('المستحقات','شایستەکان','Dues'), textAlign: TextAlign.center, style: const TextStyle(fontSize:22,fontWeight:FontWeight.w900))),
            IconButton(onPressed:_load, icon: const Icon(Icons.refresh_rounded)),
          ])),
          Expanded(child:_loading?const Center(child:CircularProgressIndicator()):_error!=null?_errorView():RefreshIndicator(onRefresh:_load,child:ListView(padding:EdgeInsets.fromLTRB(wide?22:14,10,wide?22:14,30),children:isPayments?_paymentView(wide):_duesView(wide))))
        ])));
      })),
    );
  }

  Widget _errorView()=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.error_outline_rounded,size:42,color:AppColors.orange),const SizedBox(height:12),Text(_error!,textAlign:TextAlign.center),const SizedBox(height:14),FilledButton(onPressed:_load,child:Text(_txt('إعادة المحاولة','دووبارە هەوڵبدەرەوە','Retry')))])));

  List<Widget> _duesView(bool wide)=>[
    _financeHero(icon:Icons.account_balance_wallet_rounded,title:_txt('المستحق الحالي','شایستەی ئێستا','Current due'),amount:_n('outstanding_due'),colors:const[Color(0xFFFF5B00),Color(0xFFFF7A00)],subtitle:_txt('هذا هو المبلغ المتبقي لك بعد خصم الدفعات المسجلة','ئەمە بڕی ماوەیە دوای کەمکردنەوەی پارەدانە تۆمارکراوەکان','This is what remains after recorded payments')),
    const SizedBox(height:12),
    _threeMoneySummary(wide),
    const SizedBox(height:12),
    _balanceExplanation(),
    const SizedBox(height:12),
    _stats(wide),
    const SizedBox(height:14),
    _duesLedger(),
    const SizedBox(height:14),
    _policy(),
  ];

  List<Widget> _paymentView(bool wide)=>[
    _financeHero(icon:Icons.payments_rounded,title:_txt('إجمالي المدفوع','کۆی پارەدراو','Total paid'),amount:_n('paid_amount'),colors:const[Color(0xFF6C5CE7),Color(0xFF8E7CF6)],subtitle:_txt('المبالغ التي تم تسجيلها كمدفوعة لك','ئەو بڕانەی وەک پارەدراو تۆمارکراون','Payments recorded as paid to you')),
    const SizedBox(height:12),
    _paymentPeriod(),
    const SizedBox(height:12),
    _payments(),
  ];

  Widget _financeHero({required IconData icon,required String title,required double amount,required List<Color> colors,required String subtitle})=>LayoutBuilder(builder:(context,c){final narrow=c.maxWidth<360; final ico=Container(width:64,height:64,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.18),borderRadius:BorderRadius.circular(19)),child:Icon(icon,color:Colors.white,size:36)); final copy=Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.white70,fontWeight:FontWeight.w800)),const SizedBox(height:5),FittedBox(fit:BoxFit.scaleDown,alignment:AlignmentDirectional.centerStart,child:Text(_m(amount),style:const TextStyle(color:Colors.white,fontSize:29,fontWeight:FontWeight.w900))),const SizedBox(height:4),Text(subtitle,style:const TextStyle(color:Colors.white70,height:1.35))]); return Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:LinearGradient(colors:colors),borderRadius:BorderRadius.circular(24)),child:narrow?Column(crossAxisAlignment:CrossAxisAlignment.start,children:[ico,const SizedBox(height:12),copy]):Row(children:[ico,const SizedBox(width:15),Expanded(child:copy)]));});

  Widget _threeMoneySummary(bool wide) {
    final cards = [
      _compactMoneyCard(
        Icons.savings_outlined,
        _txt('إجمالي المستحق', 'کۆی شایستە', 'Total earned'),
        _m(_n('base_due') + _n('bonus_due')),
        AppColors.orange,
      ),
      _compactMoneyCard(
        Icons.check_circle_outline_rounded,
        _txt('المدفوع', 'پارەدراو', 'Paid'),
        _m(_n('paid_amount')),
        const Color(0xFF20A747),
      ),
      _compactMoneyCard(
        Icons.hourglass_bottom_rounded,
        _txt('المتبقي', 'ماوە', 'Remaining'),
        _m(_n('outstanding_due')),
        const Color(0xFF2878E8),
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 760) {
        return Row(children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i < cards.length - 1) const SizedBox(width: 10),
          ],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(child: cards[i]),
          if (i < cards.length - 1) const SizedBox(width: 8),
        ],
      ]);
    });
  }

  Widget _compactMoneyCard(IconData icon, String label, String value, Color color) =>
      Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Widget _balanceExplanation() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6EF),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFFFE1CC)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.orange, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _txt(
                  'إجمالي المستحق هو ما كسبته من التوصيلات والمكافآت، والمدفوع هو ما تم تسليمه لك فعليًا، والمتبقي هو رصيدك الحالي.',
                  'کۆی شایستە ئەوەیە کە لە گەیاندن و خەڵاتەکان بەدەستت هێناوە، پارەدراو ئەوەیە کە پێت دراوە، ماوەش بالانسی ئێستاتە.',
                  'Total earned includes deliveries and bonuses. Paid is what you already received. Remaining is your current balance.',
                ),
                style: const TextStyle(color: AppColors.muted, height: 1.45, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  Widget _stats(bool wide) {
    final cards = [
      _statCompact(Icons.delivery_dining_rounded, _txt('التوصيلات', 'گەیاندنەکان', 'Deliveries'), _i('delivered_orders').toString(), AppColors.orange),
      _statCompact(Icons.calendar_today_rounded, _txt('أيام العمل', 'ڕۆژانی کار', 'Work days'), _i('work_days').toString(), const Color(0xFF2878E8)),
      _statCompact(Icons.card_giftcard_rounded, _txt('المكافآت', 'خەڵاتەکان', 'Bonuses'), _m(_n('bonus_due')), const Color(0xFF20A747)),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < cards.length; i++) ...[
        Expanded(child: cards[i]),
        if (i < cards.length - 1) const SizedBox(width: 8),
      ],
    ]);
  }

  Widget _statCompact(IconData icon, String label, String value, Color color) => Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _duesLedger() {
    final rows = _maps('dues');
    return _section(
      title: _txt('سجل حركة المستحقات', 'تۆماری جوڵەی شایستەکان', 'Dues activity'),
      child: rows.isEmpty
          ? _emptyLedger()
          : Column(children: [for (final r in rows) _ledgerTile(r)]),
    );
  }

  Widget _emptyLedger() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: const Color(0xFFFFF1E8), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.receipt_long_outlined, color: AppColors.orange, size: 28),
          ),
          const SizedBox(height: 11),
          Text(
            _txt('لا توجد حركات مستحقات بعد', 'هێشتا جوڵەی شایستە نییە', 'No dues activity yet'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            _txt(
              'بعد إكمال التوصيلات سيظهر هنا رقم الطلب، أجرة التوصيل، المكافأة أو الخصم، التاريخ وحالة الاستحقاق.',
              'دوای تەواوکردنی گەیاندن، ژمارەی داواکاری و کرێی گەیاندن و خەڵات یان کەمکردنەوە و بەروار لێرە دەردەکەون.',
              'Completed deliveries will appear here with order number, delivery fee, bonus or deduction, date and status.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showDuesBreakdown,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(_txt('عرض التفاصيل', 'بینینی وردەکاری', 'View details')),
          ),
        ]),
      );

  Widget _ledgerTile(Map<String,dynamic> r) {
    final kind=(r['kind']??'base').toString();
    final amount=double.tryParse((r['amount']??0).toString())??0;
    final bonus=kind=='bonus';
    final orderRef=(r['order_number']??r['order_id']??'').toString().trim();
    final status=(r['status']??'').toString().trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical:7),
      child: Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        CircleAvatar(radius:19,backgroundColor:(bonus?const Color(0xFF20A747):AppColors.orange).withValues(alpha:.1),child:Icon(bonus?Icons.card_giftcard_rounded:Icons.delivery_dining_rounded,size:19,color:bonus?const Color(0xFF20A747):AppColors.orange)),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((r['period_label']??r['note']??_txt('استحقاق','شایستە','Due')).toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
          if(orderRef.isNotEmpty) Text('${_txt('الطلب','داواکاری','Order')} #$orderRef', style: const TextStyle(fontSize:12,color:AppColors.muted,fontWeight:FontWeight.w700)),
          if((r['note']??'').toString().trim().isNotEmpty)Text(r['note'].toString(),style:const TextStyle(fontSize:12,color:AppColors.muted)),
          Text(_date(r['created_at']),style:const TextStyle(fontSize:11,color:AppColors.muted)),
        ])),
        Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Text(_m(amount),style:const TextStyle(fontWeight:FontWeight.w900)),
          if(status.isNotEmpty) Text(status, style: const TextStyle(fontSize:10.5,color:AppColors.muted,fontWeight:FontWeight.w700)),
        ]),
      ]),
    );
  }

  Future<void> _showDuesBreakdown() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_txt('تفاصيل المستحقات','وردەکاری شایستەکان','Dues details'), style: const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
              const SizedBox(height:16),
              _row(_txt('المستحق الأساسي','شایستەی بنەڕەتی','Base due'), _m(_n('base_due'))),
              _row(_txt('المكافآت','خەڵاتەکان','Bonuses'), _m(_n('bonus_due'))),
              _row(_txt('إجمالي المستحق','کۆی شایستە','Total earned'), _m(_n('base_due') + _n('bonus_due'))),
              _row(_txt('المدفوع','پارەدراو','Paid'), _m(_n('paid_amount'))),
              const Divider(height: 22),
              _row(_txt('المتبقي','ماوە','Remaining'), _m(_n('outstanding_due'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _policy()=>_section(title:_txt('نظام مستحقات السائق','سیستەمی شایستەی شۆفێر','Driver compensation'),child:Column(children:[_row(_txt('طريقة الاحتساب','شێوازی ژماردن','Calculation'),(_data['pay_type_label']??_txt('حسب اتفاق الإدارة','بەپێی ڕێککەوتنی بەڕێوەبەرایەتی','As agreed with admin')).toString()),_row(_txt('المستحق الأساسي','شایستەی بنەڕەتی','Base due'),_m(_n('base_due'))),_row(_txt('المكافآت','خەڵاتەکان','Bonuses'),_m(_n('bonus_due'))),const Divider(height:22),Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.info_outline_rounded,color:AppColors.orange),const SizedBox(width:8),Expanded(child:Text(_txt('المستحقات هي ما تكسبه من التوصيلات والمكافآت. الدفعات هي المبالغ التي تم تسليمها لك فعليًا، وتظهر منفصلة في صفحة الدفعات.','شایستەکان ئەوەیە کە لە گەیاندن و خەڵاتەکان بەدەستت دێت؛ پارەدانەکان ئەو بڕانەن کە بەڕاستی پێت دراون.','Dues are what you earn from deliveries and bonuses. Payments are the amounts actually paid to you and are listed separately.'),style:const TextStyle(color:AppColors.muted,height:1.45,fontWeight:FontWeight.w700)))]) ]));

  Widget _paymentPeriod()=>_section(title:_txt('الفترة','ماوە','Period'),child:DropdownButtonFormField<int>(initialValue:_paymentDays,decoration:const InputDecoration(border:OutlineInputBorder()),items:[DropdownMenuItem(value:7,child:Text(_txt('آخر 7 أيام','٧ ڕۆژی ڕابردوو','Last 7 days'))),DropdownMenuItem(value:30,child:Text(_txt('آخر 30 يوم','٣٠ ڕۆژی ڕابردوو','Last 30 days'))),DropdownMenuItem(value:90,child:Text(_txt('آخر 90 يوم','٩٠ ڕۆژی ڕابردوو','Last 90 days'))),const DropdownMenuItem(value:0,child:Text('الكل'))],onChanged:(v)=>setState(()=>_paymentDays=v??30)));
  List<Map<String,dynamic>> get _filteredPayments {final now=DateTime.now(); return _maps('payments').where((r){if(_paymentDays<=0)return true;final d=_dt(r['paid_at']);return d==null||d.isAfter(now.subtract(Duration(days:_paymentDays)));}).toList();}
  Widget _payments(){final rows=_filteredPayments;return _section(title:_txt('سجل الدفعات','تۆماری پارەدان','Payment history'),child:rows.isEmpty?_empty(_txt('لا توجد دفعات مسجلة ضمن هذه الفترة.','هیچ پارەدانێک لەم ماوەیەدا نییە.','No payments in this period.')):Column(children:[for(final r in rows)_paymentTile(r)]));}
  Widget _paymentTile(Map<String,dynamic> r) {
    final amount = double.tryParse((r['amount'] ?? 0).toString()) ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showPayment(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFFECE9FF), child: Icon(Icons.payments_outlined, color: Color(0xFF6C5CE7))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_m(amount), style: const TextStyle(fontWeight: FontWeight.w900)),
            Text((r['period_label'] ?? r['note'] ?? _txt('دفعة','پارەدان','Payment')).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(_date(r['paid_at']), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFFE7F7EC), borderRadius: BorderRadius.circular(9)),
            child: Text(_txt('مدفوعة','پارەدراو','Paid'), style: const TextStyle(color: Color(0xFF14853B), fontWeight: FontWeight.w900, fontSize: 11)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
      ),
    );
  }

  Future<void> _showPayment(Map<String,dynamic> r) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_txt('تفاصيل الدفعة','وردەکاری پارەدان','Payment details'), style: const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
              const SizedBox(height:16),
              _row(_txt('المبلغ','بڕ','Amount'), _m(double.tryParse((r['amount']??0).toString())??0)),
              _row(_txt('الحالة','دۆخ','Status'), _txt('مدفوعة','پارەدراو','Paid')),
              _row(_txt('التاريخ','بەروار','Date'), _date(r['paid_at'])),
              _row(_txt('الفترة/المرجع','ماوە/سەرچاوە','Period/reference'), (r['period_label']??'—').toString()),
              if((r['note']??'').toString().trim().isNotEmpty) _row(_txt('ملاحظة','تێبینی','Note'), r['note'].toString()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required String title,required Widget child})=>Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE8EAF0))),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:12),child]));
  Widget _empty(String text)=>Padding(padding:const EdgeInsets.symmetric(vertical:22),child:Center(child:Text(text,textAlign:TextAlign.center,style:const TextStyle(color:AppColors.muted))));
  Widget _row(String a,String b)=>Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(a,style:const TextStyle(color:AppColors.muted,fontWeight:FontWeight.w700))),const SizedBox(width:12),Flexible(child:Text(b,textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w900)))]));
}
