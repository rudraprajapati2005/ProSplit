// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ExpenseModelImpl _$$ExpenseModelImplFromJson(Map<String, dynamic> json) =>
    _$ExpenseModelImpl(
      id: json['id'] as String,
      title: json['title'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: json['category'] as String,
      description: json['description'] as String,
      paidBy: json['paidBy'] as String,
      splitBetween: (json['splitBetween'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      date: DateTime.parse(json['date'] as String),
      groupId: json['groupId'] as String,
      isSettled: json['isSettled'] as bool? ?? false,
    );

Map<String, dynamic> _$$ExpenseModelImplToJson(_$ExpenseModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'amount': instance.amount,
      'category': instance.category,
      'description': instance.description,
      'paidBy': instance.paidBy,
      'splitBetween': instance.splitBetween,
      'date': instance.date.toIso8601String(),
      'groupId': instance.groupId,
      'isSettled': instance.isSettled,
    };
