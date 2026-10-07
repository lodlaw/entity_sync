import 'package:test/test.dart';

import 'package:entity_sync/entity_sync.dart';

class TestEntity with SerializableMixin, SyncableMixin {
  final int id;
  final String? name;
  final DateTime? created;
  final bool shouldSync;

  /// The unique syncable key of the entity
  @override
  final keyField = IntegerField('id');

  /// The flag to indicate the entity needs to be synced
  @override
  final flagField = BoolField('shouldSync');

  TestEntity({
    required this.id,
    this.name,
    this.created,
    this.shouldSync = false,
  });

  @override
  SerializableMixin copyFromMap(Map<String, dynamic> mapData) {
    return TestEntity(
      id: mapData['id'],
      name: mapData['name'],
      created: mapData['created'],
      shouldSync: mapData['shouldSync'],
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created': created,
      'shouldSync': shouldSync,
    };
  }
}

class TestEntitySerializer extends Serializer<TestEntity> {
  TestEntitySerializer({
    Map<String, dynamic>? data,
    TestEntity? instance,
    String prefix = '',
  }) : super(data: data, instance: instance, prefix: prefix);

  @override
  final fields = [
    IntegerField('id', source: 'id'),
    StringField('name', source: 'name'),
    DateTimeField('created', source: 'created'),
  ];

  int validateId(int value) {
    if (value < 0) {
      throw ValidationException('id must be positive value');
    }

    return value;
  }

  String validateName(String? value) {
    if (value == null) {
      throw ValidationException('name must not be null');
    }

    if (value.isEmpty) {
      throw ValidationException('name must not be empty');
    }

    return value;
  }

  DateTime validateCreated(DateTime? value) {
    if (value == null) {
      throw ValidationException('created must not be null');
    }

    return value;
  }

  @override
  TestEntity createInstance(Map<String, dynamic> validatedData) {
    return TestEntity(
      id: validatedData['id'],
      name: validatedData['name'],
      created: validatedData['created'],
      shouldSync: false,
    );
  }

  @override
  Map toMap() {
    return {
      'validateId': validateId,
      'validateName': validateName,
      'validateCreated': validateCreated,
    };
  }
}

class RelatedTestEntitySerializer extends TestEntitySerializer {
  RelatedTestEntitySerializer({
    Map<String, dynamic>? data,
    TestEntity? instance,
    String prefix = '',
  }) : super(data: data, instance: instance, prefix: prefix);

  @override
  final fields = [
    IntegerField('id', source: 'id'),
    StringField('name', source: 'name', prefix: 'activity/'),
    DateTimeField('created', source: 'created'),
  ];
}

