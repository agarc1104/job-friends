import 'package:flutter/widgets.dart';

class PrivacySection {
  const PrivacySection({
    required this.title,
    required this.paragraphs,
  });

  final String title;
  final List<String> paragraphs;
}

class PrivacyContent {
  const PrivacyContent({
    required this.versionLabel,
    required this.intro,
    required this.sections,
  });

  final String versionLabel;
  final String intro;
  final List<PrivacySection> sections;
}

PrivacyContent privacyContentForLocale(Locale locale) {
  final code = locale.languageCode.toLowerCase();
  if (code == 'es') {
    return _privacyEs;
  }
  return _privacyEn;
}

const PrivacyContent _privacyEs = PrivacyContent(
  versionLabel: '2026-06-21-ai',
  intro:
      'Esta Politica de Privacidad explica como JobFriends recopila, usa, comparte y protege tus datos personales cuando utilizas la aplicacion en Estados Unidos y Canada.',
  sections: [
    PrivacySection(
      title: '1. Datos que recopilamos',
      paragraphs: [
        'Podemos recopilar datos de cuenta y contacto (correo, nombre, telefono), contenido que cargas o generas (CVs, respuestas de entrevista), datos de uso y telemetria tecnica.',
        'Tambien podemos tratar datos de ubicacion aproximada o exacta cuando habilitas funciones de busqueda de empleo por localizacion.',
      ],
    ),
    PrivacySection(
      title: '2. Finalidades del tratamiento',
      paragraphs: [
        'Usamos tus datos para operar la app, autenticarte, guardar tu progreso, ofrecer funciones de CV e entrevistas con IA, mejorar la experiencia y prevenir abuso o fraude.',
        'Cuando activas funciones de CV o entrevistas con IA, JobFriends puede transmitir prompts, respuestas, contenido curricular e instrucciones relacionadas a DeepSeek mediante APIs y servicios backend controlados para procesar la solicitud y devolverte un resultado.',
        'Tambien podemos usar datos para cumplir obligaciones legales y responder requerimientos regulatorios validos.',
      ],
    ),
    PrivacySection(
      title: '3. Bases legales y marcos aplicables',
      paragraphs: [
        'Tratamos datos bajo marcos legales aplicables en Estados Unidos y Canada, incluyendo CCPA/CPRA cuando aplique, PIPEDA y leyes provinciales aplicables (como Ley 25 de Quebec cuando corresponda).',
        'Segun la jurisdiccion, la base legal puede incluir consentimiento, ejecucion del servicio, interes legitimo y cumplimiento legal.',
      ],
    ),
    PrivacySection(
      title: '4. Comparticion de datos',
      paragraphs: [
        'Podemos compartir datos con proveedores de servicios que actuan por cuenta de JobFriends (por ejemplo, infraestructura cloud, autenticacion, analitica, almacenamiento, mensajeria y proveedores de IA como DeepSeek cuando uses funciones compatibles).',
        'No vendemos datos personales en el sentido tradicional de venta; si la ley aplicable considera alguna transferencia como sharing, habilitaremos mecanismos de derechos y exclusion cuando corresponda.',
      ],
    ),
    PrivacySection(
      title: '5. Retencion y seguridad',
      paragraphs: [
        'Conservamos datos solo durante el tiempo necesario para las finalidades descritas, obligaciones legales o resolucion de disputas.',
        'Aplicamos medidas tecnicas y organizativas razonables para proteger la informacion, aunque ningun sistema es completamente infalible.',
      ],
    ),
    PrivacySection(
      title: '6. Tus derechos de privacidad',
      paragraphs: [
        'Dependiendo de tu jurisdiccion, puedes solicitar acceso, correccion, eliminacion, portabilidad u oposicion/limitacion al tratamiento de tus datos.',
        'Tambien puedes retirar consentimiento cuando sea la base legal, sin afectar la licitud del tratamiento previo.',
      ],
    ),
    PrivacySection(
      title: '7. Menores de edad',
      paragraphs: [
        'La app no esta dirigida a menores de edad segun la ley aplicable. Si detectamos recoleccion no autorizada de datos de menores, tomaremos medidas para eliminarlos.',
      ],
    ),
    PrivacySection(
      title: '8. Transferencias internacionales',
      paragraphs: [
        'Tus datos pueden ser procesados en paises distintos al tuyo. Cuando aplique, implementamos salvaguardas contractuales y tecnicas razonables para esas transferencias.',
      ],
    ),
    PrivacySection(
      title: '9. Contacto y cambios',
      paragraphs: [
        'Podemos actualizar esta Politica de Privacidad por cambios legales o del producto. Cuando sea necesario, solicitaremos nueva aceptacion antes de continuar el uso.',
      ],
    ),
  ],
);

