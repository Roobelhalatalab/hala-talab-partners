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
  List<Map<String, dynamic>> _productOffers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
        OffersRepository.instance.getProductOffers(),
      ]);
      if (!mounted) return;
      setState(() {
        _offers = data[0];
        _coupons = data[1];
        _productOffers = data[2];
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

  Future<void> _editProductOffer([Map<String, dynamic>? item]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => _ProductOfferEditorDialog(item: item));
    if (saved == true && mounted) await _load();
  }

  Future<void> _deleteProductOffer(Map<String, dynamic> item) async {
    if (!await _confirm('حذف عرض المنتجات', 'هل تريد حذف هذا العرض نهائياً؟')) return;
    try {
      await OffersRepository.instance.deleteProductOffer(item['id'].toString());
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف العرض: $error')));
    }
  }

  Future<void> _toggleProductOffer(Map<String, dynamic> item, bool active) async {
    await OffersRepository.instance.setProductOfferActive(item['id'].toString(), active);
    await _load();
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
              tabs: [Tab(text: t.t('promotionsTab'), icon: compact ? null : const Icon(Icons.local_offer_rounded)), Tab(text: 'عروض المنتجات', icon: compact ? null : const Icon(Icons.shopping_bag_outlined)), Tab(text: t.t('couponsTab'), icon: compact ? null : const Icon(Icons.confirmation_number_rounded))],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? _ProductsErrorState(message: _error!, onRetry: _load)
              : TabBarView(controller: _tabs, children: [
                  _OfferList(items: _offers, onAdd: () => _editOffer(), onEdit: _editOffer, onDelete: _deleteOffer, onToggle: _toggleOffer),
                  _ProductOfferList(items: _productOffers, onAdd: () => _editProductOffer(), onEdit: _editProductOffer, onToggle: _toggleProductOffer, onDelete: _deleteProductOffer),
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

class _OfferEditorDialog extends StatefulWidget {
  const _OfferEditorDialog({this.item});
  final Map<String,dynamic>? item;
  @override State<_OfferEditorDialog> createState()=>_OfferEditorDialogState();
}

class _OfferEditorDialogState extends State<_OfferEditorDialog> {
  final _key=GlobalKey<FormState>();
  late final TextEditingController _title,_desc,_value,_min,_perCustomer;
  String _type='percentage';
  DateTime _start=DateTime.now(),_end=DateTime.now().add(const Duration(days:7));
  bool _active=true,_saving=false,_removeImage=false;
  PlatformFile? _selectedImage;
  String? _imageUrl,_imagePath;
  @override void initState(){super.initState();final x=widget.item;_title=TextEditingController(text:x?['title']?.toString()??'');_desc=TextEditingController(text:x?['description']?.toString()??'');_value=TextEditingController(text:x==null?'':(x['discount_value'] as num?)?.toString()??'');_min=TextEditingController(text:x==null?'0':(x['minimum_order'] as num?)?.toString()??'0');_perCustomer=TextEditingController(text:x?['per_customer_limit']?.toString()??'');_type=x?['discount_type']?.toString()??'percentage';_start=DateTime.tryParse(x?['start_at']?.toString()??'')??DateTime.now();_end=DateTime.tryParse(x?['end_at']?.toString()??'')??DateTime.now().add(const Duration(days:7));_active=x?['is_active']!=false;_imageUrl=x?['image_url']?.toString();_imagePath=x?['image_path']?.toString();}
  @override void dispose(){for(final c in [_title,_desc,_value,_min,_perCustomer]){c.dispose();}super.dispose();}
  Future<void> _pick(bool start) async {final v=await showDatePicker(context:context,initialDate:start?_start:_end,firstDate:DateTime.now().subtract(const Duration(days:365)),lastDate:DateTime.now().add(const Duration(days:3650)));if(!mounted||v==null)return;setState(()=>start?_start=v:_end=v);}
  Future<void> _pickImage() async {final f=await pickPartnerPhotoFromGallery();if(f!=null&&mounted)setState((){_selectedImage=f;_removeImage=false;});}
  Future<void> _save() async {
    final t=AppStrings.of(context);if(_key.currentState?.validate()!=true||_saving)return;
    if(!_end.isAfter(_start)){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t.t('invalidDateRange'))));return;}
    setState(()=>_saving=true);
    try{
      var imageUrl=_removeImage?null:_imageUrl;var imagePath=_removeImage?null:_imagePath;
      if(_selectedImage?.bytes!=null){final ext=(_selectedImage!.extension??'jpg');final up=await OffersRepository.instance.uploadCampaignImage(bytes:_selectedImage!.bytes!,extension:ext,oldPath:_imagePath);imageUrl=up['url'];imagePath=up['path'];}
      else if(_removeImage){await OffersRepository.instance.removeCampaignImage(_imagePath);}
      await OffersRepository.instance.savePromotion(promotionId:widget.item?['id'] as String?,title:_title.text,description:_desc.text,discountType:_type,discountValue:double.parse(_value.text),minimumOrder:double.tryParse(_min.text)??0,perCustomerLimit:int.tryParse(_perCustomer.text),startAt:_start,endAt:_end,isActive:_active,imageUrl:imageUrl,imagePath:imagePath);
      if(mounted)Navigator.pop(context,true);
    }on PostgrestException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  Widget _imagePicker(){return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    InkWell(onTap:_saving?null:_pickImage,borderRadius:BorderRadius.circular(14),child:Container(height:150,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(color:const Color(0xFFFFFAF6),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFFFD6AD))),child:_selectedImage?.bytes!=null?Image.memory(_selectedImage!.bytes!,fit:BoxFit.cover):(_imageUrl??'').isNotEmpty?PersistentNetworkImage(url:_imageUrl!,fit:BoxFit.cover,cacheWidth:900,placeholder:const Center(child:Icon(Icons.image_outlined,color:AppColors.orange)),errorBuilder:(_,_,_)=>const Center(child:Icon(Icons.add_photo_alternate_outlined,color:AppColors.orange))):Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.add_photo_alternate_outlined,color:AppColors.orange,size:36),const SizedBox(height:6),Text(_txCampaign(context,'إضافة صورة للعرض (اختياري)','زیادکردنی وێنەی ئۆفەر','Add offer image (optional)'),style:const TextStyle(fontWeight:FontWeight.w900))])))),
    if(_selectedImage!=null||(_imageUrl??'').isNotEmpty)Align(alignment:AlignmentDirectional.centerStart,child:TextButton.icon(onPressed:()=>setState((){_selectedImage=null;_imageUrl=null;_removeImage=true;}),icon:const Icon(Icons.delete_outline,color:Colors.red),label:Text(_txCampaign(context,'إزالة الصورة','سڕینەوەی وێنە','Remove image'),style:const TextStyle(color:Colors.red)))),
  ]);}
  @override Widget build(BuildContext context){final t=AppStrings.of(context);return AlertDialog(title:Text(t.t(widget.item==null?'addOffer':'editOffer')),content:SizedBox(width:_adaptiveDialogWidth(context,maxWidth:540),child:Form(key:_key,child:SingleChildScrollView(child:Column(children:[_imagePicker(),const SizedBox(height:10),TextFormField(controller:_title,decoration:InputDecoration(labelText:t.t('offerTitle')),validator:(v)=>v==null||v.trim().isEmpty?t.t('requiredField'):null),const SizedBox(height:10),TextFormField(controller:_desc,minLines:2,maxLines:3,decoration:InputDecoration(labelText:t.t('offerDescription'))),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:_type,decoration:InputDecoration(labelText:t.t('discountType')),items:[DropdownMenuItem(value:'percentage',child:Text(t.t('percentageDiscount'))),DropdownMenuItem(value:'fixed',child:Text(t.t('fixedDiscount')))],onChanged:(v)=>setState(()=>_type=v!)),const SizedBox(height:10),TextFormField(controller:_value,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('discountValue')),validator:(v){final n=double.tryParse(v??'');if(n==null||n<=0||(_type=='percentage'&&n>100))return t.t('invalidDiscount');return null;}),const SizedBox(height:10),TextFormField(controller:_min,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('minimumOrder'))),const SizedBox(height:10),TextFormField(controller:_perCustomer,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('offerPerCustomerLimit'),helperText:t.t('offerPerCustomerLimitHint')),validator:(v){if((v??'').trim().isEmpty)return null;final n=int.tryParse(v!.trim());return n==null||n<=0?t.t('invalidUsageLimit'):null;}),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>_pick(true),icon:const Icon(Icons.calendar_today),label:Text('${t.t('startDate')}: ${_date(_start)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>_pick(false),icon:const Icon(Icons.event),label:Text('${t.t('endDate')}: ${_date(_end)}')))]),SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:Text(t.t('activeOffer')),value:_active,onChanged:(v)=>setState(()=>_active=v),activeThumbColor:AppColors.green)])))),actions:[TextButton(onPressed:_saving?null:()=>Navigator.pop(context,false),child:Text(t.t('cancel'))),FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save),label:Text(t.t('saveOffer')))]);}
}

class _CouponEditorDialog extends StatefulWidget {
  const _CouponEditorDialog({this.item}); final Map<String,dynamic>? item;
  @override State<_CouponEditorDialog> createState()=>_CouponEditorDialogState();
}
class _CouponEditorDialogState extends State<_CouponEditorDialog> {
  final _key=GlobalKey<FormState>(); late final TextEditingController _code,_title,_value,_min,_max,_limit; String _type='percentage'; DateTime _start=DateTime.now(),_end=DateTime.now().add(const Duration(days:30)); bool _active=true,_saving=false,_removeImage=false; PlatformFile? _selectedImage; String? _imageUrl,_imagePath;
  @override void initState(){super.initState();final x=widget.item;_code=TextEditingController(text:x?['code']?.toString()??'');_title=TextEditingController(text:x?['title']?.toString()??'');_value=TextEditingController(text:x==null?'':(x['discount_value'] as num?)?.toString()??'');_min=TextEditingController(text:x==null?'0':(x['minimum_order'] as num?)?.toString()??'0');_max=TextEditingController(text:x==null?'':(x['max_discount'] as num?)?.toString()??'');_limit=TextEditingController(text:x==null?'':x['usage_limit']?.toString()??'');_type=x?['discount_type']?.toString()??'percentage';_start=DateTime.tryParse(x?['start_at']?.toString()??'')??DateTime.now();_end=DateTime.tryParse(x?['end_at']?.toString()??'')??DateTime.now().add(const Duration(days:30));_active=x?['is_active']!=false;_imageUrl=x?['image_url']?.toString();_imagePath=x?['image_path']?.toString();}
  @override void dispose(){for(final c in [_code,_title,_value,_min,_max,_limit]){c.dispose();}super.dispose();}
  Future<void> _pick(bool start) async {final v=await showDatePicker(context:context,initialDate:start?_start:_end,firstDate:DateTime.now().subtract(const Duration(days:365)),lastDate:DateTime.now().add(const Duration(days:3650)));if(!mounted||v==null)return;setState(()=>start?_start=v:_end=v);}
  Future<void> _pickImage() async {final f=await pickPartnerPhotoFromGallery();if(f!=null&&mounted)setState((){_selectedImage=f;_removeImage=false;});}
  Future<void> _save() async {final t=AppStrings.of(context);if(_key.currentState?.validate()!=true||_saving)return;if(!_end.isAfter(_start)){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t.t('invalidDateRange'))));return;}setState(()=>_saving=true);try{var imageUrl=_removeImage?null:_imageUrl;var imagePath=_removeImage?null:_imagePath;if(_selectedImage?.bytes!=null){final up=await OffersRepository.instance.uploadCampaignImage(bytes:_selectedImage!.bytes!,extension:_selectedImage!.extension??'jpg',oldPath:_imagePath);imageUrl=up['url'];imagePath=up['path'];}else if(_removeImage){await OffersRepository.instance.removeCampaignImage(_imagePath);}await OffersRepository.instance.saveCoupon(couponId:widget.item?['id'] as String?,code:_code.text,title:_title.text,discountType:_type,discountValue:double.parse(_value.text),minimumOrder:double.tryParse(_min.text)??0,maxDiscount:double.tryParse(_max.text),usageLimit:int.tryParse(_limit.text),startAt:_start,endAt:_end,isActive:_active,imageUrl:imageUrl,imagePath:imagePath);if(mounted)Navigator.pop(context,true);}on PostgrestException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}finally{if(mounted)setState(()=>_saving=false);}}
  Widget _imagePicker()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[InkWell(onTap:_saving?null:_pickImage,borderRadius:BorderRadius.circular(14),child:Container(height:130,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(color:const Color(0xFFFFFAF6),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFFFD6AD))),child:_selectedImage?.bytes!=null?Image.memory(_selectedImage!.bytes!,fit:BoxFit.cover):(_imageUrl??'').isNotEmpty?PersistentNetworkImage(url:_imageUrl!,fit:BoxFit.cover,cacheWidth:900,placeholder:const Center(child:Icon(Icons.image_outlined,color:AppColors.orange)),errorBuilder:(_,_,_)=>const Center(child:Icon(Icons.add_photo_alternate_outlined,color:AppColors.orange))):Center(child:Text(_txCampaign(context,'إضافة صورة للكوبون (اختياري)','وێنەی کوپۆن','Add coupon image (optional)'),style:const TextStyle(fontWeight:FontWeight.w900))))),if(_selectedImage!=null||(_imageUrl??'').isNotEmpty)Align(alignment:AlignmentDirectional.centerStart,child:TextButton.icon(onPressed:()=>setState((){_selectedImage=null;_imageUrl=null;_removeImage=true;}),icon:const Icon(Icons.delete_outline,color:Colors.red),label:Text(_txCampaign(context,'إزالة الصورة','سڕینەوەی وێنە','Remove image'),style:const TextStyle(color:Colors.red))))]);
  @override Widget build(BuildContext context){final t=AppStrings.of(context);return AlertDialog(title:Text(t.t(widget.item==null?'addCoupon':'editCoupon')),content:SizedBox(width:_adaptiveDialogWidth(context,maxWidth:560),child:Form(key:_key,child:SingleChildScrollView(child:Column(children:[_imagePicker(),const SizedBox(height:10),TextFormField(controller:_code,textCapitalization:TextCapitalization.characters,decoration:InputDecoration(labelText:t.t('couponCode')),validator:(v)=>v==null||v.trim().length<3?t.t('requiredField'):null),const SizedBox(height:10),TextFormField(controller:_title,decoration:InputDecoration(labelText:t.t('couponTitle')),validator:(v)=>v==null||v.trim().isEmpty?t.t('requiredField'):null),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:_type,decoration:InputDecoration(labelText:t.t('discountType')),items:[DropdownMenuItem(value:'percentage',child:Text(t.t('percentageDiscount'))),DropdownMenuItem(value:'fixed',child:Text(t.t('fixedDiscount')))],onChanged:(v)=>setState(()=>_type=v!)),const SizedBox(height:10),TextFormField(controller:_value,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('discountValue')),validator:(v){final n=double.tryParse(v??'');if(n==null||n<=0||(_type=='percentage'&&n>100))return t.t('invalidDiscount');return null;}),const SizedBox(height:10),Row(children:[Expanded(child:TextFormField(controller:_min,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('minimumOrder')))),const SizedBox(width:8),Expanded(child:TextFormField(controller:_max,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('maxDiscount'))))]),const SizedBox(height:10),TextFormField(controller:_limit,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t.t('usageLimit'),helperText:t.t('couponGlobalUsageLimitHint'))),const SizedBox(height:8),Align(alignment:AlignmentDirectional.centerStart,child:Text(t.t('couponSingleUseHint'),style:const TextStyle(fontSize:12,color:AppColors.muted,fontWeight:FontWeight.w700))),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_pick(true),child:Text('${t.t('startDate')}: ${_date(_start)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()=>_pick(false),child:Text('${t.t('endDate')}: ${_date(_end)}')))]),SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:Text(t.t('activeCoupon')),value:_active,onChanged:(v)=>setState(()=>_active=v),activeThumbColor:AppColors.green)])))),actions:[TextButton(onPressed:_saving?null:()=>Navigator.pop(context,false),child:Text(t.t('cancel'))),FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save),label:Text(t.t('saveCoupon')))]);}
}

String _txCampaign(BuildContext context,String ar,String ku,String en){final code=Localizations.localeOf(context).languageCode.toLowerCase();if(code.startsWith('ku'))return ku;if(code.startsWith('en'))return en;return ar;}

String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2,'0')}-${value.day.toString().padLeft(2,'0')}';


