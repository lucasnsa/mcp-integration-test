import 'package:mcp_integration_test_server/src/session_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('SessionRecorder', () {
    test('records nothing until started', () {
      final recorder = SessionRecorder()
        ..record('tap', {
          'finder': {'key': 'login'},
        });

      expect(recorder.isRecording, isFalse);
      expect(recorder.steps, isEmpty);
    });

    test('records replayable tools and ignores queries', () {
      final recorder = SessionRecorder()
        ..start()
        ..record('snapshot', {})
        ..record('tap', {
          'finder': {'key': 'login'},
        })
        ..record('getText', {
          'finder': {'key': 'login'},
        })
        ..record('expect', {
          'finder': {'text': 'Login'},
        }, failure: 'expected to exist, found none');

      expect(recorder.steps.map((s) => s.tool), ['tap', 'expect']);
      expect(recorder.steps.last.failure, 'expected to exist, found none');
    });

    test('copies the arguments so later changes do not leak in', () {
      final finder = <String, Object?>{'key': 'login'};
      final args = <String, Object?>{'finder': finder};
      final recorder = SessionRecorder()
        ..start()
        ..record('tap', args);
      finder['key'] = 'changed';
      args['settle'] = false;

      expect(recorder.steps.single.args, {
        'finder': {'key': 'login'},
      });
    });

    test('keeps the steps after stop and clears them on a new start', () {
      final recorder = SessionRecorder()
        ..start()
        ..record('pressBack', {})
        ..stop()
        ..record('pressBack', {});

      expect(recorder.isRecording, isFalse);
      expect(recorder.steps, hasLength(1));

      recorder.start();
      expect(recorder.steps, isEmpty);
    });
  });
}
