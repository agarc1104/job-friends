import '../l10n/localized_text.dart';

enum InterviewPracticeMode {
  simulation,
  star,
  technical,
  salary,
  hardQuestions,
}

extension InterviewPracticeModeX on InterviewPracticeMode {
  String get key {
    switch (this) {
      case InterviewPracticeMode.simulation:
        return 'simulation';
      case InterviewPracticeMode.star:
        return 'star';
      case InterviewPracticeMode.technical:
        return 'technical';
      case InterviewPracticeMode.salary:
        return 'salary';
      case InterviewPracticeMode.hardQuestions:
        return 'hard_questions';
    }
  }

  String labelFor(String languageCode) {
    switch (this) {
      case InterviewPracticeMode.simulation:
        return _modeLocalized(languageCode, 'interview.mode.simulation', _fallback(languageCode, en: 'Real simulation', es: 'Simulacion real', pt: 'Simulacao real', fr: 'Simulation reelle', de: 'Echte Simulation', it: 'Simulazione reale'));
      case InterviewPracticeMode.star:
        return _modeLocalized(languageCode, 'interview.mode.star', _fallback(languageCode, en: 'STAR response', es: 'Respuesta STAR', pt: 'Resposta STAR', fr: 'Reponse STAR', de: 'STAR-Antwort', it: 'Risposta STAR'));
      case InterviewPracticeMode.technical:
        return _modeLocalized(languageCode, 'interview.mode.technical', _fallback(languageCode, en: 'Technical questions', es: 'Preguntas tecnicas', pt: 'Perguntas tecnicas', fr: 'Questions techniques', de: 'Technische Fragen', it: 'Domande tecniche'));
      case InterviewPracticeMode.salary:
        return _modeLocalized(languageCode, 'interview.mode.salary', _fallback(languageCode, en: 'Salary negotiation', es: 'Negociacion salarial', pt: 'Negociacao salarial', fr: 'Negociation salariale', de: 'Gehaltsverhandlung', it: 'Negoziazione salariale'));
      case InterviewPracticeMode.hardQuestions:
        return _modeLocalized(languageCode, 'interview.mode.hardQuestions', _fallback(languageCode, en: 'Hard questions', es: 'Preguntas dificiles', pt: 'Perguntas dificeis', fr: 'Questions difficiles', de: 'Schwierige Fragen', it: 'Domande difficili'));
    }
  }

  String assistantTitleFor(String languageCode) {
    switch (this) {
      case InterviewPracticeMode.simulation:
        return _modeLocalized(languageCode, 'interview.assistant.simulation', _fallback(languageCode, en: 'AI interviewer', es: 'Entrevistador IA', pt: 'Entrevistador IA', fr: 'Intervieweur IA', de: 'KI-Interviewer', it: 'Intervistatore IA'));
      case InterviewPracticeMode.star:
        return _modeLocalized(languageCode, 'interview.assistant.star', _fallback(languageCode, en: 'STAR coach', es: 'Coach STAR', pt: 'Coach STAR', fr: 'Coach STAR', de: 'STAR-Coach', it: 'Coach STAR'));
      case InterviewPracticeMode.technical:
        return _modeLocalized(languageCode, 'interview.assistant.technical', _fallback(languageCode, en: 'Technical interviewer', es: 'Entrevistador tecnico', pt: 'Entrevistador tecnico', fr: 'Intervieweur technique', de: 'Technischer Interviewer', it: 'Intervistatore tecnico'));
      case InterviewPracticeMode.salary:
        return _modeLocalized(languageCode, 'interview.assistant.salary', _fallback(languageCode, en: 'Negotiation coach', es: 'Coach de negociacion', pt: 'Coach de negociacao', fr: 'Coach de negotiation', de: 'Verhandlungscoach', it: 'Coach di negoziazione'));
      case InterviewPracticeMode.hardQuestions:
        return _modeLocalized(languageCode, 'interview.assistant.hardQuestions', _fallback(languageCode, en: 'Hard questions coach', es: 'Coach de preguntas dificiles', pt: 'Coach de perguntas dificeis', fr: 'Coach de questions difficiles', de: 'Coach fur schwierige Fragen', it: 'Coach per domande difficili'));
    }
  }

