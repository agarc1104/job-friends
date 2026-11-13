import 'dart:convert';

class InterviewResponseParts {
  const InterviewResponseParts({
    required this.reply,
    required this.coachFeedback,
    required this.improvedAnswer,
    required this.nextQuestion,
    required this.hasStructuredSections,
  });

  const InterviewResponseParts.empty()
      : reply = '',
        coachFeedback = '',
        improvedAnswer = '',
        nextQuestion = '',
        hasStructuredSections = false;

  final String reply;
  final String coachFeedback;
  final String improvedAnswer;
  final String nextQuestion;
  final bool hasStructuredSections;
}

InterviewResponseParts parseInterviewResponsePayload(Map<String, dynamic> payload) {
  final directReply = _stringValue(payload['reply']);
  final directCoachFeedback = _stringValue(payload['coach_feedback']);
  final directImprovedAnswer = _stringValue(payload['improved_answer']);
  final directNextQuestion = _stringValue(payload['next_question']);

  final parsedFromReply = parseInterviewResponseText(directReply);

  return InterviewResponseParts(
    reply: parsedFromReply.hasStructuredSections && parsedFromReply.reply.isNotEmpty
        ? parsedFromReply.reply
        : directReply,
    coachFeedback: _firstNonEmpty([directCoachFeedback, parsedFromReply.coachFeedback]),
    improvedAnswer: _firstNonEmpty([directImprovedAnswer, parsedFromReply.improvedAnswer]),
    nextQuestion: _firstNonEmpty([directNextQuestion, parsedFromReply.nextQuestion]),
    hasStructuredSections: parsedFromReply.hasStructuredSections,
  );
}

InterviewResponseParts parseInterviewResponseText(String rawText) {
  final trimmed = rawText.trim();
  if (trimmed.isEmpty) {
    return const InterviewResponseParts.empty();
  }

  final jsonCandidate = _extractJsonCandidate(trimmed);
  if (jsonCandidate != null) {
    try {
      final decoded = jsonDecode(jsonCandidate);
      if (decoded is Map<String, dynamic>) {
        return _partsFromMap(decoded, structured: true);
      }
      if (decoded is Map) {
        return _partsFromMap(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
          structured: true,
        );
      }
    } catch (_) {
      // Fall through to the heading-based parser.
    }
  }

  return _parseSectionedText(trimmed);
}

InterviewResponseParts _partsFromMap(Map<String, dynamic> map, {required bool structured}) {
  return InterviewResponseParts(
    reply: _stringValue(_readFirst(map, const ['reply', 'answer', 'response', 'main_reply', 'main_answer'])),
    coachFeedback: _stringValue(_readFirst(map, const ['coach_feedback', 'feedback'])),
    improvedAnswer: _stringValue(_readFirst(map, const ['improved_answer', 'improved_version', 'version_mejorada'])),
    nextQuestion: _stringValue(_readFirst(map, const ['next_question', 'next_challenge', 'follow_up'])),
    hasStructuredSections: structured,
  );
}

InterviewResponseParts _parseSectionedText(String rawText) {
  final lines = rawText.split(RegExp(r'\r?\n'));
  final buffers = <_Section, StringBuffer>{
    _Section.reply: StringBuffer(),
    _Section.feedback: StringBuffer(),
    _Section.improved: StringBuffer(),
    _Section.nextQuestion: StringBuffer(),
  };

  var currentSection = _Section.reply;
  var foundStructuredSection = false;

  for (final line in lines) {
    final header = _matchSectionHeader(line);
    if (header != null) {
      currentSection = header.section;
      foundStructuredSection = true;
      if (header.inlineContent.trim().isNotEmpty) {
        _appendLine(buffers[currentSection]!, header.inlineContent.trim());
      }
      continue;
    }

    _appendLine(buffers[currentSection]!, line);
  }

  if (!foundStructuredSection) {
    return const InterviewResponseParts.empty();
  }

  return InterviewResponseParts(
    reply: _collapseWhitespace(buffers[_Section.reply]!.toString()),
    coachFeedback: _collapseWhitespace(buffers[_Section.feedback]!.toString()),
    improvedAnswer: _collapseWhitespace(buffers[_Section.improved]!.toString()),
    nextQuestion: _collapseWhitespace(buffers[_Section.nextQuestion]!.toString()),
    hasStructuredSections: true,
  );
}

