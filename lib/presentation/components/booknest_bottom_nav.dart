import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';

/// Animated, glass-like navigation inspired by Telegram's responsive controls.
class BookNestBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  const BookNestBottomNav({super.key, required this.currentIndex, required this.onTap});
  @override State<BookNestBottomNav> createState() => _BookNestBottomNavState();
}
class _BookNestBottomNavState extends State<BookNestBottomNav> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync:this, duration:const Duration(milliseconds:240));
  @override void dispose(){_pulse.dispose();super.dispose();}
  @override Widget build(BuildContext context) { final dark=Theme.of(context).brightness==Brightness.dark; final surface=dark?BookNestColors.darkChatBackground:Colors.white; final border=dark?BookNestColors.darkBorder:BookNestColors.lightBorder; final inactive=dark?BookNestColors.darkTextSecondary:BookNestColors.lightTextSecondary; return SizedBox(height:92,child:Stack(alignment:Alignment.bottomCenter,clipBehavior:Clip.none,children:[Container(height:64,margin:const EdgeInsets.fromLTRB(16,12,16,8),decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),boxShadow:[BoxShadow(color:BookNestColors.navyDeep.withOpacity(.18),blurRadius:20,offset:const Offset(0,8))]),child:ClipRRect(borderRadius:BorderRadius.circular(24),child:BackdropFilter(filter:ImageFilter.blur(sigmaX:14,sigmaY:14),child:DecoratedBox(decoration:BoxDecoration(color:surface.withOpacity(dark ? .78 : .92),borderRadius:BorderRadius.circular(24),border:Border.all(color:border)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[_tab(0,Icons.view_agenda_outlined,inactive),_tab(1,Icons.explore_outlined,inactive),const SizedBox(width:56),_tab(3,Icons.chat_bubble_outline,inactive),_tab(4,Icons.person_outline,inactive)]))))),Positioned(top:0,child:GestureDetector(onTap:(){HapticFeedback.selectionClick();_pulse.forward(from:0).then((_)=>_pulse.reverse());widget.onTap(2);},child:AnimatedBuilder(animation:_pulse,builder:(_,__)=>Transform.scale(scale:widget.currentIndex==2?1+_pulse.value*.1:1,child:Container(width:64,height:64,decoration:BoxDecoration(shape:BoxShape.circle,gradient:const LinearGradient(colors:[BookNestColors.navy,BookNestColors.navyDeep]),border:Border.all(color:BookNestColors.cyan.withOpacity(.7)),boxShadow:[BoxShadow(color:BookNestColors.cyan.withOpacity(.25),blurRadius:18)]),child:const Icon(Icons.menu_book_rounded,color:Colors.white)))))])); }
  Widget _tab(int index,IconData icon,Color inactive){final selected=widget.currentIndex==index;return Semantics(button:true,selected:selected,child:InkResponse(onTap:()=>widget.onTap(index),radius:28,child:AnimatedContainer(duration:const Duration(milliseconds:220),curve:Curves.easeOutCubic,padding:const EdgeInsets.all(11),decoration:BoxDecoration(shape:BoxShape.circle,color:selected?BookNestColors.cyan.withOpacity(.15):Colors.transparent),child:Icon(icon,color:selected?BookNestColors.cyan:inactive))));}
}