  String descriptionFor(String languageCode) {
    switch (this) {
      case InterviewPracticeMode.simulation:
        return _modeLocalized(languageCode, 'interview.desc.simulation', _fallback(languageCode, en: 'Practice a full interview with progressive questions and feedback.', es: 'Practica una entrevista de punta a punta, con preguntas progresivas y feedback.', pt: 'Pratique uma entrevista completa com perguntas progressivas e feedback.', fr: 'Entrainez-vous a un entretien complet avec questions progressives et feedback.', de: 'Uben Sie ein vollstandiges Interview mit aufeinander aufbauenden Fragen und Feedback.', it: 'Esercitati con un colloquio completo con domande progressive e feedback.'));
      case InterviewPracticeMode.star:
        return _modeLocalized(languageCode, 'interview.desc.star', _fallback(languageCode, en: 'Turn your experience into clear STAR-structured answers.', es: 'Convierte tus experiencias en respuestas claras usando la estructura STAR.', pt: 'Transforme sua experiencia em respostas claras usando a estrutura STAR.', fr: 'Transformez vos experiences en reponses claires avec la structure STAR.', de: 'Verwandeln Sie Ihre Erfahrung mit der STAR-Struktur in klare Antworten.', it: 'Trasforma la tua esperienza in risposte chiare con la struttura STAR.'));
      case InterviewPracticeMode.technical:
        return _modeLocalized(languageCode, 'interview.desc.technical', _fallback(languageCode, en: 'Train technical depth and clarity of reasoning.', es: 'Entrena preguntas de profundidad tecnica y claridad de razonamiento.', pt: 'Treine profundidade tecnica e clareza de raciocinio.', fr: 'Travaillez la profondeur technique et la clarte du raisonnement.', de: 'Trainieren Sie technische Tiefe und klares Denken.', it: 'Allena profondita tecnica e chiarezza di ragionamento.'));
      case InterviewPracticeMode.salary:
        return _modeLocalized(languageCode, 'interview.desc.salary', _fallback(languageCode, en: 'Practice defending your value with concrete arguments.', es: 'Practica como defender tu valor y negociar con argumentos concretos.', pt: 'Pratique como defender seu valor com argumentos concretos.', fr: 'Entrainez-vous a defendre votre valeur avec des arguments concrets.', de: 'Ueben Sie, Ihren Wert mit konkreten Argumenten zu verteidigen.', it: 'Esercitati a difendere il tuo valore con argomenti concreti.'));
      case InterviewPracticeMode.hardQuestions:
        return _modeLocalized(languageCode, 'interview.desc.hardQuestions', _fallback(languageCode, en: 'Rehearse answers for high-pressure moments.', es: 'Ensaya respuestas para momentos incomodos o de alta presion.', pt: 'Treine respostas para momentos desconfortaveis ou de alta pressao.', fr: 'Repetez des reponses pour les moments inconfortables ou sous pression.', de: 'Ueben Sie Antworten fuer unangenehme oder stressige Situationen.', it: 'Prova risposte per momenti scomodi o ad alta pressione.'));
    }
  }

