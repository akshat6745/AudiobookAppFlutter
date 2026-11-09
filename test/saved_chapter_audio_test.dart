import 'package:audiobook_app/services/saved_chapter_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lines = ['The wheel', '[IMAGE: map]', 'He rode on.'];

  Map<String, dynamic> manifest({bool silentGap = true, bool dropLast = false}) {
    final paragraphs = [
      {'index': 0, 'file': '0.opus'},
      if (silentGap) {'index': 1, 'file': '1.opus', 'silent': true},
      if (!dropLast) {'index': 2, 'file': '2.opus'},
    ];
    return {
      'files': {
        'title.opus': true,
        'chapter.opus': true,
        '0.opus': true,
        '1.opus': true,
        if (!dropLast) '2.opus': true,
      },
      'paragraphs': paragraphs,
    };
  }

  test('a chapter is complete when every playable line has audio', () {
    expect(studentChapterIsComplete(manifest(), lines), isTrue);
  });

  test('a missing paragraph hides the saved option', () {
    expect(studentChapterIsComplete(manifest(dropLast: true), lines), isFalse);
  });

  test('an image line must be marked silent or skipped', () {
    expect(
      studentChapterIsComplete(manifest(silentGap: false), lines),
      isTrue,
    );
  });

  test('playback index 0 is the title and body indexes follow the file', () {
    expect(savedParagraphParam(0), 'title');
    expect(savedParagraphParam(1), '0');
    expect(savedParagraphParam(3), '2');
  });
}