// Note 4: independent product offers. General offers and coupon editors stay unchanged.
class _ProductOfferList extends StatelessWidget {
  const _ProductOfferList({required this.items, required this.onAdd, required this.onEdit, required this.onToggle, required this.onDelete});
  final List<Map<String, dynamic>> items;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final ValueChanged<Map<String, dynamic>> onDelete;
  String _discountLabel(Map<String, dynamic> offer) {
    final type = offer['discount_type']?.toString();
    final value = offer['discount_value']?.toString() ?? '';
    if (type == 'percentage') return 'خصم $value%';
    if (type == 'fixed') return 'خصم $value دينار';
    return 'السعر النهائي $value دينار';
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Align(alignment: AlignmentDirectional.centerEnd,
      child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('إضافة عرض منتجات'))),
    const SizedBox(height: 12),
    Expanded(child: items.isEmpty
      ? const Center(child: Text('ماكو عروض منتجات حالياً'))
      : ListView.builder(itemCount: items.length, itemBuilder: (context, index) {
          final offer = items[index];
          final products = offer['product_ids'];
          final count = products is List ? products.length : 0;
          return Card(child: ListTile(
            title: Text(offer['title']?.toString() ?? ''),
            subtitle: Text('$count أصناف • ${_discountLabel(offer)}'),
            onTap: () => onEdit(offer),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () => onEdit(offer)),
              IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => onDelete(offer)),
              Switch.adaptive(value: offer['is_active'] == true, onChanged: (value) => onToggle(offer, value)),
            ]),
          ));
        })),
  ]);
}

