part of 'partner_dashboard.dart';

class _OffersManagementPage extends StatefulWidget {
  const _OffersManagementPage();

  @override
  State<_OffersManagementPage> createState() => _OffersManagementPageState();
}

class _OffersManagementPageState extends State<_OffersManagementPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _offers = const [];
  List<Map<String, dynamic>> _coupons = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Future.wait([
        OffersRepository.instance.getPromotions(),
        OffersRepository.instance.getCoupons(),
      ]);
      if (!mounted) return;
      setState(() {
        _offers = data[0];
        _coupons = data[1];
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editOffer([Map<String, dynamic>? item]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _OfferEditorDialog(item: item));
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('offerSaved'))));
      await _load();
    }
  }

  Future<void> _editCoupon([Map<String, dynamic>? item]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _CouponEditorDialog(item: item));
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('couponSaved'))));
      await _load();
    }
  }

  Future<bool> _confirm(String title, String message) async => await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(title: Text(title), content: Text(message), actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(AppStrings.of(context).t('cancel'))),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: Text(AppStrings.of(context).t('delete'))),
    ]),
  ) ?? false;

  Future<void> _deleteOffer(Map<String, dynamic> item) async {
    final t=AppStrings.of(context);
    if (!await _confirm(t.t('deleteOffer'), t.t('deleteOfferConfirm'))) return;
    await OffersRepository.instance.deletePromotion(item['id'] as String);
    await _load();
  }

  Future<void> _deleteCoupon(Map<String, dynamic> item) async {
    final t=AppStrings.of(context);
    if (!await _confirm(t.t('deleteCoupon'), t.t('deleteCouponConfirm'))) return;
    await OffersRepository.instance.deleteCoupon(item['id'] as String);
    await _load();
  }

  Future<void> _toggleOffer(Map<String, dynamic> item, bool value) async {
    await OffersRepository.instance.updatePromotionActive(item['id'] as String, value);
    await _load();
  }

  Future<void> _toggleCoupon(Map<String, dynamic> item, bool value) async {
    await OffersRepository.instance.updateCouponActive(item['id'] as String, value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t=AppStrings.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    return ColoredBox(
      color: const Color(0xFFF8F9FB),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ModernPageHero(
            title: t.t('offersManagement'),
            subtitle: t.t('offersSubtitle'),
            icon: Icons.local_offer_rounded,
            trailing: compact
                ? IconButton.filledTonal(onPressed: _load, tooltip: t.t('refreshNotifications'), icon: const Icon(Icons.refresh_rounded, size: 19))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    _SummaryPill(icon: Icons.local_offer_outlined, label: t.t('promotionsTab'), value: _offers.length.toString(), accent: AppColors.orange),
                    _SummaryPill(icon: Icons.confirmation_number_outlined, label: t.t('couponsTab'), value: _coupons.length.toString(), accent: const Color(0xFF7C3AED)),
                    IconButton.filledTonal(onPressed: _load, tooltip: t.t('refreshNotifications'), icon: const Icon(Icons.refresh_rounded)),
                  ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: EdgeInsets.all(compact ? 3 : 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EAF0))),
            child: TabBar(
              controller: _tabs,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(color: const Color(0xFFFFF0E5), borderRadius: BorderRadius.circular(14)),
              labelColor: AppColors.orangeDark,
              unselectedLabelColor: AppColors.muted,
              tabs: [Tab(text: t.t('promotionsTab'), icon: compact ? null : const Icon(Icons.local_offer_rounded)), Tab(text: t.t('couponsTab'), icon: compact ? null : const Icon(Icons.confirmation_number_rounded))],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? _ProductsErrorState(message: _error!, onRetry: _load)
              : TabBarView(controller: _tabs, children: [
                  _OfferList(items: _offers, onAdd: () => _editOffer(), onEdit: _editOffer, onDelete: _deleteOffer, onToggle: _toggleOffer),
                  _CouponList(items: _coupons, onAdd: () => _editCoupon(), onEdit: _editCoupon, onDelete: _deleteCoupon, onToggle: _toggleCoupon),
                ])),
        ]),
      ),
    );
  }
}

