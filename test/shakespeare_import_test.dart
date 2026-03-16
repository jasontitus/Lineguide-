import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:castcircle/data/models/script_models.dart';
import 'package:castcircle/data/services/script_parser.dart';

void main() {
  group('Gutenberg wrapper stripping', () {
    test('strips preamble and postamble', () {
      const text = '''
The Project Gutenberg eBook of Hamlet

Title: Hamlet
Author: William Shakespeare

*** START OF THE PROJECT GUTENBERG EBOOK HAMLET ***

ELIZABETH. Actual script content.

*** END OF THE PROJECT GUTENBERG EBOOK HAMLET ***

Some licensing text here.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'Gutenberg Test');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(lines.length, 1);
      expect(lines.first.character, 'ELIZABETH');
    });

    test('works fine when no Gutenberg markers present', () {
      const text = '''
ELIZABETH. First line.
DARCY. Second line.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'No Gutenberg');
      expect(
        script.lines.where((l) => l.lineType == LineType.dialogue).length,
        2,
      );
    });
  });

  group('Format detection', () {
    test('detects standard format (name + dialogue on same line)', () {
      const text = '''
ELIZABETH. First line of dialogue.
DARCY. Second line of dialogue.
ELIZABETH. Third line of dialogue.
DARCY. Fourth line of dialogue.
ELIZABETH. Fifth line of dialogue.
DARCY. Sixth line of dialogue.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'Standard');
      // Standard format should still work as before
      expect(
        script.lines.where((l) => l.lineType == LineType.dialogue).length,
        6,
      );
    });

    test('detects name-on-own-line format (Macbeth style)', () {
      const text = '''
MACBETH.
So foul and fair a day I have not seen.

BANQUO.
How far is it call'd to Forres?

MACBETH.
Speak, if you can; what are you?

FIRST WITCH.
All hail, Macbeth!

SECOND WITCH.
Hail to thee, Thane of Cawdor!

THIRD WITCH.
All hail, Macbeth, that shalt be king hereafter!
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'Macbeth Style');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(lines.length, 6);
      expect(lines[0].character, 'MACBETH');
      expect(lines[0].text, contains('foul and fair'));
      expect(lines[1].character, 'BANQUO');
      expect(lines[3].character, 'FIRST WITCH');
    });

    test('detects title-case format (First Folio style)', () {
      const text = '''
Enter Barnardo and Francisco.

  Barnardo. Who's there?
  Fran. Nay answer me: Stand and unfold yourself.

  Bar. Long live the King.

  Fran. Barnardo?
  Bar. He.

  Fran. You come most carefully upon your hour.

  Bar. 'Tis now struck twelve, get thee to bed Francisco.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'First Folio');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      // Should detect characters and lines
      expect(lines.length, greaterThanOrEqualTo(5));
      // Bar/Barn should be merged via prefix matching
      final chars = script.characters.map((c) => c.name).toSet();
      // Should have BARNARDO (or BARN) as a character (resolved from Bar/Barn)
      expect(
        chars.any((c) => c.startsWith('BAR')),
        isTrue,
        reason: 'Should detect Barnardo variants as a character',
      );
      expect(
        chars.any((c) => c.startsWith('FRAN')),
        isTrue,
        reason: 'Should detect Francisco variants as a character',
      );
    });
  });

  group('Macbeth parsing (name-on-own-line format)', () {
    late ScriptParser parser;

    setUp(() {
      parser = ScriptParser();
    });

    test('parses character names on their own line', () {
      const text = '''
ACT I

SCENE I. An open Place.

FIRST WITCH.
When shall we three meet again?
In thunder, lightning, or in rain?

SECOND WITCH.
When the hurlyburly's done,
When the battle's lost and won.

THIRD WITCH.
That will be ere the set of sun.
''';
      final script = parser.parse(text, title: 'Macbeth Scene 1');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(lines.length, 3);
      expect(lines[0].character, 'FIRST WITCH');
      expect(lines[0].text, contains('meet again'));
      expect(lines[0].text, contains('rain'));
      expect(lines[1].character, 'SECOND WITCH');
      expect(lines[2].character, 'THIRD WITCH');
    });

    test('handles multi-line dialogue in name-on-own-line format', () {
      const text = '''
MACBETH.
Tomorrow, and tomorrow, and tomorrow,
Creeps in this petty pace from day to day,
To the last syllable of recorded time.

LADY MACBETH.
Out, damned spot! Out, I say!
''';
      final script = parser.parse(text, title: 'Macbeth Multiline');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(lines.length, 2);
      expect(lines[0].character, 'MACBETH');
      expect(lines[0].text, contains('Tomorrow'));
      expect(lines[0].text, contains('recorded time'));
      expect(lines[1].character, 'LADY MACBETH');
    });

    test('detects Enter/Exit as stage directions', () {
      const text = '''
DUNCAN.
What bloody man is that?

 Enter Ross and Angus.

MALCOLM.
The worthy Thane of Ross.
''';
      final script = parser.parse(text, title: 'Macbeth Directions');
      final directions = script.lines
          .where((l) => l.lineType == LineType.stageDirection)
          .toList();
      expect(directions.length, greaterThanOrEqualTo(1));
      expect(
        directions.any((d) => d.text.contains('Ross') || d.text.contains('Enter')),
        isTrue,
      );
      // Dialogue should not include the stage direction text
      final dialogue =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      for (final line in dialogue) {
        expect(line.text, isNot(contains('Enter Ross')));
      }
    });

    test('detects bracketed stage directions [_Exeunt._]', () {
      const text = '''
MACBETH.
Lead me to the chamber.

[_Exeunt._]

ROSS.
Is it known who did this?
''';
      final script = parser.parse(text, title: 'Macbeth Brackets');
      final directions = script.lines
          .where((l) => l.lineType == LineType.stageDirection)
          .toList();
      expect(directions, isNotEmpty);
    });

    test('detects ACT and SCENE headers', () {
      const text = '''
ACT I

SCENE I. An open Place.

FIRST WITCH.
When shall we three meet again?

SCENE II. A Camp near Forres.

DUNCAN.
What bloody man is that?

ACT II

SCENE I. Court within the Castle.

MACBETH.
Is this a dagger which I see before me?
''';
      final script = parser.parse(text, title: 'Macbeth Acts');
      final headers =
          script.lines.where((l) => l.lineType == LineType.header).toList();
      expect(headers.length, 2);
      expect(headers[0].text, contains('ACT I'));
      expect(headers[1].text, contains('ACT II'));
    });

    test('finds all major Macbeth characters', () {
      const text = '''
ACT I

SCENE I. An open Place.

FIRST WITCH.
When shall we three meet again?

SECOND WITCH.
When the hurlyburly's done.

THIRD WITCH.
That will be ere the set of sun.

ALL.
Fair is foul, and foul is fair.

SCENE II. A Camp near Forres.

DUNCAN.
What bloody man is that?

MALCOLM.
This is the sergeant.

SCENE III. A heath.

MACBETH.
So foul and fair a day I have not seen.

BANQUO.
How far is it to Forres?

ROSS.
God save the King!

LENNOX.
What a haste looks through his eyes!

SCENE V. A Room in the Castle.

LADY MACBETH.
They met me in the day of success.

SCENE IV. A Room in the Palace.

MACDUFF.
Is the King stirring?
''';
      final script = parser.parse(text, title: 'Macbeth Full Cast');
      final charNames = script.characters.map((c) => c.name).toSet();
      expect(charNames, contains('MACBETH'));
      expect(charNames, contains('LADY MACBETH'));
      expect(charNames, contains('BANQUO'));
      expect(charNames, contains('DUNCAN'));
      expect(charNames, contains('MALCOLM'));
      expect(charNames, contains('MACDUFF'));
      expect(charNames, contains('ROSS'));
      expect(charNames, contains('FIRST WITCH'));
    });
  });

  group('Hamlet parsing (title-case format)', () {
    late ScriptParser parser;

    setUp(() {
      parser = ScriptParser();
    });

    test('parses title-case character names with dialogue on same line', () {
      const text = '''
  Ham. To be, or not to be, that is the question.

  Hor. My lord, I came to see your father's funeral.

  Ham. I pray thee, do not mock me.

  Hor. Indeed, my lord, it followed hard upon.

  Ham. Thrift, thrift, Horatio!
''';
      final script = parser.parse(text, title: 'Hamlet Dialogue');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(lines.length, 5);
      // HAM should be detected (and possibly resolved to HAMLET via aliases)
      final hamletChar = lines[0].character;
      expect(hamletChar, startsWith('HAM'));
    });

    test('resolves abbreviated names via Enter stage directions', () {
      const text = '''
Enter Hamlet and Horatio.

  Ham. The air bites shrewdly.

  Hor. It is a nipping and an eager air.

  Ham. What hour now?

  Hor. I think it lacks of twelve.

  Mar. No, it is struck.

Enter Marcellus.

  Mar. Holla Barnardo!

  Ham. The time is out of joint.
''';
      final script = parser.parse(text, title: 'Hamlet Names');
      final charNames = script.characters.map((c) => c.name).toSet();
      // HAM should resolve to HAMLET via "Enter Hamlet and Horatio"
      expect(charNames, contains('HAMLET'));
      // HOR should resolve to HORATIO
      expect(charNames, contains('HORATIO'));
      // MAR should resolve to MARCELLUS
      expect(charNames, contains('MARCELLUS'));
    });

    test('handles Latin act/scene headers', () {
      const text = '''
Actus Primus. Scoena Prima.

Enter Barnardo and Francisco.

  Barnardo. Who's there?
  Fran. Nay answer me.

Scena Secunda.

Enter King and Queen.

  King. Though yet of Hamlet our dear brother's death.

  Queen. Good Hamlet, cast thy nightly colour off.
''';
      final script = parser.parse(text, title: 'Hamlet Acts');
      final headers =
          script.lines.where((l) => l.lineType == LineType.header).toList();
      expect(headers.length, greaterThanOrEqualTo(1));
      // Should detect characters across scenes
      final charNames = script.characters.map((c) => c.name).toSet();
      expect(charNames, isNotEmpty);
      expect(
        charNames.any((c) => c.startsWith('KING')),
        isTrue,
      );
    });

    test('merges prefix abbreviations (Bar → Barn → Barnardo)', () {
      const text = '''
Enter Barnardo and Francisco.

  Barnardo. Who's there?

  Bar. Long live the King.

  Barn. Have you had quiet guard?

  Bar. 'Tis now struck twelve.

  Barn. In the same figure, like the king that's dead.
''';
      final script = parser.parse(text, title: 'Hamlet Abbreviations');
      final charNames = script.characters.map((c) => c.name).toSet();
      // All variants (BAR, BARN, BARNARDO) should merge to BARNARDO
      expect(charNames, contains('BARNARDO'));
      expect(charNames, isNot(contains('BAR')));
      expect(charNames, isNot(contains('BARN')));
    });

    test('handles Enter/Exit as stage directions in First Folio', () {
      const text = '''
  Hor. Friends to this ground.

Enter the Ghost.

  Hor. Stay! Speak! I charge thee speak.

Exit the Ghost.

  Mar. 'Tis gone, and will not answer.
''';
      final script = parser.parse(text, title: 'Hamlet Directions');
      final directions = script.lines
          .where((l) => l.lineType == LineType.stageDirection)
          .toList();
      expect(directions.length, greaterThanOrEqualTo(2));
      // Dialogue should not contain Enter/Exit text
      final dialogue =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(dialogue.length, greaterThanOrEqualTo(2));
      for (final line in dialogue) {
        expect(line.text, isNot(startsWith('Enter')));
        expect(line.text, isNot(startsWith('Exit')));
      }
    });
  });

  group('Full Shakespeare file parsing', () {
    test('Macbeth text file produces characters and dialogue', () {
      final file = File('sample-scripts/macbeth-pg1533-images-3.txt');
      if (!file.existsSync()) {
        // Skip if file not available (CI environment)
        return;
      }
      final rawText = file.readAsStringSync();
      final parser = ScriptParser();
      final script = parser.parse(rawText, title: 'Macbeth');

      final charNames = script.characters.map((c) => c.name).toSet();
      final dialogue =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();

      // Must have characters
      expect(script.characters.length, greaterThan(10),
          reason: 'Macbeth has 20+ speaking characters');

      // Must have substantial dialogue
      expect(dialogue.length, greaterThan(200),
          reason: 'Macbeth has 600+ speeches');

      // Key characters must be present
      expect(charNames, contains('MACBETH'));
      expect(charNames, contains('LADY MACBETH'));
      expect(charNames, contains('BANQUO'));
      expect(charNames, contains('DUNCAN'));
      expect(charNames, contains('MACDUFF'));
      expect(charNames, contains('MALCOLM'));
      expect(charNames, contains('ROSS'));
      expect(charNames, contains('LENNOX'));

      // MACBETH should have the most lines
      final macbeth =
          script.characters.firstWhere((c) => c.name == 'MACBETH');
      expect(macbeth.lineCount, greaterThan(50));
      expect(script.characters.first.name, 'MACBETH',
          reason: 'MACBETH should be the character with the most lines');

      // Should have multiple acts
      final headers =
          script.lines.where((l) => l.lineType == LineType.header).toList();
      expect(headers.length, greaterThanOrEqualTo(4),
          reason: 'Macbeth has 5 acts');
    });

    test('Hamlet text file produces characters and dialogue', () {
      final file = File('sample-scripts/hamlet-pg1524-images-3.txt');
      if (!file.existsSync()) {
        return;
      }
      final rawText = file.readAsStringSync();
      final parser = ScriptParser();
      final script = parser.parse(rawText, title: 'Hamlet');

      final charNames = script.characters.map((c) => c.name).toSet();
      final dialogue =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();

      // Must have characters
      expect(script.characters.length, greaterThan(5),
          reason: 'Hamlet has many speaking characters');

      // Must have substantial dialogue
      expect(dialogue.length, greaterThan(200),
          reason: 'Hamlet has 1000+ speeches');

      // Key characters should be present (resolved from abbreviations)
      // Ham → HAMLET (via Enter stage directions)
      expect(charNames, contains('HAMLET'),
          reason: 'Ham. should resolve to HAMLET via Enter directions');

      // Hor → HORATIO
      expect(charNames, contains('HORATIO'),
          reason: 'Hor. should resolve to HORATIO');

      // HAMLET should have the most lines
      final hamlet =
          script.characters.firstWhere((c) => c.name == 'HAMLET');
      expect(hamlet.lineCount, greaterThan(50));
    });
  });

  group('Standard format not broken', () {
    test('Pride & Prejudice style still works perfectly', () {
      const text = '''
ACT I

ELIZABETH. I could easily forgive his pride, if he had not mortified mine.

DARCY. I have been meditating on the very great pleasure which a pair of fine eyes can bestow.

(She exits.)

ELIZABETH. A man who has once been refused! How could I be so blind?

MR. BENNET. I have the pleasure of understanding your character.

MRS. BENNET. Oh my nerves!

BINGLEY. Your sister is the most beautiful creature.

ELIZABETH. I do not want people to be agreeable.

DARCY. My good opinion once lost is lost forever.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'P&P Test');

      final charNames = script.characters.map((c) => c.name).toSet();
      expect(charNames, contains('ELIZABETH'));
      expect(charNames, contains('DARCY'));
      expect(charNames, contains('MR. BENNET'));
      expect(charNames, contains('MRS. BENNET'));
      expect(charNames, contains('BINGLEY'));

      final dialogue =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(dialogue.length, 7);

      // Stage direction should be detected
      final directions = script.lines
          .where((l) => l.lineType == LineType.stageDirection)
          .toList();
      expect(directions.length, 1);

      // Characters sorted by line count
      expect(script.characters[0].name, 'ELIZABETH');
      expect(script.characters[0].lineCount, 3);
    });

    test('multi-line dialogue continuation still works', () {
      const text = '''
ELIZABETH. I could easily forgive
his pride, if he had not
mortified mine.

DARCY. Indeed.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'Continuation Test');
      final lines =
          script.lines.where((l) => l.lineType == LineType.dialogue).toList();
      expect(lines.length, 2);
      expect(lines[0].text, contains('forgive'));
      expect(lines[0].text, contains('mortified'));
      expect(lines[0].character, 'ELIZABETH');
    });

    test('inline stage directions still work', () {
      const text = '''
ELIZABETH. (sarcastically:) How delightful.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'Inline Direction');
      final line =
          script.lines.firstWhere((l) => l.lineType == LineType.dialogue);
      expect(line.stageDirection, 'sarcastically');
      expect(line.text, 'How delightful.');
    });

    test('shift scene transitions still work', () {
      const text = '''
ACT I

ELIZABETH. We are at Longbourn.

(Shift begins into Netherfield.)

DARCY. Welcome to Netherfield.
''';
      final parser = ScriptParser();
      final script = parser.parse(text, title: 'Shift Test');
      expect(script.scenes.length, greaterThanOrEqualTo(1));
    });
  });
}