class _ProductOfferEditorDialog extends StatefulWidget {
  const _ProductOfferEditorDialog({this.item});
  final Map<String, dynamic>? item;
  @override
  State<_ProductOfferEditorDialog> createState() => _ProductOfferEditorDialogState();
}

class _ProductOfferEditorDialogState extends State<_ProductOfferEditorDialog> {
  final _title = TextEditingController();
  final _value = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  String? _openCategoryId;
  final Set<String> _selected = {};
  final Map<String, int> _quantities = {};
  String _type = 'percentage';
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 7));
  bool _active = true, _loading = true, _saving = false;
  String? _error;
  PlatformFile? _offerImage;
  String? _offerImageUrl, _offerImagePath;
  bool _removeOfferImage = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _offerImageUrl = item['image_url']?.toString();
      _offerImagePath = item['image_path']?.toString();
      _title.text = item['title']?.toString() ?? '';
      _value.text = item['discount_value']?.toString() ?? '';
      _type = item['discount_type']?.toString() ?? 'percentage';
      _active = item['is_active'] == true;
      _start = DateTime.tryParse(item['start_at']?.toString() ?? '')?.toLocal() ?? _start;
      _end = DateTime.tryParse(item['end_at']?.toString() ?? '')?.toLocal() ?? _end;
      if (item['product_ids'] is List) {
        _selected.addAll((item['product_ids'] as List).map((e) => e.toString()));
        final saved = item['product_quantities'];
        if (saved is Map) {
          for (final entry in saved.entries) {
            final qty = int.tryParse(entry.value.toString()) ?? 1;
            if (qty >= 1 && qty <= 999) _quantities[entry.key.toString()] = qty;
          }
        }
      }
    }
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final results = await Future.wait([
        ProductsRepository.instance.getStoreProducts(),
        ProductsRepository.instance.getStoreCategories(),
      ]);
      if (mounted) {
        setState(() {
          _products = results[0];
          _categories = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _chooseDate(bool start) async {
    final current = start ? _start : _end;
    final date = await showDatePicker(context: context, firstDate: DateTime(2020),
      lastDate: DateTime(2100), initialDate: current);
    if (date != null && mounted) {
      setState(() {
        if (start) { _start = date; } else { _end = date.add(const Duration(hours: 23, minutes: 59)); }
      });
    }
  }

  Future<void> _pickOfferImage() async {
    final photo = await pickPartnerPhotoWithCamera(context);
    if (photo != null && mounted) setState(() { _offerImage = photo; _removeOfferImage = false; });
  }

  Future<void> _save() async {
    final value = double.tryParse(_value.text.trim());
    if (_title.text.trim().isEmpty || _selected.isEmpty || value == null || value < 0 ||
        (_type == 'percentage' && (value <= 0 || value > 100)) ||
        (_type == 'fixed' && value <= 0) || !_end.isAfter(_start)) {
      setState(() => _error = 'تأكد من الاسم والأصناف وقيمة الخصم والتواريخ');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      var imageUrl = _removeOfferImage ? null : _offerImageUrl;
      var imagePath = _removeOfferImage ? null : _offerImagePath;
      if (_offerImage?.bytes != null) {
        final uploaded = await OffersRepository.instance.uploadCampaignImage(
          bytes: _offerImage!.bytes!, extension: _offerImage!.extension ?? 'jpg');
        imageUrl = uploaded['url'];
        imagePath = uploaded['path'];
      }
      await OffersRepository.instance.saveProductOffer(
        offerId: widget.item?['id']?.toString(), title: _title.text,
        productIds: _selected.toList(), productQuantities: {for (final id in _selected) id: _quantities[id] ?? 1}, discountType: _type,
        discountValue: value, startAt: _start, endAt: _end, isActive: _active,
        imageUrl: imageUrl, imagePath: imagePath);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCurrentOffer() async {
    final id = widget.item?['id']?.toString();
    if (id == null || _saving) return;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('حذف عرض المنتجات'),
      content: const Text('هل تريد حذف هذا العرض نهائياً؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
      ],
    )) ?? false;
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await OffersRepository.instance.deleteProductOffer(id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _saving = false; });
    }
  }

  @override
  void dispose() { _title.dispose(); _value.dispose(); super.dispose(); }

  // The offer is priced from all selected units, not one unit per product.
  double get _selectedOriginalTotal {
    var total = 0.0;
    for (final product in _products) {
      final id = product['id']?.toString() ?? '';
      if (!_selected.contains(id)) continue;
      final price = num.tryParse(product['price']?.toString() ?? '') ?? 0;
      total += price * (_quantities[id] ?? 1);
    }
    return total;
  }

  String _formatOfferMoney(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

  Widget _offerProductCheckbox(Map<String, dynamic> product) {
    final id = product['id']?.toString() ?? '';
    final checked = _selected.contains(id);
    final qty = _quantities[id] ?? 1;
    final unitPrice = num.tryParse(product['price']?.toString() ?? '') ?? 0;
    return Row(children: [
      Expanded(child: CheckboxListTile(
        dense: true,
        title: Text(product['name']?.toString() ?? ''),
        subtitle: Text(checked
            ? 'سعر القطعة: ${_formatOfferMoney(unitPrice)} • المجموع: ${_formatOfferMoney(unitPrice * qty)} د.ع'
            : 'سعر القطعة: ${_formatOfferMoney(unitPrice)} د.ع'),
        value: checked,
        onChanged: (value) => setState(() {
          if (value == true) { _selected.add(id); _quantities.putIfAbsent(id, () => 1); }
          else { _selected.remove(id); _quantities.remove(id); }
        }),
      )),
      if (checked) ...[
        IconButton(icon: const Icon(Icons.remove_circle_outline),
          onPressed: qty > 1 ? () => setState(() => _quantities[id] = qty - 1) : null),
        Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(icon: const Icon(Icons.add_circle_outline),
          onPressed: qty < 999 ? () => setState(() => _quantities[id] = qty + 1) : null),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? 'إضافة عرض منتجات' : 'تعديل عرض المنتجات'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(onTap: _saving ? null : _pickOfferImage, child: Container(
          height: 150, clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFFFFFAF6), borderRadius: BorderRadius.circular(14)),
          child: _offerImage?.bytes != null
            ? Image.memory(_offerImage!.bytes!, fit: BoxFit.cover)
            : (_offerImageUrl ?? '').isNotEmpty && !_removeOfferImage
              ? PersistentNetworkImage(url: _offerImageUrl!, fit: BoxFit.cover,
                  placeholder: const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.add_photo_alternate_outlined)))
              : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined, size: 35), Text('صورة العرض: الاستوديو أو الكاميرا')]),
        )),
        if (_offerImage != null || ((_offerImageUrl ?? '').isNotEmpty && !_removeOfferImage))
          TextButton.icon(onPressed: () => setState(() {
            _offerImage = null; _offerImageUrl = null; _removeOfferImage = true;
          }), icon: const Icon(Icons.delete_outline), label: const Text('إزالة صورة العرض')),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'عنوان العرض')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _type,
          decoration: const InputDecoration(labelText: 'نوع الخصم'),
          items: const [
            DropdownMenuItem(value: 'percentage', child: Text('نسبة مئوية')),
            DropdownMenuItem(value: 'fixed', child: Text('مبلغ خصم ثابت')),
            DropdownMenuItem(value: 'final_price', child: Text('سعر نهائي للصنف')),
          ], onChanged: (value) { if (value != null) setState(() => _type = value); }),
        TextField(controller: _value, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _type == 'final_price' ? 'السعر بعد الخصم' : 'قيمة الخصم')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: () => _chooseDate(true), child: Text('من ${_start.year}/${_start.month}/${_start.day}')),
          OutlinedButton(onPressed: () => _chooseDate(false), child: Text('إلى ${_end.year}/${_end.month}/${_end.day}')),
        ]),
        SwitchListTile(title: const Text('العرض فعال'), value: _active,
          onChanged: (value) => setState(() => _active = value)),
        if (_selected.isNotEmpty) Builder(builder: (_) {
          final original = _selectedOriginalTotal;
          final value = double.tryParse(_value.text.trim()) ?? 0;
          final discount = _type == 'percentage'
              ? original * value.clamp(0, 100) / 100
              : _type == 'fixed' ? value.clamp(0, original).toDouble()
              : (original - value).clamp(0, original).toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'مجموع الأصناف حسب الكميات: ${_formatOfferMoney(original)} د.ع\n'
              'السعر بعد الخصم: ${_formatOfferMoney(original - discount)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }),
        const Text('اختر الأصناف المشمولة بالعرض', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('إذا اخترت صنفاً واحداً ينطبق الخصم على كل قطعة. وإذا اخترت عدة أصناف فهي مجموعة كومبو ولا يكتمل الخصم إلا بوجود جميع الأصناف معاً. تكرار المجموعة يكرر الخصم.', style: TextStyle(fontSize: 12)),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _products.isEmpty) const Text('ماكو أصناف متاحة'),
        if (!_loading) SizedBox(height: 290, child: ListView(
          children: [
            for (final category in _categories) ...[
              Builder(builder: (context) {
                final categoryId = category['id']?.toString() ?? '';
                final categoryProducts = _products.where((product) =>
                  product['category_id']?.toString() == categoryId).toList();
                if (categoryProducts.isEmpty) return const SizedBox.shrink();
                final isOpen = _openCategoryId == categoryId;
                return Column(children: [
                  ListTile(
                    title: Text(category['name']?.toString() ?? 'قسم'),
                    subtitle: Text('${categoryProducts.length} أصناف'),
                    trailing: Icon(isOpen ? Icons.expand_less : Icons.expand_more),
                    onTap: () => setState(() => _openCategoryId = isOpen ? null : categoryId),
                  ),
                  if (isOpen) for (final product in categoryProducts)
                    _offerProductCheckbox(product),
                ]);
              }),
            ],
            if (_categories.isEmpty || _products.any((product) =>
                product['category_id'] == null ||
                !_categories.any((category) => category['id']?.toString() == product['category_id']?.toString()))) ...[
              const ListTile(title: Text('أصناف بدون قسم')),
              for (final product in _products.where((product) =>
                product['category_id'] == null ||
                !_categories.any((category) => category['id']?.toString() == product['category_id']?.toString())))
                _offerProductCheckbox(product),
            ],
          ],
        )),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      ],
    ))),
    actions: [
      if (widget.item != null) TextButton.icon(
        onPressed: _saving ? null : _deleteCurrentOffer,
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: const Text('حذف العرض', style: TextStyle(color: Colors.red))),
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('إلغاء')),
      FilledButton(onPressed: _saving || _loading ? null : _save, child: const Text('حفظ العرض')),
    ],
  );
}