class _OfferList extends StatelessWidget {
  const _OfferList({required this.items, required this.onAdd, required this.onEdit, required this.onDelete, required this.onToggle});
  final List<Map<String,dynamic>> items;
  final VoidCallback onAdd;
  final ValueChanged<Map<String,dynamic>> onEdit, onDelete;
  final void Function(Map<String,dynamic>, bool) onToggle;
  @override Widget build(BuildContext context) {
    final t=AppStrings.of(context);
    if (items.isEmpty) return _OfferEmpty(icon: Icons.local_offer_outlined, title: t.t('noOffers'), subtitle: t.t('noOffersSubtitle'), button: t.t('addOffer'), onAdd: onAdd);
    return Column(children: [
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(t.t('addOffer')))),
      const SizedBox(height: 12),
      Expanded(child: LayoutBuilder(builder: (context,c) {
        final count=c.maxWidth>=1050?3:c.maxWidth>=650?2:1;
        final textScale=MediaQuery.textScalerOf(context).scale(1.0).clamp(0.9,1.4); final tileHeight=(count==1?286.0:276.0)+((textScale-1.0)*72); return GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, crossAxisSpacing: 14, mainAxisSpacing: 14, mainAxisExtent: tileHeight), itemCount: items.length, itemBuilder: (_,i) => _DiscountCard(item: items[i], isCoupon: false, onEdit: ()=>onEdit(items[i]), onDelete: ()=>onDelete(items[i]), onToggle: (v)=>onToggle(items[i],v)));
      })),
    ]);
  }
}

class _CouponList extends StatelessWidget {
  const _CouponList({required this.items, required this.onAdd, required this.onEdit, required this.onDelete, required this.onToggle});
  final List<Map<String,dynamic>> items;
  final VoidCallback onAdd;
  final ValueChanged<Map<String,dynamic>> onEdit, onDelete;
  final void Function(Map<String,dynamic>, bool) onToggle;
  @override Widget build(BuildContext context) {
    final t=AppStrings.of(context);
    if (items.isEmpty) return _OfferEmpty(icon: Icons.confirmation_number_outlined, title: t.t('noCoupons'), subtitle: t.t('noCouponsSubtitle'), button: t.t('addCoupon'), onAdd: onAdd);
    return Column(children: [
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(t.t('addCoupon')))),
      const SizedBox(height: 12),
      Expanded(child: LayoutBuilder(builder: (context,c) {
        final count=c.maxWidth>=1050?3:c.maxWidth>=650?2:1;
        final textScale=MediaQuery.textScalerOf(context).scale(1.0).clamp(0.9,1.4); final tileHeight=(count==1?306.0:296.0)+((textScale-1.0)*72); return GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, crossAxisSpacing: 14, mainAxisSpacing: 14, mainAxisExtent: tileHeight), itemCount: items.length, itemBuilder: (_,i) => _DiscountCard(item: items[i], isCoupon: true, onEdit: ()=>onEdit(items[i]), onDelete: ()=>onDelete(items[i]), onToggle: (v)=>onToggle(items[i],v)));
      })),
    ]);
  }
}