void main() {
  group('Test Serializer', () {
    setUp(() {});

    test('Test TestEntitySerializer.isValid method with valid entity', () {
      final entity =
          TestEntity(id: 0, name: 'TestName', created: DateTime.now());
      final serializer = TestEntitySerializer(instance: entity);

      expect(serializer.isValid(), isTrue);
    });

    test('Test TestEntitySerializer.isValid method with invalid entity', () {
      var entity = TestEntity(id: 0, name: null, created: DateTime.now());
      var serializer = TestEntitySerializer(instance: entity);

      expect(serializer.isValid(), isFalse);

      entity = TestEntity(id: 0, name: '', created: DateTime.now());
      serializer = TestEntitySerializer(instance: entity);

      expect(serializer.isValid(), isFalse);

      entity = TestEntity(id: -1, name: 'TestName', created: DateTime.now());
      serializer = TestEntitySerializer(instance: entity);

      expect(serializer.isValid(), isFalse);

      entity = TestEntity(id: 0, name: 'TestName', created: null);
      serializer = TestEntitySerializer(instance: entity);

      expect(serializer.isValid(), isFalse);
    });

    test('normalizes incoming related URL from a different host', () {
      final serializer = TestEntitySerializer(
        data: const {},
        prefix: 'https://current.example.com/m/',
      );

      final result = serializer.validateField(
        const StringField('name', prefix: 'activity/'),
        'https://other.example.com/m/activity/abc-123/',
      );

      expect(result, equals('abc-123'));
    });

    test('prefixes outgoing related UUID with current backend URL', () {
      final serializer = TestEntitySerializer(
        instance: TestEntity(
          id: 1,
          name: 'abc-123',
          created: DateTime(2026),
        ),
        prefix: 'https://current.example.com/m/',
      );

      final result = serializer.validateField(
        const StringField('name', prefix: 'activity/'),
        'abc-123',
      );

      expect(
        result,
        equals('https://current.example.com/m/activity/abc-123/'),
      );
    });

    test('rejects related URLs without an id', () {
      final serializer = TestEntitySerializer(
        data: const {},
        prefix: 'https://current.example.com/m/',
      );
      const field = StringField('name', prefix: 'activity/');

      for (final value in [
        'https://other.example.com',
        'https://other.example.com/',
      ]) {
        expect(
          () => serializer.validateField(field, value),
          throwsA(isA<ValidationException>()),
        );
      }
    });

    test('rejects a foreign URL for a different resource', () {
      final serializer = TestEntitySerializer(
        data: const {},
        prefix: 'https://current.example.com/m/',
      );

      expect(
        () => serializer.validateField(
          const StringField('name', prefix: 'activity/'),
          'https://other.example.com/m/user/abc-123/',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a same-host URL for a different resource', () {
      final serializer = TestEntitySerializer(
        data: const {},
        prefix: 'https://current.example.com/m/',
      );

      expect(
        () => serializer.validateField(
          const StringField('name', prefix: 'activity/'),
          'https://current.example.com/m/user/abc-123/',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('normalizes uppercase HTTPS related URL', () {
      final serializer = TestEntitySerializer(
        data: const {},
        prefix: 'https://current.example.com/m/',
      );

      final result = serializer.validateField(
        const StringField('name', prefix: 'activity/'),
        'HTTPS://other.example.com/m/activity/abc-123/',
      );

      expect(result, equals('abc-123'));
    });

    test('validates related values through isValid and toInstance', () {
      final validCases = <Map<String, String>>[
        {
          'value': 'https://other.example.com/m/activity/abc-123/',
          'expected': 'abc-123',
        },
        {
          'value': 'https://current.example.com/m/activity/abc-123/',
          'expected': 'abc-123',
        },
        {
          'value': 'abc-123',
          'expected': 'https://current.example.com/m/activity/abc-123/',
        },
        {
          'value': 'HTTPS://other.example.com/m/activity/abc-123/',
          'expected': 'abc-123',
        },
      ];

      for (final testCase in validCases) {
        final serializer = RelatedTestEntitySerializer(
          data: {
            'id': 1,
            'name': testCase['value'],
            'created': DateTime(2026),
          },
          prefix: 'https://current.example.com/m/',
        );

        expect(
          serializer.isValid(),
          isTrue,
          reason: testCase['value'],
        );
        expect(
          serializer.toInstance()?.name,
          equals(testCase['expected']),
          reason: testCase['value'],
        );
      }
    });

    test('rejects invalid related values through isValid and toInstance', () {
      for (final value in [
        'https://other.example.com',
        'https://other.example.com/',
        'https://other.example.com/m/user/abc-123/',
        'https://current.example.com/m/user/abc-123/',
      ]) {
        final serializer = RelatedTestEntitySerializer(
          data: {
            'id': 1,
            'name': value,
            'created': DateTime(2026),
          },
          prefix: 'https://current.example.com/m/',
        );

        expect(serializer.isValid(), isFalse, reason: value);
        expect(serializer.toInstance(), isNull, reason: value);
      }
    });

    test('Test TestEntitySerializer.toJson method with valid entity', () {
      final entity =
          TestEntity(id: 0, name: 'TestName', created: DateTime.now());
      final serializer = TestEntitySerializer(instance: entity);

      final repr = serializer.toRepresentationString();

      // expect(repr, isNotNull);
      expect(repr, isNotEmpty);
    });
  });
}