  List<String> starterPromptsFor(String languageCode) {
    final normalized = _supportedLanguageCodes.contains(languageCode) ? languageCode : 'es';
    switch (this) {
      case InterviewPracticeMode.simulation:
        return [
          _translation(normalized, 'interview.prompt.simulation.1', _fallback(normalized, en: 'Introduce yourself in 60 seconds for this role', es: 'Presentate en 60 segundos para esta vacante', pt: 'Apresente-se em 60 segundos para esta vaga', fr: 'Presentez-vous en 60 secondes pour ce poste', de: 'Stellen Sie sich in 60 Sekunden fur diese Stelle vor', it: 'Presentati in 60 secondi per questa posizione')),
          _translation(normalized, 'interview.prompt.simulation.2', _fallback(normalized, en: 'Ask me a relevant experience question', es: 'Hazme una pregunta de experiencia relevante', pt: 'Faca-me uma pergunta relevante sobre experiencia', fr: 'Posez-moi une question pertinente sur mon experience', de: 'Stellen Sie mir eine relevante Frage zu meiner Erfahrung', it: 'Fammi una domanda rilevante sulla mia esperienza')),
          _translation(normalized, 'interview.prompt.simulation.3', _fallback(normalized, en: 'Let us simulate the interview closing', es: 'Simulemos el cierre de entrevista', pt: 'Vamos simular o encerramento da entrevista', fr: 'Simulons la conclusion de lentretien', de: 'Lassen Sie uns den Interviewabschluss simulieren', it: 'Simuliamo la chiusura del colloquio')),
        ];
      case InterviewPracticeMode.star:
        return [
          _translation(normalized, 'interview.prompt.star.1', _fallback(normalized, en: 'Turn this achievement into STAR format', es: 'Convierte este logro a formato STAR', pt: 'Transforme esta conquista em formato STAR', fr: 'Transformez cette realisation en format STAR', de: 'Formulieren Sie diesen Erfolg im STAR-Format', it: 'Trasforma questo risultato nel formato STAR')),
          _translation(normalized, 'interview.prompt.star.2', _fallback(normalized, en: 'Give me feedback on my STAR answer', es: 'Dame feedback de mi respuesta STAR', pt: 'De feedback sobre minha resposta STAR', fr: 'Donnez-moi un retour sur ma reponse STAR', de: 'Geben Sie mir Feedback zu meiner STAR-Antwort', it: 'Dammi un feedback sulla mia risposta STAR')),
          _translation(normalized, 'interview.prompt.star.3', _fallback(normalized, en: 'Give me a question to practice STAR', es: 'Dame una pregunta para practicar STAR', pt: 'Me de uma pergunta para praticar STAR', fr: 'Donnez-moi une question pour pratiquer STAR', de: 'Geben Sie mir eine Frage zum Uben von STAR', it: 'Dammi una domanda per praticare STAR')),
        ];
      case InterviewPracticeMode.technical:
        return [
          _translation(normalized, 'interview.prompt.technical.1', _fallback(normalized, en: 'Ask me a mid-level technical question', es: 'Hazme una pregunta tecnica de nivel intermedio', pt: 'Faca-me uma pergunta tecnica de nivel intermediario', fr: 'Posez-moi une question technique de niveau intermediaire', de: 'Stellen Sie mir eine technische Frage auf mittlerem Niveau', it: 'Fammi una domanda tecnica di livello intermedio')),
          _translation(normalized, 'interview.prompt.technical.2', _fallback(normalized, en: 'Evaluate the clarity of my technical reasoning', es: 'Evalua la claridad de mi razonamiento tecnico', pt: 'Avalie a clareza do meu raciocinio tecnico', fr: 'Evaluez la clarte de mon raisonnement technique', de: 'Bewerten Sie die Klarheit meiner technischen Argumentation', it: 'Valuta la chiarezza del mio ragionamento tecnico')),
          _translation(normalized, 'interview.prompt.technical.3', _fallback(normalized, en: 'Give me a technical question with a follow-up', es: 'Dame una pregunta tecnica con follow-up', pt: 'Me de uma pergunta tecnica com follow-up', fr: 'Donnez-moi une question technique avec relance', de: 'Geben Sie mir eine technische Frage mit Anschlussfrage', it: 'Dammi una domanda tecnica con follow-up')),
        ];
      case InterviewPracticeMode.salary:
        return [
          _translation(normalized, 'interview.prompt.salary.1', _fallback(normalized, en: 'Let us practice answering salary expectations', es: 'Practiquemos como responder expectativa salarial', pt: 'Vamos praticar como responder expectativa salarial', fr: 'Pratiquons la reponse aux attentes salariales', de: 'Lassen Sie uns Gehaltsvorstellungen uben', it: 'Proviamo a rispondere alle aspettative salariali')),
          _translation(normalized, 'interview.prompt.salary.2', _fallback(normalized, en: 'Give me a script to negotiate without sounding aggressive', es: 'Dame un guion para negociar sin sonar agresivo', pt: 'Me de um roteiro para negociar sem soar agressivo', fr: 'Donnez-moi un script pour negocier sans paraitre agressif', de: 'Geben Sie mir ein Skript zum Verhandeln ohne aggressiv zu wirken', it: 'Dammi uno script per negoziare senza sembrare aggressivo')),
          _translation(normalized, 'interview.prompt.salary.3', _fallback(normalized, en: 'Act as recruiter and challenge my range', es: 'Haz de reclutador y cuestiona mi rango', pt: 'Atue como recrutador e questione minha faixa', fr: 'Jouez le recruteur et contestez ma fourchette', de: 'Spielen Sie den Recruiter und hinterfragen Sie meine Spanne', it: 'Fai il recruiter e metti in discussione il mio range')),
        ];
      case InterviewPracticeMode.hardQuestions:
        return [
          _translation(normalized, 'interview.prompt.hardQuestions.1', _fallback(normalized, en: 'How should I answer why I left my last job?', es: 'Como responder por que deje mi ultimo trabajo', pt: 'Como responder por que deixei meu ultimo trabalho', fr: 'Comment repondre a la question sur mon dernier depart', de: 'Wie beantworte ich, warum ich meinen letzten Job verlassen habe?', it: 'Come rispondere al motivo per cui ho lasciato il mio ultimo lavoro')),
          _translation(normalized, 'interview.prompt.hardQuestions.2', _fallback(normalized, en: 'Let us practice strengths and weaknesses', es: 'Practiquemos fortalezas y debilidades', pt: 'Vamos praticar pontos fortes e fracos', fr: 'Pratiquons les forces et faiblesses', de: 'Lassen Sie uns Starken und Schwachen uben', it: 'Proviamo punti di forza e debolezza')),
          _translation(normalized, 'interview.prompt.hardQuestions.3', _fallback(normalized, en: 'Ask me an uncomfortable question and correct my answer', es: 'Hazme una pregunta incomoda y corrige mi respuesta', pt: 'Faca-me uma pergunta desconfortavel e corrija minha resposta', fr: 'Posez-moi une question delicate et corrigez ma reponse', de: 'Stellen Sie mir eine unangenehme Frage und korrigieren Sie meine Antwort', it: 'Fammi una domanda scomoda e correggi la mia risposta')),
        ];
    }
  }