class _DiscountCard extends StatelessWidget {
  const _DiscountCard({required this.item, required this.isCoupon, required this.onEdit, required this.onDelete, required this.onToggle});
  final Map<String,dynamic> item;
  final bool isCoupon;
  final VoidCallback onEdit,onDelete;
  final ValueChanged<bool> onToggle;
  @override Widget build(BuildContext context) {
    final t=AppStrings.of(context);
    final type=item['discount_type']=='fixed'?'fixed':'percentage';
    final value=(item['discount_value'] as num?)?.toDouble()??0;
    final start=DateTime.tryParse(item['start_at']?.toString()??'');
    final end=DateTime.tryParse(item['end_at']?.toString()??'');
    final now=DateTime.now();
    final status=end!=null&&end.isBefore(now)?t.t('expired'):start!=null&&start.isAfter(now)?t.t('scheduled'):item['is_active']==true?t.t('active'):t.t('inactive');
    return Card(elevation:0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFFE5E7EB))), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
      Row(children:[CircleAvatar(backgroundColor: const Color(0xFFFFEEE2), child: Icon(isCoupon?Icons.confirmation_number_rounded:Icons.local_offer_rounded,color:AppColors.orange)), const SizedBox(width:10), Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(item['title']?.toString()??'',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)), if(isCoupon) Text(item['code']?.toString()??'',style:const TextStyle(color:AppColors.orangeDark,fontWeight:FontWeight.w900,letterSpacing:1.2))])), PopupMenuButton<String>(onSelected:(v)=>v=='edit'?onEdit():onDelete(),itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(t.t(isCoupon?'editCoupon':'editOffer'))),PopupMenuItem(value:'delete',child:Text(t.t(isCoupon?'deleteCoupon':'deleteOffer')))])]),
      const SizedBox(height:12),
      Text(type=='percentage'?'${value.toStringAsFixed(0)}%':'${value.toStringAsFixed(0)} د.ع',style:const TextStyle(fontSize:28,color:AppColors.orangeDark,fontWeight:FontWeight.w900)),
      const SizedBox(height:6), Text(status,style:TextStyle(color:status==t.t('active')?AppColors.green:AppColors.muted,fontWeight:FontWeight.w800)),
      const Spacer(),
      if(isCoupon) Text('${t.t('usedCount')}: ${item['used_count']??0} / ${item['usage_limit']??'∞'}',style:const TextStyle(color:AppColors.muted)),
      const Divider(), Row(children:[Expanded(child:Text(t.t(isCoupon?'activeCoupon':'activeOffer'),style:const TextStyle(fontWeight:FontWeight.w700))),Switch.adaptive(value:item['is_active']==true,onChanged:onToggle,activeThumbColor:AppColors.green)])
    ])));
  }
}

class _OfferEmpty extends StatelessWidget {
  const _OfferEmpty({required this.icon,required this.title,required this.subtitle,required this.button,required this.onAdd});
  final IconData icon; final String title,subtitle,button; final VoidCallback onAdd;
  @override Widget build(BuildContext context){final compact=MediaQuery.sizeOf(context).width<700;return Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Card(child:Padding(padding:EdgeInsets.all(compact?22:40),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:compact?44:60,color:const Color(0xFFB6BBC5)),SizedBox(height:compact?10:14),Text(title,textAlign:TextAlign.center,style:TextStyle(fontSize:compact?17:22,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(subtitle,textAlign:TextAlign.center,style:TextStyle(color:AppColors.muted,fontSize:compact?11:14)),SizedBox(height:compact?14:18),FilledButton.icon(onPressed:onAdd,icon:const Icon(Icons.add),label:Text(button))])))));}
}

