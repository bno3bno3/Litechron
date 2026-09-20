import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:litechron/model/option.dart';

class CourseIdMapAdapter extends TypeAdapter<CourseIdMap> {
  @override
  final typeId = 13;

  @override
  void write(BinaryWriter writer, CourseIdMap obj) =>
      writer.writeString(jsonEncode(obj));

  @override
  CourseIdMap read(BinaryReader reader) =>
      CourseIdMap.fromJson(jsonDecode(reader.readString()));
}
