// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deadlineUtcMeta = const VerificationMeta(
    'deadlineUtc',
  );
  @override
  late final GeneratedColumn<int> deadlineUtc = GeneratedColumn<int>(
    'deadline_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedMinutesMeta = const VerificationMeta(
    'estimatedMinutes',
  );
  @override
  late final GeneratedColumn<int> estimatedMinutes = GeneratedColumn<int>(
    'estimated_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Priority, String> priority =
      GeneratedColumn<String>(
        'priority',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Priority>($TasksTable.$converterpriority);
  @override
  late final GeneratedColumnWithTypeConverter<TaskStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TaskStatus>($TasksTable.$converterstatus);
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TaskSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TaskSource>($TasksTable.$convertersource);
  @override
  late final GeneratedColumnWithTypeConverter<TaskDepth, String> depth =
      GeneratedColumn<String>(
        'depth',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('unknown'),
      ).withConverter<TaskDepth>($TasksTable.$converterdepth);
  static const VerificationMeta _actualMinutesMeta = const VerificationMeta(
    'actualMinutes',
  );
  @override
  late final GeneratedColumn<int> actualMinutes = GeneratedColumn<int>(
    'actual_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    notes,
    deadlineUtc,
    estimatedMinutes,
    priority,
    status,
    createdUtc,
    source,
    depth,
    actualMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('deadline_utc')) {
      context.handle(
        _deadlineUtcMeta,
        deadlineUtc.isAcceptableOrUnknown(
          data['deadline_utc']!,
          _deadlineUtcMeta,
        ),
      );
    }
    if (data.containsKey('estimated_minutes')) {
      context.handle(
        _estimatedMinutesMeta,
        estimatedMinutes.isAcceptableOrUnknown(
          data['estimated_minutes']!,
          _estimatedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('actual_minutes')) {
      context.handle(
        _actualMinutesMeta,
        actualMinutes.isAcceptableOrUnknown(
          data['actual_minutes']!,
          _actualMinutesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      deadlineUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deadline_utc'],
      ),
      estimatedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_minutes'],
      ),
      priority: $TasksTable.$converterpriority.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}priority'],
        )!,
      ),
      status: $TasksTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      source: $TasksTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      depth: $TasksTable.$converterdepth.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}depth'],
        )!,
      ),
      actualMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_minutes'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Priority, String, String> $converterpriority =
      const EnumNameConverter<Priority>(Priority.values);
  static JsonTypeConverter2<TaskStatus, String, String> $converterstatus =
      const EnumNameConverter<TaskStatus>(TaskStatus.values);
  static JsonTypeConverter2<TaskSource, String, String> $convertersource =
      const EnumNameConverter<TaskSource>(TaskSource.values);
  static JsonTypeConverter2<TaskDepth, String, String> $converterdepth =
      const EnumNameConverter<TaskDepth>(TaskDepth.values);
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final String id;
  final String title;
  final String? notes;
  final int? deadlineUtc;
  final int? estimatedMinutes;
  final Priority priority;
  final TaskStatus status;
  final int createdUtc;
  final TaskSource source;

  /// Whether starting this is itself the work. Added in v4.
  ///
  /// Defaulted rather than nullable so every row upgraded from v3 reads back
  /// as `unknown`, which is exactly what is true of them: nothing read their
  /// depth, and a null that the mapper had to guess at would be a second
  /// place for that guess to be made.
  final TaskDepth depth;

  /// How long the work actually took, once someone said. Added in v5.
  ///
  /// Nullable rather than defaulted, because "nobody has said" and "it took
  /// no time" are different facts and only one of them is ever true.
  final int? actualMinutes;
  const TaskRow({
    required this.id,
    required this.title,
    this.notes,
    this.deadlineUtc,
    this.estimatedMinutes,
    required this.priority,
    required this.status,
    required this.createdUtc,
    required this.source,
    required this.depth,
    this.actualMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || deadlineUtc != null) {
      map['deadline_utc'] = Variable<int>(deadlineUtc);
    }
    if (!nullToAbsent || estimatedMinutes != null) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes);
    }
    {
      map['priority'] = Variable<String>(
        $TasksTable.$converterpriority.toSql(priority),
      );
    }
    {
      map['status'] = Variable<String>(
        $TasksTable.$converterstatus.toSql(status),
      );
    }
    map['created_utc'] = Variable<int>(createdUtc);
    {
      map['source'] = Variable<String>(
        $TasksTable.$convertersource.toSql(source),
      );
    }
    {
      map['depth'] = Variable<String>($TasksTable.$converterdepth.toSql(depth));
    }
    if (!nullToAbsent || actualMinutes != null) {
      map['actual_minutes'] = Variable<int>(actualMinutes);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      title: Value(title),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      deadlineUtc: deadlineUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(deadlineUtc),
      estimatedMinutes: estimatedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedMinutes),
      priority: Value(priority),
      status: Value(status),
      createdUtc: Value(createdUtc),
      source: Value(source),
      depth: Value(depth),
      actualMinutes: actualMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(actualMinutes),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String?>(json['notes']),
      deadlineUtc: serializer.fromJson<int?>(json['deadlineUtc']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      priority: $TasksTable.$converterpriority.fromJson(
        serializer.fromJson<String>(json['priority']),
      ),
      status: $TasksTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      source: $TasksTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      depth: $TasksTable.$converterdepth.fromJson(
        serializer.fromJson<String>(json['depth']),
      ),
      actualMinutes: serializer.fromJson<int?>(json['actualMinutes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String?>(notes),
      'deadlineUtc': serializer.toJson<int?>(deadlineUtc),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'priority': serializer.toJson<String>(
        $TasksTable.$converterpriority.toJson(priority),
      ),
      'status': serializer.toJson<String>(
        $TasksTable.$converterstatus.toJson(status),
      ),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'source': serializer.toJson<String>(
        $TasksTable.$convertersource.toJson(source),
      ),
      'depth': serializer.toJson<String>(
        $TasksTable.$converterdepth.toJson(depth),
      ),
      'actualMinutes': serializer.toJson<int?>(actualMinutes),
    };
  }

  TaskRow copyWith({
    String? id,
    String? title,
    Value<String?> notes = const Value.absent(),
    Value<int?> deadlineUtc = const Value.absent(),
    Value<int?> estimatedMinutes = const Value.absent(),
    Priority? priority,
    TaskStatus? status,
    int? createdUtc,
    TaskSource? source,
    TaskDepth? depth,
    Value<int?> actualMinutes = const Value.absent(),
  }) => TaskRow(
    id: id ?? this.id,
    title: title ?? this.title,
    notes: notes.present ? notes.value : this.notes,
    deadlineUtc: deadlineUtc.present ? deadlineUtc.value : this.deadlineUtc,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    createdUtc: createdUtc ?? this.createdUtc,
    source: source ?? this.source,
    depth: depth ?? this.depth,
    actualMinutes: actualMinutes.present
        ? actualMinutes.value
        : this.actualMinutes,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      deadlineUtc: data.deadlineUtc.present
          ? data.deadlineUtc.value
          : this.deadlineUtc,
      estimatedMinutes: data.estimatedMinutes.present
          ? data.estimatedMinutes.value
          : this.estimatedMinutes,
      priority: data.priority.present ? data.priority.value : this.priority,
      status: data.status.present ? data.status.value : this.status,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      source: data.source.present ? data.source.value : this.source,
      depth: data.depth.present ? data.depth.value : this.depth,
      actualMinutes: data.actualMinutes.present
          ? data.actualMinutes.value
          : this.actualMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('deadlineUtc: $deadlineUtc, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('source: $source, ')
          ..write('depth: $depth, ')
          ..write('actualMinutes: $actualMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    deadlineUtc,
    estimatedMinutes,
    priority,
    status,
    createdUtc,
    source,
    depth,
    actualMinutes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.deadlineUtc == this.deadlineUtc &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.priority == this.priority &&
          other.status == this.status &&
          other.createdUtc == this.createdUtc &&
          other.source == this.source &&
          other.depth == this.depth &&
          other.actualMinutes == this.actualMinutes);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> notes;
  final Value<int?> deadlineUtc;
  final Value<int?> estimatedMinutes;
  final Value<Priority> priority;
  final Value<TaskStatus> status;
  final Value<int> createdUtc;
  final Value<TaskSource> source;
  final Value<TaskDepth> depth;
  final Value<int?> actualMinutes;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.deadlineUtc = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.source = const Value.absent(),
    this.depth = const Value.absent(),
    this.actualMinutes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String title,
    this.notes = const Value.absent(),
    this.deadlineUtc = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    required Priority priority,
    required TaskStatus status,
    required int createdUtc,
    required TaskSource source,
    this.depth = const Value.absent(),
    this.actualMinutes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       priority = Value(priority),
       status = Value(status),
       createdUtc = Value(createdUtc),
       source = Value(source);
  static Insertable<TaskRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<int>? deadlineUtc,
    Expression<int>? estimatedMinutes,
    Expression<String>? priority,
    Expression<String>? status,
    Expression<int>? createdUtc,
    Expression<String>? source,
    Expression<String>? depth,
    Expression<int>? actualMinutes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (deadlineUtc != null) 'deadline_utc': deadlineUtc,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (source != null) 'source': source,
      if (depth != null) 'depth': depth,
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? notes,
    Value<int?>? deadlineUtc,
    Value<int?>? estimatedMinutes,
    Value<Priority>? priority,
    Value<TaskStatus>? status,
    Value<int>? createdUtc,
    Value<TaskSource>? source,
    Value<TaskDepth>? depth,
    Value<int?>? actualMinutes,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      deadlineUtc: deadlineUtc ?? this.deadlineUtc,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdUtc: createdUtc ?? this.createdUtc,
      source: source ?? this.source,
      depth: depth ?? this.depth,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (deadlineUtc.present) {
      map['deadline_utc'] = Variable<int>(deadlineUtc.value);
    }
    if (estimatedMinutes.present) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(
        $TasksTable.$converterpriority.toSql(priority.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $TasksTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $TasksTable.$convertersource.toSql(source.value),
      );
    }
    if (depth.present) {
      map['depth'] = Variable<String>(
        $TasksTable.$converterdepth.toSql(depth.value),
      );
    }
    if (actualMinutes.present) {
      map['actual_minutes'] = Variable<int>(actualMinutes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('deadlineUtc: $deadlineUtc, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('source: $source, ')
          ..write('depth: $depth, ')
          ..write('actualMinutes: $actualMinutes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkSessionsTable extends WorkSessions
    with TableInfo<$WorkSessionsTable, WorkSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _plannedStartUtcMeta = const VerificationMeta(
    'plannedStartUtc',
  );
  @override
  late final GeneratedColumn<int> plannedStartUtc = GeneratedColumn<int>(
    'planned_start_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plannedMinutesMeta = const VerificationMeta(
    'plannedMinutes',
  );
  @override
  late final GeneratedColumn<int> plannedMinutes = GeneratedColumn<int>(
    'planned_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualStartUtcMeta = const VerificationMeta(
    'actualStartUtc',
  );
  @override
  late final GeneratedColumn<int> actualStartUtc = GeneratedColumn<int>(
    'actual_start_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualEndUtcMeta = const VerificationMeta(
    'actualEndUtc',
  );
  @override
  late final GeneratedColumn<int> actualEndUtc = GeneratedColumn<int>(
    'actual_end_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SessionStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SessionStatus>($WorkSessionsTable.$converterstatus);
  static const VerificationMeta _rescheduleCountMeta = const VerificationMeta(
    'rescheduleCount',
  );
  @override
  late final GeneratedColumn<int> rescheduleCount = GeneratedColumn<int>(
    'reschedule_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _parentSessionIdMeta = const VerificationMeta(
    'parentSessionId',
  );
  @override
  late final GeneratedColumn<String> parentSessionId = GeneratedColumn<String>(
    'parent_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOpenerMeta = const VerificationMeta(
    'isOpener',
  );
  @override
  late final GeneratedColumn<bool> isOpener = GeneratedColumn<bool>(
    'is_opener',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_opener" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    plannedStartUtc,
    plannedMinutes,
    actualStartUtc,
    actualEndUtc,
    status,
    rescheduleCount,
    parentSessionId,
    isOpener,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('planned_start_utc')) {
      context.handle(
        _plannedStartUtcMeta,
        plannedStartUtc.isAcceptableOrUnknown(
          data['planned_start_utc']!,
          _plannedStartUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plannedStartUtcMeta);
    }
    if (data.containsKey('planned_minutes')) {
      context.handle(
        _plannedMinutesMeta,
        plannedMinutes.isAcceptableOrUnknown(
          data['planned_minutes']!,
          _plannedMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plannedMinutesMeta);
    }
    if (data.containsKey('actual_start_utc')) {
      context.handle(
        _actualStartUtcMeta,
        actualStartUtc.isAcceptableOrUnknown(
          data['actual_start_utc']!,
          _actualStartUtcMeta,
        ),
      );
    }
    if (data.containsKey('actual_end_utc')) {
      context.handle(
        _actualEndUtcMeta,
        actualEndUtc.isAcceptableOrUnknown(
          data['actual_end_utc']!,
          _actualEndUtcMeta,
        ),
      );
    }
    if (data.containsKey('reschedule_count')) {
      context.handle(
        _rescheduleCountMeta,
        rescheduleCount.isAcceptableOrUnknown(
          data['reschedule_count']!,
          _rescheduleCountMeta,
        ),
      );
    }
    if (data.containsKey('parent_session_id')) {
      context.handle(
        _parentSessionIdMeta,
        parentSessionId.isAcceptableOrUnknown(
          data['parent_session_id']!,
          _parentSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('is_opener')) {
      context.handle(
        _isOpenerMeta,
        isOpener.isAcceptableOrUnknown(data['is_opener']!, _isOpenerMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkSessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      plannedStartUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_start_utc'],
      )!,
      plannedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_minutes'],
      )!,
      actualStartUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_start_utc'],
      ),
      actualEndUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_end_utc'],
      ),
      status: $WorkSessionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      rescheduleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reschedule_count'],
      )!,
      parentSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_session_id'],
      ),
      isOpener: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_opener'],
      )!,
    );
  }

  @override
  $WorkSessionsTable createAlias(String alias) {
    return $WorkSessionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SessionStatus, String, String> $converterstatus =
      const EnumNameConverter<SessionStatus>(SessionStatus.values);
}

class WorkSessionRow extends DataClass implements Insertable<WorkSessionRow> {
  final String id;
  final String taskId;
  final int plannedStartUtc;
  final int plannedMinutes;
  final int? actualStartUtc;
  final int? actualEndUtc;
  final SessionStatus status;
  final int rescheduleCount;
  final String? parentSessionId;

  /// Whether this block is for finding the first step rather than doing the
  /// work. Added in v4; false for everything that existed before it.
  final bool isOpener;
  const WorkSessionRow({
    required this.id,
    required this.taskId,
    required this.plannedStartUtc,
    required this.plannedMinutes,
    this.actualStartUtc,
    this.actualEndUtc,
    required this.status,
    required this.rescheduleCount,
    this.parentSessionId,
    required this.isOpener,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['planned_start_utc'] = Variable<int>(plannedStartUtc);
    map['planned_minutes'] = Variable<int>(plannedMinutes);
    if (!nullToAbsent || actualStartUtc != null) {
      map['actual_start_utc'] = Variable<int>(actualStartUtc);
    }
    if (!nullToAbsent || actualEndUtc != null) {
      map['actual_end_utc'] = Variable<int>(actualEndUtc);
    }
    {
      map['status'] = Variable<String>(
        $WorkSessionsTable.$converterstatus.toSql(status),
      );
    }
    map['reschedule_count'] = Variable<int>(rescheduleCount);
    if (!nullToAbsent || parentSessionId != null) {
      map['parent_session_id'] = Variable<String>(parentSessionId);
    }
    map['is_opener'] = Variable<bool>(isOpener);
    return map;
  }

  WorkSessionsCompanion toCompanion(bool nullToAbsent) {
    return WorkSessionsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      plannedStartUtc: Value(plannedStartUtc),
      plannedMinutes: Value(plannedMinutes),
      actualStartUtc: actualStartUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(actualStartUtc),
      actualEndUtc: actualEndUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(actualEndUtc),
      status: Value(status),
      rescheduleCount: Value(rescheduleCount),
      parentSessionId: parentSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentSessionId),
      isOpener: Value(isOpener),
    );
  }

  factory WorkSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkSessionRow(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      plannedStartUtc: serializer.fromJson<int>(json['plannedStartUtc']),
      plannedMinutes: serializer.fromJson<int>(json['plannedMinutes']),
      actualStartUtc: serializer.fromJson<int?>(json['actualStartUtc']),
      actualEndUtc: serializer.fromJson<int?>(json['actualEndUtc']),
      status: $WorkSessionsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      rescheduleCount: serializer.fromJson<int>(json['rescheduleCount']),
      parentSessionId: serializer.fromJson<String?>(json['parentSessionId']),
      isOpener: serializer.fromJson<bool>(json['isOpener']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'plannedStartUtc': serializer.toJson<int>(plannedStartUtc),
      'plannedMinutes': serializer.toJson<int>(plannedMinutes),
      'actualStartUtc': serializer.toJson<int?>(actualStartUtc),
      'actualEndUtc': serializer.toJson<int?>(actualEndUtc),
      'status': serializer.toJson<String>(
        $WorkSessionsTable.$converterstatus.toJson(status),
      ),
      'rescheduleCount': serializer.toJson<int>(rescheduleCount),
      'parentSessionId': serializer.toJson<String?>(parentSessionId),
      'isOpener': serializer.toJson<bool>(isOpener),
    };
  }

  WorkSessionRow copyWith({
    String? id,
    String? taskId,
    int? plannedStartUtc,
    int? plannedMinutes,
    Value<int?> actualStartUtc = const Value.absent(),
    Value<int?> actualEndUtc = const Value.absent(),
    SessionStatus? status,
    int? rescheduleCount,
    Value<String?> parentSessionId = const Value.absent(),
    bool? isOpener,
  }) => WorkSessionRow(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    plannedStartUtc: plannedStartUtc ?? this.plannedStartUtc,
    plannedMinutes: plannedMinutes ?? this.plannedMinutes,
    actualStartUtc: actualStartUtc.present
        ? actualStartUtc.value
        : this.actualStartUtc,
    actualEndUtc: actualEndUtc.present ? actualEndUtc.value : this.actualEndUtc,
    status: status ?? this.status,
    rescheduleCount: rescheduleCount ?? this.rescheduleCount,
    parentSessionId: parentSessionId.present
        ? parentSessionId.value
        : this.parentSessionId,
    isOpener: isOpener ?? this.isOpener,
  );
  WorkSessionRow copyWithCompanion(WorkSessionsCompanion data) {
    return WorkSessionRow(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      plannedStartUtc: data.plannedStartUtc.present
          ? data.plannedStartUtc.value
          : this.plannedStartUtc,
      plannedMinutes: data.plannedMinutes.present
          ? data.plannedMinutes.value
          : this.plannedMinutes,
      actualStartUtc: data.actualStartUtc.present
          ? data.actualStartUtc.value
          : this.actualStartUtc,
      actualEndUtc: data.actualEndUtc.present
          ? data.actualEndUtc.value
          : this.actualEndUtc,
      status: data.status.present ? data.status.value : this.status,
      rescheduleCount: data.rescheduleCount.present
          ? data.rescheduleCount.value
          : this.rescheduleCount,
      parentSessionId: data.parentSessionId.present
          ? data.parentSessionId.value
          : this.parentSessionId,
      isOpener: data.isOpener.present ? data.isOpener.value : this.isOpener,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkSessionRow(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('plannedStartUtc: $plannedStartUtc, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('actualStartUtc: $actualStartUtc, ')
          ..write('actualEndUtc: $actualEndUtc, ')
          ..write('status: $status, ')
          ..write('rescheduleCount: $rescheduleCount, ')
          ..write('parentSessionId: $parentSessionId, ')
          ..write('isOpener: $isOpener')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    plannedStartUtc,
    plannedMinutes,
    actualStartUtc,
    actualEndUtc,
    status,
    rescheduleCount,
    parentSessionId,
    isOpener,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkSessionRow &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.plannedStartUtc == this.plannedStartUtc &&
          other.plannedMinutes == this.plannedMinutes &&
          other.actualStartUtc == this.actualStartUtc &&
          other.actualEndUtc == this.actualEndUtc &&
          other.status == this.status &&
          other.rescheduleCount == this.rescheduleCount &&
          other.parentSessionId == this.parentSessionId &&
          other.isOpener == this.isOpener);
}

class WorkSessionsCompanion extends UpdateCompanion<WorkSessionRow> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<int> plannedStartUtc;
  final Value<int> plannedMinutes;
  final Value<int?> actualStartUtc;
  final Value<int?> actualEndUtc;
  final Value<SessionStatus> status;
  final Value<int> rescheduleCount;
  final Value<String?> parentSessionId;
  final Value<bool> isOpener;
  final Value<int> rowid;
  const WorkSessionsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.plannedStartUtc = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    this.actualStartUtc = const Value.absent(),
    this.actualEndUtc = const Value.absent(),
    this.status = const Value.absent(),
    this.rescheduleCount = const Value.absent(),
    this.parentSessionId = const Value.absent(),
    this.isOpener = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkSessionsCompanion.insert({
    required String id,
    required String taskId,
    required int plannedStartUtc,
    required int plannedMinutes,
    this.actualStartUtc = const Value.absent(),
    this.actualEndUtc = const Value.absent(),
    required SessionStatus status,
    this.rescheduleCount = const Value.absent(),
    this.parentSessionId = const Value.absent(),
    this.isOpener = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       plannedStartUtc = Value(plannedStartUtc),
       plannedMinutes = Value(plannedMinutes),
       status = Value(status);
  static Insertable<WorkSessionRow> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<int>? plannedStartUtc,
    Expression<int>? plannedMinutes,
    Expression<int>? actualStartUtc,
    Expression<int>? actualEndUtc,
    Expression<String>? status,
    Expression<int>? rescheduleCount,
    Expression<String>? parentSessionId,
    Expression<bool>? isOpener,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (plannedStartUtc != null) 'planned_start_utc': plannedStartUtc,
      if (plannedMinutes != null) 'planned_minutes': plannedMinutes,
      if (actualStartUtc != null) 'actual_start_utc': actualStartUtc,
      if (actualEndUtc != null) 'actual_end_utc': actualEndUtc,
      if (status != null) 'status': status,
      if (rescheduleCount != null) 'reschedule_count': rescheduleCount,
      if (parentSessionId != null) 'parent_session_id': parentSessionId,
      if (isOpener != null) 'is_opener': isOpener,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<int>? plannedStartUtc,
    Value<int>? plannedMinutes,
    Value<int?>? actualStartUtc,
    Value<int?>? actualEndUtc,
    Value<SessionStatus>? status,
    Value<int>? rescheduleCount,
    Value<String?>? parentSessionId,
    Value<bool>? isOpener,
    Value<int>? rowid,
  }) {
    return WorkSessionsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      plannedStartUtc: plannedStartUtc ?? this.plannedStartUtc,
      plannedMinutes: plannedMinutes ?? this.plannedMinutes,
      actualStartUtc: actualStartUtc ?? this.actualStartUtc,
      actualEndUtc: actualEndUtc ?? this.actualEndUtc,
      status: status ?? this.status,
      rescheduleCount: rescheduleCount ?? this.rescheduleCount,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      isOpener: isOpener ?? this.isOpener,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (plannedStartUtc.present) {
      map['planned_start_utc'] = Variable<int>(plannedStartUtc.value);
    }
    if (plannedMinutes.present) {
      map['planned_minutes'] = Variable<int>(plannedMinutes.value);
    }
    if (actualStartUtc.present) {
      map['actual_start_utc'] = Variable<int>(actualStartUtc.value);
    }
    if (actualEndUtc.present) {
      map['actual_end_utc'] = Variable<int>(actualEndUtc.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $WorkSessionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (rescheduleCount.present) {
      map['reschedule_count'] = Variable<int>(rescheduleCount.value);
    }
    if (parentSessionId.present) {
      map['parent_session_id'] = Variable<String>(parentSessionId.value);
    }
    if (isOpener.present) {
      map['is_opener'] = Variable<bool>(isOpener.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkSessionsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('plannedStartUtc: $plannedStartUtc, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('actualStartUtc: $actualStartUtc, ')
          ..write('actualEndUtc: $actualEndUtc, ')
          ..write('status: $status, ')
          ..write('rescheduleCount: $rescheduleCount, ')
          ..write('parentSessionId: $parentSessionId, ')
          ..write('isOpener: $isOpener, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NudgesTable extends Nudges with TableInfo<$NudgesTable, NudgeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NudgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<NudgeType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<NudgeType>($NudgesTable.$convertertype);
  static const VerificationMeta _importanceMeta = const VerificationMeta(
    'importance',
  );
  @override
  late final GeneratedColumn<int> importance = GeneratedColumn<int>(
    'importance',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<InterventionLevel, String> level =
      GeneratedColumn<String>(
        'level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<InterventionLevel>($NudgesTable.$converterlevel);
  static const VerificationMeta _scheduledUtcMeta = const VerificationMeta(
    'scheduledUtc',
  );
  @override
  late final GeneratedColumn<int> scheduledUtc = GeneratedColumn<int>(
    'scheduled_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredUtcMeta = const VerificationMeta(
    'deliveredUtc',
  );
  @override
  late final GeneratedColumn<int> deliveredUtc = GeneratedColumn<int>(
    'delivered_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _copyMeta = const VerificationMeta('copy');
  @override
  late final GeneratedColumn<String> copy = GeneratedColumn<String>(
    'copy',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backendIdMeta = const VerificationMeta(
    'backendId',
  );
  @override
  late final GeneratedColumn<String> backendId = GeneratedColumn<String>(
    'backend_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wasSuppressedMeta = const VerificationMeta(
    'wasSuppressed',
  );
  @override
  late final GeneratedColumn<bool> wasSuppressed = GeneratedColumn<bool>(
    'was_suppressed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("was_suppressed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _suppressionReasonMeta = const VerificationMeta(
    'suppressionReason',
  );
  @override
  late final GeneratedColumn<String> suppressionReason =
      GeneratedColumn<String>(
        'suppression_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    type,
    importance,
    level,
    scheduledUtc,
    deliveredUtc,
    copy,
    templateId,
    backendId,
    wasSuppressed,
    suppressionReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nudges';
  @override
  VerificationContext validateIntegrity(
    Insertable<NudgeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('importance')) {
      context.handle(
        _importanceMeta,
        importance.isAcceptableOrUnknown(data['importance']!, _importanceMeta),
      );
    } else if (isInserting) {
      context.missing(_importanceMeta);
    }
    if (data.containsKey('scheduled_utc')) {
      context.handle(
        _scheduledUtcMeta,
        scheduledUtc.isAcceptableOrUnknown(
          data['scheduled_utc']!,
          _scheduledUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledUtcMeta);
    }
    if (data.containsKey('delivered_utc')) {
      context.handle(
        _deliveredUtcMeta,
        deliveredUtc.isAcceptableOrUnknown(
          data['delivered_utc']!,
          _deliveredUtcMeta,
        ),
      );
    }
    if (data.containsKey('copy')) {
      context.handle(
        _copyMeta,
        copy.isAcceptableOrUnknown(data['copy']!, _copyMeta),
      );
    } else if (isInserting) {
      context.missing(_copyMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    }
    if (data.containsKey('backend_id')) {
      context.handle(
        _backendIdMeta,
        backendId.isAcceptableOrUnknown(data['backend_id']!, _backendIdMeta),
      );
    }
    if (data.containsKey('was_suppressed')) {
      context.handle(
        _wasSuppressedMeta,
        wasSuppressed.isAcceptableOrUnknown(
          data['was_suppressed']!,
          _wasSuppressedMeta,
        ),
      );
    }
    if (data.containsKey('suppression_reason')) {
      context.handle(
        _suppressionReasonMeta,
        suppressionReason.isAcceptableOrUnknown(
          data['suppression_reason']!,
          _suppressionReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NudgeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NudgeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      type: $NudgesTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      importance: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}importance'],
      )!,
      level: $NudgesTable.$converterlevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}level'],
        )!,
      ),
      scheduledUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_utc'],
      )!,
      deliveredUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivered_utc'],
      ),
      copy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copy'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      ),
      backendId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backend_id'],
      ),
      wasSuppressed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}was_suppressed'],
      )!,
      suppressionReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suppression_reason'],
      ),
    );
  }

  @override
  $NudgesTable createAlias(String alias) {
    return $NudgesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<NudgeType, String, String> $convertertype =
      const EnumNameConverter<NudgeType>(NudgeType.values);
  static JsonTypeConverter2<InterventionLevel, String, String> $converterlevel =
      const EnumNameConverter<InterventionLevel>(InterventionLevel.values);
}

class NudgeRow extends DataClass implements Insertable<NudgeRow> {
  final String id;
  final String? sessionId;
  final NudgeType type;
  final int importance;
  final InterventionLevel level;
  final int scheduledUtc;
  final int? deliveredUtc;
  final String copy;
  final String? templateId;
  final String? backendId;
  final bool wasSuppressed;
  final String? suppressionReason;
  const NudgeRow({
    required this.id,
    this.sessionId,
    required this.type,
    required this.importance,
    required this.level,
    required this.scheduledUtc,
    this.deliveredUtc,
    required this.copy,
    this.templateId,
    this.backendId,
    required this.wasSuppressed,
    this.suppressionReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    {
      map['type'] = Variable<String>($NudgesTable.$convertertype.toSql(type));
    }
    map['importance'] = Variable<int>(importance);
    {
      map['level'] = Variable<String>(
        $NudgesTable.$converterlevel.toSql(level),
      );
    }
    map['scheduled_utc'] = Variable<int>(scheduledUtc);
    if (!nullToAbsent || deliveredUtc != null) {
      map['delivered_utc'] = Variable<int>(deliveredUtc);
    }
    map['copy'] = Variable<String>(copy);
    if (!nullToAbsent || templateId != null) {
      map['template_id'] = Variable<String>(templateId);
    }
    if (!nullToAbsent || backendId != null) {
      map['backend_id'] = Variable<String>(backendId);
    }
    map['was_suppressed'] = Variable<bool>(wasSuppressed);
    if (!nullToAbsent || suppressionReason != null) {
      map['suppression_reason'] = Variable<String>(suppressionReason);
    }
    return map;
  }

  NudgesCompanion toCompanion(bool nullToAbsent) {
    return NudgesCompanion(
      id: Value(id),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      type: Value(type),
      importance: Value(importance),
      level: Value(level),
      scheduledUtc: Value(scheduledUtc),
      deliveredUtc: deliveredUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredUtc),
      copy: Value(copy),
      templateId: templateId == null && nullToAbsent
          ? const Value.absent()
          : Value(templateId),
      backendId: backendId == null && nullToAbsent
          ? const Value.absent()
          : Value(backendId),
      wasSuppressed: Value(wasSuppressed),
      suppressionReason: suppressionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(suppressionReason),
    );
  }

  factory NudgeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NudgeRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      type: $NudgesTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      importance: serializer.fromJson<int>(json['importance']),
      level: $NudgesTable.$converterlevel.fromJson(
        serializer.fromJson<String>(json['level']),
      ),
      scheduledUtc: serializer.fromJson<int>(json['scheduledUtc']),
      deliveredUtc: serializer.fromJson<int?>(json['deliveredUtc']),
      copy: serializer.fromJson<String>(json['copy']),
      templateId: serializer.fromJson<String?>(json['templateId']),
      backendId: serializer.fromJson<String?>(json['backendId']),
      wasSuppressed: serializer.fromJson<bool>(json['wasSuppressed']),
      suppressionReason: serializer.fromJson<String?>(
        json['suppressionReason'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String?>(sessionId),
      'type': serializer.toJson<String>(
        $NudgesTable.$convertertype.toJson(type),
      ),
      'importance': serializer.toJson<int>(importance),
      'level': serializer.toJson<String>(
        $NudgesTable.$converterlevel.toJson(level),
      ),
      'scheduledUtc': serializer.toJson<int>(scheduledUtc),
      'deliveredUtc': serializer.toJson<int?>(deliveredUtc),
      'copy': serializer.toJson<String>(copy),
      'templateId': serializer.toJson<String?>(templateId),
      'backendId': serializer.toJson<String?>(backendId),
      'wasSuppressed': serializer.toJson<bool>(wasSuppressed),
      'suppressionReason': serializer.toJson<String?>(suppressionReason),
    };
  }

  NudgeRow copyWith({
    String? id,
    Value<String?> sessionId = const Value.absent(),
    NudgeType? type,
    int? importance,
    InterventionLevel? level,
    int? scheduledUtc,
    Value<int?> deliveredUtc = const Value.absent(),
    String? copy,
    Value<String?> templateId = const Value.absent(),
    Value<String?> backendId = const Value.absent(),
    bool? wasSuppressed,
    Value<String?> suppressionReason = const Value.absent(),
  }) => NudgeRow(
    id: id ?? this.id,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    type: type ?? this.type,
    importance: importance ?? this.importance,
    level: level ?? this.level,
    scheduledUtc: scheduledUtc ?? this.scheduledUtc,
    deliveredUtc: deliveredUtc.present ? deliveredUtc.value : this.deliveredUtc,
    copy: copy ?? this.copy,
    templateId: templateId.present ? templateId.value : this.templateId,
    backendId: backendId.present ? backendId.value : this.backendId,
    wasSuppressed: wasSuppressed ?? this.wasSuppressed,
    suppressionReason: suppressionReason.present
        ? suppressionReason.value
        : this.suppressionReason,
  );
  NudgeRow copyWithCompanion(NudgesCompanion data) {
    return NudgeRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      type: data.type.present ? data.type.value : this.type,
      importance: data.importance.present
          ? data.importance.value
          : this.importance,
      level: data.level.present ? data.level.value : this.level,
      scheduledUtc: data.scheduledUtc.present
          ? data.scheduledUtc.value
          : this.scheduledUtc,
      deliveredUtc: data.deliveredUtc.present
          ? data.deliveredUtc.value
          : this.deliveredUtc,
      copy: data.copy.present ? data.copy.value : this.copy,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      backendId: data.backendId.present ? data.backendId.value : this.backendId,
      wasSuppressed: data.wasSuppressed.present
          ? data.wasSuppressed.value
          : this.wasSuppressed,
      suppressionReason: data.suppressionReason.present
          ? data.suppressionReason.value
          : this.suppressionReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NudgeRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('importance: $importance, ')
          ..write('level: $level, ')
          ..write('scheduledUtc: $scheduledUtc, ')
          ..write('deliveredUtc: $deliveredUtc, ')
          ..write('copy: $copy, ')
          ..write('templateId: $templateId, ')
          ..write('backendId: $backendId, ')
          ..write('wasSuppressed: $wasSuppressed, ')
          ..write('suppressionReason: $suppressionReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    type,
    importance,
    level,
    scheduledUtc,
    deliveredUtc,
    copy,
    templateId,
    backendId,
    wasSuppressed,
    suppressionReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NudgeRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.type == this.type &&
          other.importance == this.importance &&
          other.level == this.level &&
          other.scheduledUtc == this.scheduledUtc &&
          other.deliveredUtc == this.deliveredUtc &&
          other.copy == this.copy &&
          other.templateId == this.templateId &&
          other.backendId == this.backendId &&
          other.wasSuppressed == this.wasSuppressed &&
          other.suppressionReason == this.suppressionReason);
}

class NudgesCompanion extends UpdateCompanion<NudgeRow> {
  final Value<String> id;
  final Value<String?> sessionId;
  final Value<NudgeType> type;
  final Value<int> importance;
  final Value<InterventionLevel> level;
  final Value<int> scheduledUtc;
  final Value<int?> deliveredUtc;
  final Value<String> copy;
  final Value<String?> templateId;
  final Value<String?> backendId;
  final Value<bool> wasSuppressed;
  final Value<String?> suppressionReason;
  final Value<int> rowid;
  const NudgesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.type = const Value.absent(),
    this.importance = const Value.absent(),
    this.level = const Value.absent(),
    this.scheduledUtc = const Value.absent(),
    this.deliveredUtc = const Value.absent(),
    this.copy = const Value.absent(),
    this.templateId = const Value.absent(),
    this.backendId = const Value.absent(),
    this.wasSuppressed = const Value.absent(),
    this.suppressionReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NudgesCompanion.insert({
    required String id,
    this.sessionId = const Value.absent(),
    required NudgeType type,
    required int importance,
    required InterventionLevel level,
    required int scheduledUtc,
    this.deliveredUtc = const Value.absent(),
    required String copy,
    this.templateId = const Value.absent(),
    this.backendId = const Value.absent(),
    this.wasSuppressed = const Value.absent(),
    this.suppressionReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       importance = Value(importance),
       level = Value(level),
       scheduledUtc = Value(scheduledUtc),
       copy = Value(copy);
  static Insertable<NudgeRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? type,
    Expression<int>? importance,
    Expression<String>? level,
    Expression<int>? scheduledUtc,
    Expression<int>? deliveredUtc,
    Expression<String>? copy,
    Expression<String>? templateId,
    Expression<String>? backendId,
    Expression<bool>? wasSuppressed,
    Expression<String>? suppressionReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (type != null) 'type': type,
      if (importance != null) 'importance': importance,
      if (level != null) 'level': level,
      if (scheduledUtc != null) 'scheduled_utc': scheduledUtc,
      if (deliveredUtc != null) 'delivered_utc': deliveredUtc,
      if (copy != null) 'copy': copy,
      if (templateId != null) 'template_id': templateId,
      if (backendId != null) 'backend_id': backendId,
      if (wasSuppressed != null) 'was_suppressed': wasSuppressed,
      if (suppressionReason != null) 'suppression_reason': suppressionReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NudgesCompanion copyWith({
    Value<String>? id,
    Value<String?>? sessionId,
    Value<NudgeType>? type,
    Value<int>? importance,
    Value<InterventionLevel>? level,
    Value<int>? scheduledUtc,
    Value<int?>? deliveredUtc,
    Value<String>? copy,
    Value<String?>? templateId,
    Value<String?>? backendId,
    Value<bool>? wasSuppressed,
    Value<String?>? suppressionReason,
    Value<int>? rowid,
  }) {
    return NudgesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      importance: importance ?? this.importance,
      level: level ?? this.level,
      scheduledUtc: scheduledUtc ?? this.scheduledUtc,
      deliveredUtc: deliveredUtc ?? this.deliveredUtc,
      copy: copy ?? this.copy,
      templateId: templateId ?? this.templateId,
      backendId: backendId ?? this.backendId,
      wasSuppressed: wasSuppressed ?? this.wasSuppressed,
      suppressionReason: suppressionReason ?? this.suppressionReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $NudgesTable.$convertertype.toSql(type.value),
      );
    }
    if (importance.present) {
      map['importance'] = Variable<int>(importance.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(
        $NudgesTable.$converterlevel.toSql(level.value),
      );
    }
    if (scheduledUtc.present) {
      map['scheduled_utc'] = Variable<int>(scheduledUtc.value);
    }
    if (deliveredUtc.present) {
      map['delivered_utc'] = Variable<int>(deliveredUtc.value);
    }
    if (copy.present) {
      map['copy'] = Variable<String>(copy.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (backendId.present) {
      map['backend_id'] = Variable<String>(backendId.value);
    }
    if (wasSuppressed.present) {
      map['was_suppressed'] = Variable<bool>(wasSuppressed.value);
    }
    if (suppressionReason.present) {
      map['suppression_reason'] = Variable<String>(suppressionReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NudgesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('importance: $importance, ')
          ..write('level: $level, ')
          ..write('scheduledUtc: $scheduledUtc, ')
          ..write('deliveredUtc: $deliveredUtc, ')
          ..write('copy: $copy, ')
          ..write('templateId: $templateId, ')
          ..write('backendId: $backendId, ')
          ..write('wasSuppressed: $wasSuppressed, ')
          ..write('suppressionReason: $suppressionReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NudgeResponsesTable extends NudgeResponses
    with TableInfo<$NudgeResponsesTable, NudgeResponseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NudgeResponsesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nudgeIdMeta = const VerificationMeta(
    'nudgeId',
  );
  @override
  late final GeneratedColumn<String> nudgeId = GeneratedColumn<String>(
    'nudge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nudges (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ResponseType, String> response =
      GeneratedColumn<String>(
        'response',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ResponseType>($NudgeResponsesTable.$converterresponse);
  static const VerificationMeta _reasonTextMeta = const VerificationMeta(
    'reasonText',
  );
  @override
  late final GeneratedColumn<String> reasonText = GeneratedColumn<String>(
    'reason_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _respondedUtcMeta = const VerificationMeta(
    'respondedUtc',
  );
  @override
  late final GeneratedColumn<int> respondedUtc = GeneratedColumn<int>(
    'responded_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latencySecondsMeta = const VerificationMeta(
    'latencySeconds',
  );
  @override
  late final GeneratedColumn<int> latencySeconds = GeneratedColumn<int>(
    'latency_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nudgeId,
    response,
    reasonText,
    respondedUtc,
    latencySeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nudge_responses';
  @override
  VerificationContext validateIntegrity(
    Insertable<NudgeResponseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('nudge_id')) {
      context.handle(
        _nudgeIdMeta,
        nudgeId.isAcceptableOrUnknown(data['nudge_id']!, _nudgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nudgeIdMeta);
    }
    if (data.containsKey('reason_text')) {
      context.handle(
        _reasonTextMeta,
        reasonText.isAcceptableOrUnknown(data['reason_text']!, _reasonTextMeta),
      );
    }
    if (data.containsKey('responded_utc')) {
      context.handle(
        _respondedUtcMeta,
        respondedUtc.isAcceptableOrUnknown(
          data['responded_utc']!,
          _respondedUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_respondedUtcMeta);
    }
    if (data.containsKey('latency_seconds')) {
      context.handle(
        _latencySecondsMeta,
        latencySeconds.isAcceptableOrUnknown(
          data['latency_seconds']!,
          _latencySecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_latencySecondsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NudgeResponseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NudgeResponseRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      nudgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nudge_id'],
      )!,
      response: $NudgeResponsesTable.$converterresponse.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}response'],
        )!,
      ),
      reasonText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason_text'],
      ),
      respondedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}responded_utc'],
      )!,
      latencySeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_seconds'],
      )!,
    );
  }

  @override
  $NudgeResponsesTable createAlias(String alias) {
    return $NudgeResponsesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ResponseType, String, String> $converterresponse =
      const EnumNameConverter<ResponseType>(ResponseType.values);
}

class NudgeResponseRow extends DataClass
    implements Insertable<NudgeResponseRow> {
  final String id;
  final String nudgeId;
  final ResponseType response;
  final String? reasonText;
  final int respondedUtc;
  final int latencySeconds;
  const NudgeResponseRow({
    required this.id,
    required this.nudgeId,
    required this.response,
    this.reasonText,
    required this.respondedUtc,
    required this.latencySeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['nudge_id'] = Variable<String>(nudgeId);
    {
      map['response'] = Variable<String>(
        $NudgeResponsesTable.$converterresponse.toSql(response),
      );
    }
    if (!nullToAbsent || reasonText != null) {
      map['reason_text'] = Variable<String>(reasonText);
    }
    map['responded_utc'] = Variable<int>(respondedUtc);
    map['latency_seconds'] = Variable<int>(latencySeconds);
    return map;
  }

  NudgeResponsesCompanion toCompanion(bool nullToAbsent) {
    return NudgeResponsesCompanion(
      id: Value(id),
      nudgeId: Value(nudgeId),
      response: Value(response),
      reasonText: reasonText == null && nullToAbsent
          ? const Value.absent()
          : Value(reasonText),
      respondedUtc: Value(respondedUtc),
      latencySeconds: Value(latencySeconds),
    );
  }

  factory NudgeResponseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NudgeResponseRow(
      id: serializer.fromJson<String>(json['id']),
      nudgeId: serializer.fromJson<String>(json['nudgeId']),
      response: $NudgeResponsesTable.$converterresponse.fromJson(
        serializer.fromJson<String>(json['response']),
      ),
      reasonText: serializer.fromJson<String?>(json['reasonText']),
      respondedUtc: serializer.fromJson<int>(json['respondedUtc']),
      latencySeconds: serializer.fromJson<int>(json['latencySeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nudgeId': serializer.toJson<String>(nudgeId),
      'response': serializer.toJson<String>(
        $NudgeResponsesTable.$converterresponse.toJson(response),
      ),
      'reasonText': serializer.toJson<String?>(reasonText),
      'respondedUtc': serializer.toJson<int>(respondedUtc),
      'latencySeconds': serializer.toJson<int>(latencySeconds),
    };
  }

  NudgeResponseRow copyWith({
    String? id,
    String? nudgeId,
    ResponseType? response,
    Value<String?> reasonText = const Value.absent(),
    int? respondedUtc,
    int? latencySeconds,
  }) => NudgeResponseRow(
    id: id ?? this.id,
    nudgeId: nudgeId ?? this.nudgeId,
    response: response ?? this.response,
    reasonText: reasonText.present ? reasonText.value : this.reasonText,
    respondedUtc: respondedUtc ?? this.respondedUtc,
    latencySeconds: latencySeconds ?? this.latencySeconds,
  );
  NudgeResponseRow copyWithCompanion(NudgeResponsesCompanion data) {
    return NudgeResponseRow(
      id: data.id.present ? data.id.value : this.id,
      nudgeId: data.nudgeId.present ? data.nudgeId.value : this.nudgeId,
      response: data.response.present ? data.response.value : this.response,
      reasonText: data.reasonText.present
          ? data.reasonText.value
          : this.reasonText,
      respondedUtc: data.respondedUtc.present
          ? data.respondedUtc.value
          : this.respondedUtc,
      latencySeconds: data.latencySeconds.present
          ? data.latencySeconds.value
          : this.latencySeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NudgeResponseRow(')
          ..write('id: $id, ')
          ..write('nudgeId: $nudgeId, ')
          ..write('response: $response, ')
          ..write('reasonText: $reasonText, ')
          ..write('respondedUtc: $respondedUtc, ')
          ..write('latencySeconds: $latencySeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    nudgeId,
    response,
    reasonText,
    respondedUtc,
    latencySeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NudgeResponseRow &&
          other.id == this.id &&
          other.nudgeId == this.nudgeId &&
          other.response == this.response &&
          other.reasonText == this.reasonText &&
          other.respondedUtc == this.respondedUtc &&
          other.latencySeconds == this.latencySeconds);
}

class NudgeResponsesCompanion extends UpdateCompanion<NudgeResponseRow> {
  final Value<String> id;
  final Value<String> nudgeId;
  final Value<ResponseType> response;
  final Value<String?> reasonText;
  final Value<int> respondedUtc;
  final Value<int> latencySeconds;
  final Value<int> rowid;
  const NudgeResponsesCompanion({
    this.id = const Value.absent(),
    this.nudgeId = const Value.absent(),
    this.response = const Value.absent(),
    this.reasonText = const Value.absent(),
    this.respondedUtc = const Value.absent(),
    this.latencySeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NudgeResponsesCompanion.insert({
    required String id,
    required String nudgeId,
    required ResponseType response,
    this.reasonText = const Value.absent(),
    required int respondedUtc,
    required int latencySeconds,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       nudgeId = Value(nudgeId),
       response = Value(response),
       respondedUtc = Value(respondedUtc),
       latencySeconds = Value(latencySeconds);
  static Insertable<NudgeResponseRow> custom({
    Expression<String>? id,
    Expression<String>? nudgeId,
    Expression<String>? response,
    Expression<String>? reasonText,
    Expression<int>? respondedUtc,
    Expression<int>? latencySeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nudgeId != null) 'nudge_id': nudgeId,
      if (response != null) 'response': response,
      if (reasonText != null) 'reason_text': reasonText,
      if (respondedUtc != null) 'responded_utc': respondedUtc,
      if (latencySeconds != null) 'latency_seconds': latencySeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NudgeResponsesCompanion copyWith({
    Value<String>? id,
    Value<String>? nudgeId,
    Value<ResponseType>? response,
    Value<String?>? reasonText,
    Value<int>? respondedUtc,
    Value<int>? latencySeconds,
    Value<int>? rowid,
  }) {
    return NudgeResponsesCompanion(
      id: id ?? this.id,
      nudgeId: nudgeId ?? this.nudgeId,
      response: response ?? this.response,
      reasonText: reasonText ?? this.reasonText,
      respondedUtc: respondedUtc ?? this.respondedUtc,
      latencySeconds: latencySeconds ?? this.latencySeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nudgeId.present) {
      map['nudge_id'] = Variable<String>(nudgeId.value);
    }
    if (response.present) {
      map['response'] = Variable<String>(
        $NudgeResponsesTable.$converterresponse.toSql(response.value),
      );
    }
    if (reasonText.present) {
      map['reason_text'] = Variable<String>(reasonText.value);
    }
    if (respondedUtc.present) {
      map['responded_utc'] = Variable<int>(respondedUtc.value);
    }
    if (latencySeconds.present) {
      map['latency_seconds'] = Variable<int>(latencySeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NudgeResponsesCompanion(')
          ..write('id: $id, ')
          ..write('nudgeId: $nudgeId, ')
          ..write('response: $response, ')
          ..write('reasonText: $reasonText, ')
          ..write('respondedUtc: $respondedUtc, ')
          ..write('latencySeconds: $latencySeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, EventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tsUtcMeta = const VerificationMeta('tsUtc');
  @override
  late final GeneratedColumn<int> tsUtc = GeneratedColumn<int>(
    'ts_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EventType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EventType>($EventsTable.$convertertype);
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tsUtc,
    type,
    payloadJson,
    sessionId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ts_utc')) {
      context.handle(
        _tsUtcMeta,
        tsUtc.isAcceptableOrUnknown(data['ts_utc']!, _tsUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_tsUtcMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tsUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts_utc'],
      )!,
      type: $EventsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EventType, String, String> $convertertype =
      const EnumNameConverter<EventType>(EventType.values);
}

class EventRow extends DataClass implements Insertable<EventRow> {
  final int id;
  final int tsUtc;
  final EventType type;
  final String payloadJson;

  /// Lifted out of [payloadJson] so the log can be read per session without
  /// loading all of it. Null for events that are not about a session, which is
  /// most of them.
  ///
  /// A denormalisation, and the only one in the schema. It does not weaken the
  /// append-only rule: the payload is still the record, this is a copy of one
  /// field made at write time and never edited afterwards.
  final String? sessionId;
  const EventRow({
    required this.id,
    required this.tsUtc,
    required this.type,
    required this.payloadJson,
    this.sessionId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ts_utc'] = Variable<int>(tsUtc);
    {
      map['type'] = Variable<String>($EventsTable.$convertertype.toSql(type));
    }
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      tsUtc: Value(tsUtc),
      type: Value(type),
      payloadJson: Value(payloadJson),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
    );
  }

  factory EventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventRow(
      id: serializer.fromJson<int>(json['id']),
      tsUtc: serializer.fromJson<int>(json['tsUtc']),
      type: $EventsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tsUtc': serializer.toJson<int>(tsUtc),
      'type': serializer.toJson<String>(
        $EventsTable.$convertertype.toJson(type),
      ),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'sessionId': serializer.toJson<String?>(sessionId),
    };
  }

  EventRow copyWith({
    int? id,
    int? tsUtc,
    EventType? type,
    String? payloadJson,
    Value<String?> sessionId = const Value.absent(),
  }) => EventRow(
    id: id ?? this.id,
    tsUtc: tsUtc ?? this.tsUtc,
    type: type ?? this.type,
    payloadJson: payloadJson ?? this.payloadJson,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
  );
  EventRow copyWithCompanion(EventsCompanion data) {
    return EventRow(
      id: data.id.present ? data.id.value : this.id,
      tsUtc: data.tsUtc.present ? data.tsUtc.value : this.tsUtc,
      type: data.type.present ? data.type.value : this.type,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventRow(')
          ..write('id: $id, ')
          ..write('tsUtc: $tsUtc, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('sessionId: $sessionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tsUtc, type, payloadJson, sessionId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventRow &&
          other.id == this.id &&
          other.tsUtc == this.tsUtc &&
          other.type == this.type &&
          other.payloadJson == this.payloadJson &&
          other.sessionId == this.sessionId);
}

class EventsCompanion extends UpdateCompanion<EventRow> {
  final Value<int> id;
  final Value<int> tsUtc;
  final Value<EventType> type;
  final Value<String> payloadJson;
  final Value<String?> sessionId;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.tsUtc = const Value.absent(),
    this.type = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.sessionId = const Value.absent(),
  });
  EventsCompanion.insert({
    this.id = const Value.absent(),
    required int tsUtc,
    required EventType type,
    this.payloadJson = const Value.absent(),
    this.sessionId = const Value.absent(),
  }) : tsUtc = Value(tsUtc),
       type = Value(type);
  static Insertable<EventRow> custom({
    Expression<int>? id,
    Expression<int>? tsUtc,
    Expression<String>? type,
    Expression<String>? payloadJson,
    Expression<String>? sessionId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tsUtc != null) 'ts_utc': tsUtc,
      if (type != null) 'type': type,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (sessionId != null) 'session_id': sessionId,
    });
  }

  EventsCompanion copyWith({
    Value<int>? id,
    Value<int>? tsUtc,
    Value<EventType>? type,
    Value<String>? payloadJson,
    Value<String?>? sessionId,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      tsUtc: tsUtc ?? this.tsUtc,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tsUtc.present) {
      map['ts_utc'] = Variable<int>(tsUtc.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $EventsTable.$convertertype.toSql(type.value),
      );
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('tsUtc: $tsUtc, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('sessionId: $sessionId')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$VanDatabase extends GeneratedDatabase {
  _$VanDatabase(QueryExecutor e) : super(e);
  $VanDatabaseManager get managers => $VanDatabaseManager(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $WorkSessionsTable workSessions = $WorkSessionsTable(this);
  late final $NudgesTable nudges = $NudgesTable(this);
  late final $NudgeResponsesTable nudgeResponses = $NudgeResponsesTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index idxTasksDeadline = Index(
    'idx_tasks_deadline',
    'CREATE INDEX idx_tasks_deadline ON tasks (deadline_utc)',
  );
  late final Index idxSessionsPlannedStart = Index(
    'idx_sessions_planned_start',
    'CREATE INDEX idx_sessions_planned_start ON work_sessions (planned_start_utc)',
  );
  late final Index idxSessionsTask = Index(
    'idx_sessions_task',
    'CREATE INDEX idx_sessions_task ON work_sessions (task_id)',
  );
  late final Index idxNudgesScheduled = Index(
    'idx_nudges_scheduled',
    'CREATE INDEX idx_nudges_scheduled ON nudges (scheduled_utc)',
  );
  late final Index idxNudgesSession = Index(
    'idx_nudges_session',
    'CREATE INDEX idx_nudges_session ON nudges (session_id)',
  );
  late final Index idxResponsesNudge = Index(
    'idx_responses_nudge',
    'CREATE INDEX idx_responses_nudge ON nudge_responses (nudge_id)',
  );
  late final Index idxEventsTs = Index(
    'idx_events_ts',
    'CREATE INDEX idx_events_ts ON events (ts_utc)',
  );
  late final Index idxEventsType = Index(
    'idx_events_type',
    'CREATE INDEX idx_events_type ON events (type)',
  );
  late final Index idxEventsSession = Index(
    'idx_events_session',
    'CREATE INDEX idx_events_session ON events (session_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tasks,
    workSessions,
    nudges,
    nudgeResponses,
    events,
    settings,
    idxTasksDeadline,
    idxSessionsPlannedStart,
    idxSessionsTask,
    idxNudgesScheduled,
    idxNudgesSession,
    idxResponsesNudge,
    idxEventsTs,
    idxEventsType,
    idxEventsSession,
  ];
}

typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      required String id,
      required String title,
      Value<String?> notes,
      Value<int?> deadlineUtc,
      Value<int?> estimatedMinutes,
      required Priority priority,
      required TaskStatus status,
      required int createdUtc,
      required TaskSource source,
      Value<TaskDepth> depth,
      Value<int?> actualMinutes,
      Value<int> rowid,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> notes,
      Value<int?> deadlineUtc,
      Value<int?> estimatedMinutes,
      Value<Priority> priority,
      Value<TaskStatus> status,
      Value<int> createdUtc,
      Value<TaskSource> source,
      Value<TaskDepth> depth,
      Value<int?> actualMinutes,
      Value<int> rowid,
    });

final class $$TasksTableReferences
    extends BaseReferences<_$VanDatabase, $TasksTable, TaskRow> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$WorkSessionsTable, List<WorkSessionRow>>
  _workSessionsRefsTable(_$VanDatabase db) => MultiTypedResultKey.fromTable(
    db.workSessions,
    aliasName: 'tasks__id__work_sessions__task_id',
  );

  $$WorkSessionsTableProcessedTableManager get workSessionsRefs {
    final manager = $$WorkSessionsTableTableManager(
      $_db,
      $_db.workSessions,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_workSessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$VanDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deadlineUtc => $composableBuilder(
    column: $table.deadlineUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Priority, Priority, String> get priority =>
      $composableBuilder(
        column: $table.priority,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<TaskStatus, TaskStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TaskSource, TaskSource, String> get source =>
      $composableBuilder(
        column: $table.source,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<TaskDepth, TaskDepth, String> get depth =>
      $composableBuilder(
        column: $table.depth,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get actualMinutes => $composableBuilder(
    column: $table.actualMinutes,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> workSessionsRefs(
    Expression<bool> Function($$WorkSessionsTableFilterComposer f) f,
  ) {
    final $$WorkSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.workSessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkSessionsTableFilterComposer(
            $db: $db,
            $table: $db.workSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$VanDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deadlineUtc => $composableBuilder(
    column: $table.deadlineUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get depth => $composableBuilder(
    column: $table.depth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualMinutes => $composableBuilder(
    column: $table.actualMinutes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$VanDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get deadlineUtc => $composableBuilder(
    column: $table.deadlineUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Priority, String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaskStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TaskSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaskDepth, String> get depth =>
      $composableBuilder(column: $table.depth, builder: (column) => column);

  GeneratedColumn<int> get actualMinutes => $composableBuilder(
    column: $table.actualMinutes,
    builder: (column) => column,
  );

  Expression<T> workSessionsRefs<T extends Object>(
    Expression<T> Function($$WorkSessionsTableAnnotationComposer a) f,
  ) {
    final $$WorkSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.workSessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.workSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$VanDatabase,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, $$TasksTableReferences),
          TaskRow,
          PrefetchHooks Function({bool workSessionsRefs})
        > {
  $$TasksTableTableManager(_$VanDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int?> deadlineUtc = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<Priority> priority = const Value.absent(),
                Value<TaskStatus> status = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<TaskSource> source = const Value.absent(),
                Value<TaskDepth> depth = const Value.absent(),
                Value<int?> actualMinutes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                title: title,
                notes: notes,
                deadlineUtc: deadlineUtc,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                status: status,
                createdUtc: createdUtc,
                source: source,
                depth: depth,
                actualMinutes: actualMinutes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> notes = const Value.absent(),
                Value<int?> deadlineUtc = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                required Priority priority,
                required TaskStatus status,
                required int createdUtc,
                required TaskSource source,
                Value<TaskDepth> depth = const Value.absent(),
                Value<int?> actualMinutes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                title: title,
                notes: notes,
                deadlineUtc: deadlineUtc,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                status: status,
                createdUtc: createdUtc,
                source: source,
                depth: depth,
                actualMinutes: actualMinutes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TasksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({workSessionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (workSessionsRefs) db.workSessions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (workSessionsRefs)
                    await $_getPrefetchedData<
                      TaskRow,
                      $TasksTable,
                      WorkSessionRow
                    >(
                      currentTable: table,
                      referencedTable: $$TasksTableReferences
                          ._workSessionsRefsTable(db),
                      managerFromTypedResult: (p0) => $$TasksTableReferences(
                        db,
                        table,
                        p0,
                      ).workSessionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.taskId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$VanDatabase,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, $$TasksTableReferences),
      TaskRow,
      PrefetchHooks Function({bool workSessionsRefs})
    >;
typedef $$WorkSessionsTableCreateCompanionBuilder =
    WorkSessionsCompanion Function({
      required String id,
      required String taskId,
      required int plannedStartUtc,
      required int plannedMinutes,
      Value<int?> actualStartUtc,
      Value<int?> actualEndUtc,
      required SessionStatus status,
      Value<int> rescheduleCount,
      Value<String?> parentSessionId,
      Value<bool> isOpener,
      Value<int> rowid,
    });
typedef $$WorkSessionsTableUpdateCompanionBuilder =
    WorkSessionsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<int> plannedStartUtc,
      Value<int> plannedMinutes,
      Value<int?> actualStartUtc,
      Value<int?> actualEndUtc,
      Value<SessionStatus> status,
      Value<int> rescheduleCount,
      Value<String?> parentSessionId,
      Value<bool> isOpener,
      Value<int> rowid,
    });

final class $$WorkSessionsTableReferences
    extends BaseReferences<_$VanDatabase, $WorkSessionsTable, WorkSessionRow> {
  $$WorkSessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$VanDatabase db) =>
      db.tasks.createAlias('work_sessions__task_id__tasks__id');

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WorkSessionsTableFilterComposer
    extends Composer<_$VanDatabase, $WorkSessionsTable> {
  $$WorkSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedStartUtc => $composableBuilder(
    column: $table.plannedStartUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualStartUtc => $composableBuilder(
    column: $table.actualStartUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualEndUtc => $composableBuilder(
    column: $table.actualEndUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SessionStatus, SessionStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get rescheduleCount => $composableBuilder(
    column: $table.rescheduleCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentSessionId => $composableBuilder(
    column: $table.parentSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOpener => $composableBuilder(
    column: $table.isOpener,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkSessionsTableOrderingComposer
    extends Composer<_$VanDatabase, $WorkSessionsTable> {
  $$WorkSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedStartUtc => $composableBuilder(
    column: $table.plannedStartUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualStartUtc => $composableBuilder(
    column: $table.actualStartUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualEndUtc => $composableBuilder(
    column: $table.actualEndUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rescheduleCount => $composableBuilder(
    column: $table.rescheduleCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentSessionId => $composableBuilder(
    column: $table.parentSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOpener => $composableBuilder(
    column: $table.isOpener,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkSessionsTableAnnotationComposer
    extends Composer<_$VanDatabase, $WorkSessionsTable> {
  $$WorkSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get plannedStartUtc => $composableBuilder(
    column: $table.plannedStartUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actualStartUtc => $composableBuilder(
    column: $table.actualStartUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actualEndUtc => $composableBuilder(
    column: $table.actualEndUtc,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SessionStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get rescheduleCount => $composableBuilder(
    column: $table.rescheduleCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentSessionId => $composableBuilder(
    column: $table.parentSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOpener =>
      $composableBuilder(column: $table.isOpener, builder: (column) => column);

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkSessionsTableTableManager
    extends
        RootTableManager<
          _$VanDatabase,
          $WorkSessionsTable,
          WorkSessionRow,
          $$WorkSessionsTableFilterComposer,
          $$WorkSessionsTableOrderingComposer,
          $$WorkSessionsTableAnnotationComposer,
          $$WorkSessionsTableCreateCompanionBuilder,
          $$WorkSessionsTableUpdateCompanionBuilder,
          (WorkSessionRow, $$WorkSessionsTableReferences),
          WorkSessionRow,
          PrefetchHooks Function({bool taskId})
        > {
  $$WorkSessionsTableTableManager(_$VanDatabase db, $WorkSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<int> plannedStartUtc = const Value.absent(),
                Value<int> plannedMinutes = const Value.absent(),
                Value<int?> actualStartUtc = const Value.absent(),
                Value<int?> actualEndUtc = const Value.absent(),
                Value<SessionStatus> status = const Value.absent(),
                Value<int> rescheduleCount = const Value.absent(),
                Value<String?> parentSessionId = const Value.absent(),
                Value<bool> isOpener = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkSessionsCompanion(
                id: id,
                taskId: taskId,
                plannedStartUtc: plannedStartUtc,
                plannedMinutes: plannedMinutes,
                actualStartUtc: actualStartUtc,
                actualEndUtc: actualEndUtc,
                status: status,
                rescheduleCount: rescheduleCount,
                parentSessionId: parentSessionId,
                isOpener: isOpener,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required int plannedStartUtc,
                required int plannedMinutes,
                Value<int?> actualStartUtc = const Value.absent(),
                Value<int?> actualEndUtc = const Value.absent(),
                required SessionStatus status,
                Value<int> rescheduleCount = const Value.absent(),
                Value<String?> parentSessionId = const Value.absent(),
                Value<bool> isOpener = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkSessionsCompanion.insert(
                id: id,
                taskId: taskId,
                plannedStartUtc: plannedStartUtc,
                plannedMinutes: plannedMinutes,
                actualStartUtc: actualStartUtc,
                actualEndUtc: actualEndUtc,
                status: status,
                rescheduleCount: rescheduleCount,
                parentSessionId: parentSessionId,
                isOpener: isOpener,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WorkSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable: $$WorkSessionsTableReferences
                                    ._taskIdTable(db),
                                referencedColumn: $$WorkSessionsTableReferences
                                    ._taskIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WorkSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$VanDatabase,
      $WorkSessionsTable,
      WorkSessionRow,
      $$WorkSessionsTableFilterComposer,
      $$WorkSessionsTableOrderingComposer,
      $$WorkSessionsTableAnnotationComposer,
      $$WorkSessionsTableCreateCompanionBuilder,
      $$WorkSessionsTableUpdateCompanionBuilder,
      (WorkSessionRow, $$WorkSessionsTableReferences),
      WorkSessionRow,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$NudgesTableCreateCompanionBuilder =
    NudgesCompanion Function({
      required String id,
      Value<String?> sessionId,
      required NudgeType type,
      required int importance,
      required InterventionLevel level,
      required int scheduledUtc,
      Value<int?> deliveredUtc,
      required String copy,
      Value<String?> templateId,
      Value<String?> backendId,
      Value<bool> wasSuppressed,
      Value<String?> suppressionReason,
      Value<int> rowid,
    });
typedef $$NudgesTableUpdateCompanionBuilder =
    NudgesCompanion Function({
      Value<String> id,
      Value<String?> sessionId,
      Value<NudgeType> type,
      Value<int> importance,
      Value<InterventionLevel> level,
      Value<int> scheduledUtc,
      Value<int?> deliveredUtc,
      Value<String> copy,
      Value<String?> templateId,
      Value<String?> backendId,
      Value<bool> wasSuppressed,
      Value<String?> suppressionReason,
      Value<int> rowid,
    });

final class $$NudgesTableReferences
    extends BaseReferences<_$VanDatabase, $NudgesTable, NudgeRow> {
  $$NudgesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$NudgeResponsesTable, List<NudgeResponseRow>>
  _nudgeResponsesRefsTable(_$VanDatabase db) => MultiTypedResultKey.fromTable(
    db.nudgeResponses,
    aliasName: 'nudges__id__nudge_responses__nudge_id',
  );

  $$NudgeResponsesTableProcessedTableManager get nudgeResponsesRefs {
    final manager = $$NudgeResponsesTableTableManager(
      $_db,
      $_db.nudgeResponses,
    ).filter((f) => f.nudgeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_nudgeResponsesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NudgesTableFilterComposer
    extends Composer<_$VanDatabase, $NudgesTable> {
  $$NudgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<NudgeType, NudgeType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<InterventionLevel, InterventionLevel, String>
  get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get scheduledUtc => $composableBuilder(
    column: $table.scheduledUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveredUtc => $composableBuilder(
    column: $table.deliveredUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get copy => $composableBuilder(
    column: $table.copy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backendId => $composableBuilder(
    column: $table.backendId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wasSuppressed => $composableBuilder(
    column: $table.wasSuppressed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suppressionReason => $composableBuilder(
    column: $table.suppressionReason,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> nudgeResponsesRefs(
    Expression<bool> Function($$NudgeResponsesTableFilterComposer f) f,
  ) {
    final $$NudgeResponsesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.nudgeResponses,
      getReferencedColumn: (t) => t.nudgeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NudgeResponsesTableFilterComposer(
            $db: $db,
            $table: $db.nudgeResponses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NudgesTableOrderingComposer
    extends Composer<_$VanDatabase, $NudgesTable> {
  $$NudgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledUtc => $composableBuilder(
    column: $table.scheduledUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveredUtc => $composableBuilder(
    column: $table.deliveredUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get copy => $composableBuilder(
    column: $table.copy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backendId => $composableBuilder(
    column: $table.backendId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wasSuppressed => $composableBuilder(
    column: $table.wasSuppressed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suppressionReason => $composableBuilder(
    column: $table.suppressionReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NudgesTableAnnotationComposer
    extends Composer<_$VanDatabase, $NudgesTable> {
  $$NudgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<NudgeType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<InterventionLevel, String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<int> get scheduledUtc => $composableBuilder(
    column: $table.scheduledUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deliveredUtc => $composableBuilder(
    column: $table.deliveredUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get copy =>
      $composableBuilder(column: $table.copy, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backendId =>
      $composableBuilder(column: $table.backendId, builder: (column) => column);

  GeneratedColumn<bool> get wasSuppressed => $composableBuilder(
    column: $table.wasSuppressed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suppressionReason => $composableBuilder(
    column: $table.suppressionReason,
    builder: (column) => column,
  );

  Expression<T> nudgeResponsesRefs<T extends Object>(
    Expression<T> Function($$NudgeResponsesTableAnnotationComposer a) f,
  ) {
    final $$NudgeResponsesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.nudgeResponses,
      getReferencedColumn: (t) => t.nudgeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NudgeResponsesTableAnnotationComposer(
            $db: $db,
            $table: $db.nudgeResponses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NudgesTableTableManager
    extends
        RootTableManager<
          _$VanDatabase,
          $NudgesTable,
          NudgeRow,
          $$NudgesTableFilterComposer,
          $$NudgesTableOrderingComposer,
          $$NudgesTableAnnotationComposer,
          $$NudgesTableCreateCompanionBuilder,
          $$NudgesTableUpdateCompanionBuilder,
          (NudgeRow, $$NudgesTableReferences),
          NudgeRow,
          PrefetchHooks Function({bool nudgeResponsesRefs})
        > {
  $$NudgesTableTableManager(_$VanDatabase db, $NudgesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NudgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NudgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NudgesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<NudgeType> type = const Value.absent(),
                Value<int> importance = const Value.absent(),
                Value<InterventionLevel> level = const Value.absent(),
                Value<int> scheduledUtc = const Value.absent(),
                Value<int?> deliveredUtc = const Value.absent(),
                Value<String> copy = const Value.absent(),
                Value<String?> templateId = const Value.absent(),
                Value<String?> backendId = const Value.absent(),
                Value<bool> wasSuppressed = const Value.absent(),
                Value<String?> suppressionReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NudgesCompanion(
                id: id,
                sessionId: sessionId,
                type: type,
                importance: importance,
                level: level,
                scheduledUtc: scheduledUtc,
                deliveredUtc: deliveredUtc,
                copy: copy,
                templateId: templateId,
                backendId: backendId,
                wasSuppressed: wasSuppressed,
                suppressionReason: suppressionReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> sessionId = const Value.absent(),
                required NudgeType type,
                required int importance,
                required InterventionLevel level,
                required int scheduledUtc,
                Value<int?> deliveredUtc = const Value.absent(),
                required String copy,
                Value<String?> templateId = const Value.absent(),
                Value<String?> backendId = const Value.absent(),
                Value<bool> wasSuppressed = const Value.absent(),
                Value<String?> suppressionReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NudgesCompanion.insert(
                id: id,
                sessionId: sessionId,
                type: type,
                importance: importance,
                level: level,
                scheduledUtc: scheduledUtc,
                deliveredUtc: deliveredUtc,
                copy: copy,
                templateId: templateId,
                backendId: backendId,
                wasSuppressed: wasSuppressed,
                suppressionReason: suppressionReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$NudgesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({nudgeResponsesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (nudgeResponsesRefs) db.nudgeResponses,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (nudgeResponsesRefs)
                    await $_getPrefetchedData<
                      NudgeRow,
                      $NudgesTable,
                      NudgeResponseRow
                    >(
                      currentTable: table,
                      referencedTable: $$NudgesTableReferences
                          ._nudgeResponsesRefsTable(db),
                      managerFromTypedResult: (p0) => $$NudgesTableReferences(
                        db,
                        table,
                        p0,
                      ).nudgeResponsesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.nudgeId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NudgesTableProcessedTableManager =
    ProcessedTableManager<
      _$VanDatabase,
      $NudgesTable,
      NudgeRow,
      $$NudgesTableFilterComposer,
      $$NudgesTableOrderingComposer,
      $$NudgesTableAnnotationComposer,
      $$NudgesTableCreateCompanionBuilder,
      $$NudgesTableUpdateCompanionBuilder,
      (NudgeRow, $$NudgesTableReferences),
      NudgeRow,
      PrefetchHooks Function({bool nudgeResponsesRefs})
    >;
typedef $$NudgeResponsesTableCreateCompanionBuilder =
    NudgeResponsesCompanion Function({
      required String id,
      required String nudgeId,
      required ResponseType response,
      Value<String?> reasonText,
      required int respondedUtc,
      required int latencySeconds,
      Value<int> rowid,
    });
typedef $$NudgeResponsesTableUpdateCompanionBuilder =
    NudgeResponsesCompanion Function({
      Value<String> id,
      Value<String> nudgeId,
      Value<ResponseType> response,
      Value<String?> reasonText,
      Value<int> respondedUtc,
      Value<int> latencySeconds,
      Value<int> rowid,
    });

final class $$NudgeResponsesTableReferences
    extends
        BaseReferences<_$VanDatabase, $NudgeResponsesTable, NudgeResponseRow> {
  $$NudgeResponsesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NudgesTable _nudgeIdTable(_$VanDatabase db) =>
      db.nudges.createAlias('nudge_responses__nudge_id__nudges__id');

  $$NudgesTableProcessedTableManager get nudgeId {
    final $_column = $_itemColumn<String>('nudge_id')!;

    final manager = $$NudgesTableTableManager(
      $_db,
      $_db.nudges,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nudgeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NudgeResponsesTableFilterComposer
    extends Composer<_$VanDatabase, $NudgeResponsesTable> {
  $$NudgeResponsesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ResponseType, ResponseType, String>
  get response => $composableBuilder(
    column: $table.response,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get reasonText => $composableBuilder(
    column: $table.reasonText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get respondedUtc => $composableBuilder(
    column: $table.respondedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencySeconds => $composableBuilder(
    column: $table.latencySeconds,
    builder: (column) => ColumnFilters(column),
  );

  $$NudgesTableFilterComposer get nudgeId {
    final $$NudgesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nudgeId,
      referencedTable: $db.nudges,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NudgesTableFilterComposer(
            $db: $db,
            $table: $db.nudges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NudgeResponsesTableOrderingComposer
    extends Composer<_$VanDatabase, $NudgeResponsesTable> {
  $$NudgeResponsesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get response => $composableBuilder(
    column: $table.response,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasonText => $composableBuilder(
    column: $table.reasonText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get respondedUtc => $composableBuilder(
    column: $table.respondedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencySeconds => $composableBuilder(
    column: $table.latencySeconds,
    builder: (column) => ColumnOrderings(column),
  );

  $$NudgesTableOrderingComposer get nudgeId {
    final $$NudgesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nudgeId,
      referencedTable: $db.nudges,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NudgesTableOrderingComposer(
            $db: $db,
            $table: $db.nudges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NudgeResponsesTableAnnotationComposer
    extends Composer<_$VanDatabase, $NudgeResponsesTable> {
  $$NudgeResponsesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ResponseType, String> get response =>
      $composableBuilder(column: $table.response, builder: (column) => column);

  GeneratedColumn<String> get reasonText => $composableBuilder(
    column: $table.reasonText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get respondedUtc => $composableBuilder(
    column: $table.respondedUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get latencySeconds => $composableBuilder(
    column: $table.latencySeconds,
    builder: (column) => column,
  );

  $$NudgesTableAnnotationComposer get nudgeId {
    final $$NudgesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nudgeId,
      referencedTable: $db.nudges,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NudgesTableAnnotationComposer(
            $db: $db,
            $table: $db.nudges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NudgeResponsesTableTableManager
    extends
        RootTableManager<
          _$VanDatabase,
          $NudgeResponsesTable,
          NudgeResponseRow,
          $$NudgeResponsesTableFilterComposer,
          $$NudgeResponsesTableOrderingComposer,
          $$NudgeResponsesTableAnnotationComposer,
          $$NudgeResponsesTableCreateCompanionBuilder,
          $$NudgeResponsesTableUpdateCompanionBuilder,
          (NudgeResponseRow, $$NudgeResponsesTableReferences),
          NudgeResponseRow,
          PrefetchHooks Function({bool nudgeId})
        > {
  $$NudgeResponsesTableTableManager(
    _$VanDatabase db,
    $NudgeResponsesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NudgeResponsesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NudgeResponsesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NudgeResponsesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> nudgeId = const Value.absent(),
                Value<ResponseType> response = const Value.absent(),
                Value<String?> reasonText = const Value.absent(),
                Value<int> respondedUtc = const Value.absent(),
                Value<int> latencySeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NudgeResponsesCompanion(
                id: id,
                nudgeId: nudgeId,
                response: response,
                reasonText: reasonText,
                respondedUtc: respondedUtc,
                latencySeconds: latencySeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String nudgeId,
                required ResponseType response,
                Value<String?> reasonText = const Value.absent(),
                required int respondedUtc,
                required int latencySeconds,
                Value<int> rowid = const Value.absent(),
              }) => NudgeResponsesCompanion.insert(
                id: id,
                nudgeId: nudgeId,
                response: response,
                reasonText: reasonText,
                respondedUtc: respondedUtc,
                latencySeconds: latencySeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$NudgeResponsesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({nudgeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (nudgeId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.nudgeId,
                                referencedTable: $$NudgeResponsesTableReferences
                                    ._nudgeIdTable(db),
                                referencedColumn:
                                    $$NudgeResponsesTableReferences
                                        ._nudgeIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$NudgeResponsesTableProcessedTableManager =
    ProcessedTableManager<
      _$VanDatabase,
      $NudgeResponsesTable,
      NudgeResponseRow,
      $$NudgeResponsesTableFilterComposer,
      $$NudgeResponsesTableOrderingComposer,
      $$NudgeResponsesTableAnnotationComposer,
      $$NudgeResponsesTableCreateCompanionBuilder,
      $$NudgeResponsesTableUpdateCompanionBuilder,
      (NudgeResponseRow, $$NudgeResponsesTableReferences),
      NudgeResponseRow,
      PrefetchHooks Function({bool nudgeId})
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      required int tsUtc,
      required EventType type,
      Value<String> payloadJson,
      Value<String?> sessionId,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      Value<int> tsUtc,
      Value<EventType> type,
      Value<String> payloadJson,
      Value<String?> sessionId,
    });

class $$EventsTableFilterComposer
    extends Composer<_$VanDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tsUtc => $composableBuilder(
    column: $table.tsUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EventType, EventType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$VanDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tsUtc => $composableBuilder(
    column: $table.tsUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$VanDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get tsUtc =>
      $composableBuilder(column: $table.tsUtc, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EventType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$VanDatabase,
          $EventsTable,
          EventRow,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (EventRow, BaseReferences<_$VanDatabase, $EventsTable, EventRow>),
          EventRow,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$VanDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> tsUtc = const Value.absent(),
                Value<EventType> type = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                tsUtc: tsUtc,
                type: type,
                payloadJson: payloadJson,
                sessionId: sessionId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int tsUtc,
                required EventType type,
                Value<String> payloadJson = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                tsUtc: tsUtc,
                type: type,
                payloadJson: payloadJson,
                sessionId: sessionId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$VanDatabase,
      $EventsTable,
      EventRow,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (EventRow, BaseReferences<_$VanDatabase, $EventsTable, EventRow>),
      EventRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$VanDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$VanDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$VanDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$VanDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$VanDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$VanDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$VanDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$VanDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $VanDatabaseManager {
  final _$VanDatabase _db;
  $VanDatabaseManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$WorkSessionsTableTableManager get workSessions =>
      $$WorkSessionsTableTableManager(_db, _db.workSessions);
  $$NudgesTableTableManager get nudges =>
      $$NudgesTableTableManager(_db, _db.nudges);
  $$NudgeResponsesTableTableManager get nudgeResponses =>
      $$NudgeResponsesTableTableManager(_db, _db.nudgeResponses);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