class _OfferEditorDialog extends StatefulWidget { const _OfferEditorDialog({this.item}); final Map<String,dynamic>? item; @override State<_OfferEditorDialog> createState()=>_OfferEditorDialogState(); }
class _OfferEditorDialogState extends State<_OfferEditorDialog> {
  final _key=GlobalKey<FormState>(); late final TextEditingController _title,_desc,_value,_min,_perCustomer; String _type='percentage'; DateTime _start=DateTime.now(),_end=DateTime.now().add(const Duration(days:7)); bool _active=true,_saving=false;
  @override void initState(){super.initState();final x=widget.item;_title=TextEditingController(text:x?['title']?.toString()??'');_desc=TextEditingController(text:x?['description']?.toString()??'');_value=TextEditingController(text:x==null?'':(x['discount_value'] as num?)?.toString()??'');_min=TextEditingController(text:x==null?'0':(x['minimum_order'] as num?)?.toString()??'0');_perCustomer=TextEditingController(text:x?['per_customer_limit']?.toString()??'');_type=x?['discount_type']?.toString()??'percentage';_start=DateTime.tryParse(x?['start_at']?.toString()??'')??DateTime.now();_end=DateTime.tryParse(x?['end_at']?.toString()??'')??DateTime.now().add(const Duration(days:7));_active=x?['is_active']!=false;}
  @override void dispose(){_title.dispose();_desc.dispose();_value.dispose();_min.dispose();_perCustomer.dispose();super.dispose();}
  Future<void> _pick(bool start) async {final v=await showDatePicker(context:context,initialDate:start?_start:_end,firstDate:DateTime.now().subtract(const Duration(days:365)),lastDate:DateTime.now().add(const Duration(days:3650)));if(!mounted||v==null)return;setState(()=>start?_start=v:_end=v);}
  Future<void> _save() async {final t=AppStrings.of(context);if(_key.currentState?.validate()!=true||_saving)return;if(!_end.isAfter(_start)){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t.t('invalidDateRange'))));return;}setState(()=>_saving=true);try{await OffersRepository.instance.savePromotion(promotionId:widget.item?['id'] as String?,title:_title.text,description:_desc.text,discountType:_type,discountValue:double.parse(_value.text),minimumOrder:double.tryParse(_min.text)??0,perCustomerLimit:int.tryParse(_perCustomer.text),startAt:_start,endAt:_end,isActive:_active);if(mounted)Navigator.pop(context,true);}on PostgrestException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>_saving=false);}}
  @override Widget build(BuildContext context){final t=AppStrings.of(context);return AlertDialog(title:Text(t.t(widget.item==null?'addOffer':'editOffer')),content:SizedBox(width:_adaptiveDialogWidth(context, maxWidth: 520),child:Form(key:_key,child:SingleChildScrollView(child:Column(children:[TextFormField(controller:_title,decoration:InputDecoration(labelText:t.t('offerTitle')),validator:(v)=>v==null||v.trim().isEmpty?t.t('requiredField'):null),const SizedBox(height:10),TextFormField(controller:_desc,minLines:2,maxLines:3,decoration:InputDecoration(labelText:t.t('offerDescription'))),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:_type,decoration:InputDecoration(labelText:t.t('discountType')),items:[DropdownMenuItem(value:'percentage',child:Text(t.t('percentageDiscount'))),DropdownMenuItem(value:'fixed',child:Text(t.t('fixedDiscount')))],onChanged:(v)=>setState(()=>_type=v!)),const SizedBox(height:10),TextFormField(controller:_value,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('discountValue')),validator:(v){final n=double.tryParse(v??'');if(n==null||n<=0||(_type=='percentage'&&n>100))return t.t('invalidDiscount');return null;}),const SizedBox(height:10),TextFormField(controller:_min,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('minimumOrder'))),const SizedBox(height:10),TextFormField(controller:_perCustomer,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('offerPerCustomerLimit'),helperText:t.t('offerPerCustomerLimitHint')),validator:(v){if((v??'').trim().isEmpty)return null;final n=int.tryParse(v!.trim());return n==null||n<=0?t.t('invalidUsageLimit'):null;}),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>_pick(true),icon:const Icon(Icons.calendar_today),label:Text('${t.t('startDate')}: ${_date(_start)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>_pick(false),icon:const Icon(Icons.event),label:Text('${t.t('endDate')}: ${_date(_end)}')))]),SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:Text(t.t('activeOffer')),value:_active,onChanged:(v)=>setState(()=>_active=v),activeThumbColor:AppColors.green)])))),actions:[TextButton(onPressed:_saving?null:()=>Navigator.pop(context,false),child:Text(t.t('cancel'))),FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save),label:Text(t.t('saveOffer')))]);}
}

class _CouponEditorDialog extends StatefulWidget { const _CouponEditorDialog({this.item}); final Map<String,dynamic>? item; @override State<_CouponEditorDialog> createState()=>_CouponEditorDialogState(); }
class _CouponEditorDialogState extends State<_CouponEditorDialog> {
  final _key=GlobalKey<FormState>(); late final TextEditingController _code,_title,_value,_min,_max,_limit; String _type='percentage'; DateTime _start=DateTime.now(),_end=DateTime.now().add(const Duration(days:30)); bool _active=true,_saving=false;
  @override void initState(){super.initState();final x=widget.item;_code=TextEditingController(text:x?['code']?.toString()??'');_title=TextEditingController(text:x?['title']?.toString()??'');_value=TextEditingController(text:x==null?'':(x['discount_value'] as num?)?.toString()??'');_min=TextEditingController(text:x==null?'0':(x['minimum_order'] as num?)?.toString()??'0');_max=TextEditingController(text:x==null?'':(x['max_discount'] as num?)?.toString()??'');_limit=TextEditingController(text:x==null?'':x['usage_limit']?.toString()??'');_type=x?['discount_type']?.toString()??'percentage';_start=DateTime.tryParse(x?['start_at']?.toString()??'')??DateTime.now();_end=DateTime.tryParse(x?['end_at']?.toString()??'')??DateTime.now().add(const Duration(days:30));_active=x?['is_active']!=false;}
  @override void dispose(){for(final c in [_code,_title,_value,_min,_max,_limit]) { c.dispose(); } super.dispose();}
  Future<void> _pick(bool start) async {final v=await showDatePicker(context:context,initialDate:start?_start:_end,firstDate:DateTime.now().subtract(const Duration(days:365)),lastDate:DateTime.now().add(const Duration(days:3650)));if(!mounted||v==null)return;setState(()=>start?_start=v:_end=v);}
  Future<void> _save() async {final t=AppStrings.of(context);if(_key.currentState?.validate()!=true||_saving)return;if(!_end.isAfter(_start)){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t.t('invalidDateRange'))));return;}setState(()=>_saving=true);try{await OffersRepository.instance.saveCoupon(couponId:widget.item?['id'] as String?,code:_code.text,title:_title.text,discountType:_type,discountValue:double.parse(_value.text),minimumOrder:double.tryParse(_min.text)??0,maxDiscount:double.tryParse(_max.text),usageLimit:int.tryParse(_limit.text),startAt:_start,endAt:_end,isActive:_active);if(mounted)Navigator.pop(context,true);}on PostgrestException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>_saving=false);}}
  @override Widget build(BuildContext context){final t=AppStrings.of(context);return AlertDialog(title:Text(t.t(widget.item==null?'addCoupon':'editCoupon')),content:SizedBox(width:_adaptiveDialogWidth(context, maxWidth: 540),child:Form(key:_key,child:SingleChildScrollView(child:Column(children:[TextFormField(controller:_code,textCapitalization:TextCapitalization.characters,decoration:InputDecoration(labelText:t.t('couponCode')),validator:(v)=>v==null||v.trim().length<3?t.t('requiredField'):null),const SizedBox(height:10),TextFormField(controller:_title,decoration:InputDecoration(labelText:t.t('couponTitle')),validator:(v)=>v==null||v.trim().isEmpty?t.t('requiredField'):null),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:_type,decoration:InputDecoration(labelText:t.t('discountType')),items:[DropdownMenuItem(value:'percentage',child:Text(t.t('percentageDiscount'))),DropdownMenuItem(value:'fixed',child:Text(t.t('fixedDiscount')))],onChanged:(v)=>setState(()=>_type=v!)),const SizedBox(height:10),TextFormField(controller:_value,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('discountValue')),validator:(v){final n=double.tryParse(v??'');if(n==null||n<=0||(_type=='percentage'&&n>100))return t.t('invalidDiscount');return null;}),const SizedBox(height:10),Row(children:[Expanded(child:TextFormField(controller:_min,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('minimumOrder')))),const SizedBox(width:8),Expanded(child:TextFormField(controller:_max,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('maxDiscount'))))]),const SizedBox(height:10),TextFormField(controller:_limit,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('usageLimit'),helperText:t.t('couponGlobalUsageLimitHint'))),const SizedBox(height:8),Align(alignment:AlignmentDirectional.centerStart,child:Text(t.t('couponSingleUseHint'),style:const TextStyle(fontSize:12,color:AppColors.muted,fontWeight:FontWeight.w700))),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_pick(true),child:Text('${t.t('startDate')}: ${_date(_start)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()=>_pick(false),child:Text('${t.t('endDate')}: ${_date(_end)}')))]),SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:Text(t.t('activeCoupon')),value:_active,onChanged:(v)=>setState(()=>_active=v),activeThumbColor:AppColors.green)])))),actions:[TextButton(onPressed:_saving?null:()=>Navigator.pop(context,false),child:Text(t.t('cancel'))),FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save),label:Text(t.t('saveCoupon')))]);}
}

String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2,'0')}-${value.day.toString().padLeft(2,'0')}';