  static InterviewPracticeMode fromKey(String? key) {
    switch ((key ?? '').trim().toLowerCase()) {
      case 'star':
        return InterviewPracticeMode.star;
      case 'technical':
        return InterviewPracticeMode.technical;
      case 'salary':
        return InterviewPracticeMode.salary;
      case 'hard_questions':
        return InterviewPracticeMode.hardQuestions;
      case 'simulation':
      default:
        return InterviewPracticeMode.simulation;
    }
  }
}

const Set<String> _supportedLanguageCodes = {'en', 'es', 'pt', 'fr', 'de', 'it'};

String _modeLocalized(String languageCode, String key, String fallback) {
  return _translation(languageCode, key, fallback);
}

String _translation(String languageCode, String key, String fallback) {
  final normalized = _supportedLanguageCodes.contains(languageCode) ? languageCode : 'en';
  return trByCode(normalized, key, fallback: fallback);
}

String _fallback(
  String languageCode, {
  required String en,
  required String es,
  required String pt,
  required String fr,
  required String de,
  required String it,
}) {
  switch (_supportedLanguageCodes.contains(languageCode) ? languageCode : 'en') {
    case 'es':
      return es;
    case 'pt':
      return pt;
    case 'fr':
      return fr;
    case 'de':
      return de;
    case 'it':
      return it;
    case 'en':
    default:
      return en;
  }
}