void _appendLine(StringBuffer buffer, String line) {
  if (line.trim().isEmpty) {
    if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
      buffer.writeln();
    }
    return;
  }

  if (buffer.isNotEmpty) {
    buffer.writeln();
  }
  buffer.write(line.trimRight());
}

String _collapseWhitespace(String value) {
  return value
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .trim();
}

String _stringValue(Object? value) {
  return value?.toString().trim() ?? '';
}

Object? _readFirst(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _extractJsonCandidate(String rawText) {
  var candidate = rawText.trim();
  candidate = candidate.replaceFirst(RegExp(r'^json\s*:\s*', caseSensitive: false), '');

  final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false).firstMatch(candidate);
  if (fenced != null) {
    return fenced.group(1)?.trim();
  }

  final start = candidate.indexOf('{');
  final end = candidate.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return candidate.substring(start, end + 1).trim();
  }

  return candidate;
}

_SectionHeader? _matchSectionHeader(String line) {
  final stripped = line.trim().replaceFirst(RegExp(r'^[#>*\-•\s]+'), '');
  if (stripped.isEmpty) {
    return null;
  }

  final separators = [':', ' - '];
  for (final separator in separators) {
    final index = stripped.indexOf(separator);
    if (index >= 0) {
      final header = stripped.substring(0, index).trim();
      final content = stripped.substring(index + separator.length).trim();
      final section = _sectionForHeader(header);
      if (section != null) {
        return _SectionHeader(section, content);
      }
    }
  }

  final section = _sectionForHeader(stripped);
  if (section != null) {
    if (RegExp(r'[.!?]$').hasMatch(stripped)) {
      return null;
    }
    return _SectionHeader(section, '');
  }

  return null;
}

_Section? _sectionForHeader(String header) {
  final normalized = _normalizeHeader(header);
  if (_replyHeaders.contains(normalized)) {
    return _Section.reply;
  }
  if (_feedbackHeaders.contains(normalized)) {
    return _Section.feedback;
  }
  if (_improvedHeaders.contains(normalized)) {
    return _Section.improved;
  }
  if (_nextQuestionHeaders.contains(normalized)) {
    return _Section.nextQuestion;
  }
  return null;
}

String _normalizeHeader(String value) {
  var normalized = value.trim().toLowerCase();
  const replacements = {
    '\u00e1': 'a',
    '\u00e0': 'a',
    '\u00e2': 'a',
    '\u00e4': 'a',
    '\u00e3': 'a',
    '\u00e5': 'a',
    '\u00e7': 'c',
    '\u00e9': 'e',
    '\u00e8': 'e',
    '\u00ea': 'e',
    '\u00eb': 'e',
    '\u00ed': 'i',
    '\u00ec': 'i',
    '\u00ee': 'i',
    '\u00ef': 'i',
    '\u00f1': 'n',
    '\u00f3': 'o',
    '\u00f2': 'o',
    '\u00f4': 'o',
    '\u00f6': 'o',
    '\u00f5': 'o',
    '\u00fa': 'u',
    '\u00f9': 'u',
    '\u00fb': 'u',
    '\u00fc': 'u',
  };

  replacements.forEach((from, to) {
    normalized = normalized.replaceAll(from, to);
  });

  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return normalized.trim();
}

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

enum _Section {
  reply,
  feedback,
  improved,
  nextQuestion,
}

class _SectionHeader {
  const _SectionHeader(this.section, this.inlineContent);

  final _Section section;
  final String inlineContent;
}

const Set<String> _replyHeaders = {
  'reply',
  'answer',
  'response',
  'main reply',
  'main answer',
  'respuesta',
  'respuesta principal',
  'resposta',
  'resposta principal',
  'risposta',
};

const Set<String> _feedbackHeaders = {
  'feedback',
  'coach feedback',
  'retroalimentacion',
  'comentarios',
  'observaciones',
  'retorno',
  'retour',
  'rueckmeldung',
};

const Set<String> _improvedHeaders = {
  'improved version',
  'improved answer',
  'better answer',
  'answer improved',
  'version mejorada',
  'respuesta mejorada',
  'versao melhorada',
  'version amelioree',
  'verbesserte antwort',
  'risposta migliorata',
};

const Set<String> _nextQuestionHeaders = {
  'next challenge',
  'next question',
  'follow up',
  'followup',
  'siguiente reto',
  'siguiente pregunta',
  'proximo desafio',
  'prochaine question',
  'naechste frage',
  'prossima domanda',
};