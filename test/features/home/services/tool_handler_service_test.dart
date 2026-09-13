import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolHandlerService tool schema sanitization', () {
    for (final kind in const [ProviderKind.openai, ProviderKind.claude]) {
      test('preserves and sanitizes additionalProperties for $kind', () {
        final input = <String, dynamic>{
          'type': 'object',
          'additionalProperties': true,
          'properties': {
            'config': {
              'type': 'object',
              'additionalProperties': {
                r'$schema': 'https://json-schema.org/draft/2020-12/schema',
                'type': 'string',
                'const': 'enabled',
              },
            },
            'entries': {
              'type': 'array',
              'items': {'type': 'object', 'additionalProperties': false},
            },
          },
        };

        final output = ToolHandlerService.sanitizeToolParametersForProvider(
          input,
          kind,
        );

        expect(output['additionalProperties'], isTrue);
        final properties = output['properties'] as Map<String, dynamic>;
        expect(
          (properties['config'] as Map)['additionalProperties'],
          <String, dynamic>{
            'type': 'string',
            'enum': ['enabled'],
          },
        );
        expect(
          ((properties['entries'] as Map)['items']
              as Map)['additionalProperties'],
          isFalse,
        );
      });
    }

    test('continues to drop additionalProperties for Google', () {
      final output = ToolHandlerService.sanitizeToolParametersForProvider({
        'type': 'object',
        'additionalProperties': true,
        'properties': {
          'config': {'type': 'object', 'additionalProperties': true},
        },
      }, ProviderKind.google);

      expect(output, isNot(contains('additionalProperties')));
      expect(
        output['properties']['config'],
        isNot(contains('additionalProperties')),
      );
    });
  });

  group('Speech tool path resolution tests', () {
    setUp(() {
      SandboxPathResolver.debugSetDirs(docsDir: '/mock/Documents');
    });

    tearDown(() {
      SandboxPathResolver.debugSetDirs(docsDir: null);
    });

    test('SandboxPathResolver resolves kelivo:// URIs to sandbox documents', () {
      final resolved = SandboxPathResolver.fix('kelivo://01ea9b06405dae274f037001a06d90e0d4_258.m4a');
      expect(resolved, '/mock/Documents/01ea9b06405dae274f037001a06d90e0d4_258.m4a');
    });

    test('SandboxPathResolver resolves kelivo-file:/// URIs to sandbox documents', () {
      final resolved = SandboxPathResolver.fix('kelivo-file:///upload/audio.m4a');
      expect(resolved, '/mock/Documents/upload/audio.m4a');
    });
  });
}