const PrivacyContent _privacyEn = PrivacyContent(
  versionLabel: '2026-06-21-ai',
  intro:
      'This Privacy Policy explains how JobFriends collects, uses, shares, and protects your personal data when you use the app in the United States and Canada.',
  sections: [
    PrivacySection(
      title: '1. Data we collect',
      paragraphs: [
        'We may collect account and contact data (email, name, phone), content you upload or generate (CVs, interview responses), usage data, and technical telemetry.',
        'We may also process approximate or precise location data when you enable location-based job search features.',
      ],
    ),
    PrivacySection(
      title: '2. Purposes of processing',
      paragraphs: [
        'We use data to operate the app, authenticate users, store progress, provide AI CV/interview features, improve user experience, and prevent abuse or fraud.',
        'When you activate AI CV or interview features, JobFriends may transmit prompts, responses, CV content, and related instructions to DeepSeek through controlled APIs and backend services in order to process your request and return a result.',
        'We may also process data to comply with legal obligations and valid regulatory requests.',
      ],
    ),
    PrivacySection(
      title: '3. Legal bases and applicable frameworks',
      paragraphs: [
        'We process personal data under applicable US and Canadian legal frameworks, including CCPA/CPRA where applicable, PIPEDA, and applicable provincial laws (such as Quebec Law 25 where applicable).',
        'Depending on jurisdiction, legal bases may include consent, service performance, legitimate interests, and legal compliance.',
      ],
    ),
    PrivacySection(
      title: '4. Data sharing',
      paragraphs: [
        'We may share data with service providers acting on JobFriends behalf (for example, cloud infrastructure, authentication, analytics, storage, messaging, and AI providers such as DeepSeek when you use supported features).',
        'We do not sell personal information in the traditional sense; where applicable law treats certain transfers as sharing, we provide rights mechanisms and opt-out options when required.',
      ],
    ),
    PrivacySection(
      title: '5. Retention and security',
      paragraphs: [
        'We retain data only as long as needed for the purposes described, legal obligations, or dispute resolution.',
        'We apply reasonable technical and organizational safeguards, but no system can be fully secure in all circumstances.',
      ],
    ),
    PrivacySection(
      title: '6. Your privacy rights',
      paragraphs: [
        'Depending on your jurisdiction, you may request access, correction, deletion, portability, or objection/restriction regarding processing of your data.',
        'You may also withdraw consent when consent is the legal basis, without affecting processing performed before withdrawal.',
      ],
    ),
    PrivacySection(
      title: '7. Children privacy',
      paragraphs: [
        'The app is not directed to children under the age required by applicable law. If unauthorized collection is identified, we will take steps to delete that data.',
      ],
    ),
    PrivacySection(
      title: '8. International transfers',
      paragraphs: [
        'Your data may be processed in countries other than your own. Where required, we implement reasonable contractual and technical safeguards for such transfers.',
      ],
    ),
    PrivacySection(
      title: '9. Contact and updates',
      paragraphs: [
        'We may update this Privacy Policy due to legal or product changes. When required, we will request renewed acceptance before continued use.',
      ],
    ),
  ],
);
