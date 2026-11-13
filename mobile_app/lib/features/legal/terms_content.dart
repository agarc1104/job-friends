import 'package:flutter/widgets.dart';

class TermsSection {
  const TermsSection({
    required this.title,
    required this.paragraphs,
  });

  final String title;
  final List<String> paragraphs;
}

class TermsContent {
  const TermsContent({
    required this.versionLabel,
    required this.intro,
    required this.sections,
  });

  final String versionLabel;
  final String intro;
  final List<TermsSection> sections;
}

TermsContent termsContentForLocale(Locale locale) {
  final code = locale.languageCode.toLowerCase();
  if (code == 'es') {
    return _termsEs;
  }
  return _termsEn;
}

const TermsContent _termsEs = TermsContent(
  versionLabel: '2026-06-21-ai',
  intro:
      'Estos Terminos y Condiciones regulan el acceso y uso de JobFriends en Estados Unidos y Canada. Al usar la aplicacion aceptas este acuerdo, junto con la Politica de Privacidad aplicable.',
  sections: [
    TermsSection(
      title: '1. Aceptacion y elegibilidad',
      paragraphs: [
        'Debes tener capacidad legal para contratar en tu jurisdiccion. Si usas la app en nombre de una organizacion, declaras que tienes autorizacion para obligarla legalmente.',
        'El uso de JobFriends implica consentimiento expreso para el tratamiento de datos descrito en estos terminos y en la Politica de Privacidad.',
      ],
    ),
    TermsSection(
      title: '2. Servicios ofrecidos',
      paragraphs: [
        'JobFriends ofrece herramientas para busqueda de empleo, gestion de candidaturas, preparacion de CV y simulacion de entrevistas asistidas por IA.',
        'Las funciones de creacion o adaptacion de CVs y de simulacion de entrevistas pueden operar mediante modelos de IA ofrecidos a traves de la API de DeepSeek, integrados por medio de servicios backend y Edge Functions controlados por JobFriends.',
        'No garantizamos contratacion, entrevistas reales, ofertas de trabajo ni resultados especificos.',
      ],
    ),
    TermsSection(
      title: '3. Cuenta y seguridad',
      paragraphs: [
        'Eres responsable de la veracidad de tu informacion, de mantener la confidencialidad de tus credenciales y de toda actividad realizada desde tu cuenta.',
        'Debes notificarnos de inmediato cualquier acceso no autorizado o vulneracion de seguridad detectada.',
      ],
    ),
    TermsSection(
      title: '4. Datos personales y privacidad (EE. UU. y Canada)',
      paragraphs: [
        'Tratamos datos personales conforme a la legislacion aplicable, incluyendo marcos de privacidad en Estados Unidos (incluyendo leyes estatales aplicables como CCPA/CPRA cuando correspondan) y Canada (incluyendo PIPEDA y leyes provinciales aplicables, como Ley 25 de Quebec cuando corresponda).',
        'Puedes ejercer derechos de acceso, correccion, supresion y otros derechos de privacidad de acuerdo con tu jurisdiccion y nuestra Politica de Privacidad.',
        'Podemos utilizar proveedores tecnologicos para operar el servicio (por ejemplo, autenticacion, analitica, alojamiento, mensajeria y procesamiento de IA), bajo obligaciones contractuales de confidencialidad y seguridad razonables.',
        'Cuando uses funciones de CV o entrevistas asistidas por IA, ciertos prompts, instrucciones y contenido aportado por ti pueden ser enviados de forma controlada a DeepSeek o a la infraestructura tecnica necesaria para generar respuestas.',
      ],
    ),
    TermsSection(
      title: '5. Contenido del usuario y CVs',
      paragraphs: [
        'Tu mantienes la titularidad y responsabilidad total sobre la informacion, documentos y CVs que cargues, generes, edites o compartas mediante la app.',
        'Eres el unico responsable de asegurar que tu CV y cualquier documento cumplan la ley, no infrinjan derechos de terceros y no incluyan informacion falsa, enganosa o no autorizada.',
        'JobFriends actua como proveedor de herramientas y no asume responsabilidad editorial ni legal por el contenido de CVs, cartas, respuestas de entrevista o cualquier documento creado por el usuario.',
      ],
    ),
    TermsSection(
      title: '6. Propiedad intelectual',
      paragraphs: [
        'La app, su software, marca, diseno, estructura, interfaces y contenido propio son propiedad de JobFriends o de sus licenciantes y estan protegidos por leyes de propiedad intelectual.',
        'Se concede una licencia limitada, no exclusiva, revocable e intransferible para uso personal o interno de negocio, segun corresponda, sin derecho a reventa, sublicencia ni ingenieria inversa salvo permiso legal expreso.',
      ],
    ),
    TermsSection(
      title: '7. Uso aceptable',
      paragraphs: [
        'No puedes usar la app para actividades ilegales, discriminatorias, fraudulentas, de scraping no autorizado, ni para introducir malware o afectar la disponibilidad del servicio.',
        'Nos reservamos el derecho de suspender cuentas o limitar acceso cuando exista riesgo legal, tecnico o de seguridad.',
      ],
    ),
    TermsSection(
      title: '8. IA y descargos de responsabilidad',
      paragraphs: [
        'Las sugerencias de IA son orientativas y pueden contener errores, sesgos o imprecisiones. Debes revisar y validar cualquier contenido antes de usarlo profesionalmente.',
        'Salvo que se indique expresamente otra cosa en una version futura del servicio, JobFriends utiliza la API de DeepSeek como motor de IA para determinadas funciones de CV y entrevistas, sin garantizar disponibilidad continua, exactitud, compatibilidad con un puesto especifico ni ausencia de resultados sesgados o incompletos.',
        'JobFriends no presta asesoria legal, migratoria, laboral, financiera ni profesional certificada.',
      ],
    ),
    TermsSection(
      title: '9. Limitacion de responsabilidad',
      paragraphs: [
        'En la medida permitida por ley, JobFriends no sera responsable por danos indirectos, incidentales, especiales, punitivos o consecuenciales, ni por perdida de ingresos, datos u oportunidades.',
        'La responsabilidad total acumulada de JobFriends, cuando aplique legalmente, se limitara al mayor entre el monto pagado por ti en los 12 meses previos (si existiera) y el minimo exigido por la ley aplicable.',
      ],
    ),
    TermsSection(
      title: '10. Indemnizacion',
      paragraphs: [
        'Aceptas defender, indemnizar y mantener indemne a JobFriends ante reclamaciones de terceros derivadas de tu contenido, uso indebido del servicio o incumplimiento de estos terminos.',
      ],
    ),
    TermsSection(
      title: '11. Terminacion',
      paragraphs: [
        'Puedes dejar de usar la app en cualquier momento. Podemos suspender o terminar acceso por incumplimiento legal, contractual o por riesgo de seguridad.',
        'Las clausulas que por su naturaleza deban sobrevivir a la terminacion seguiran vigentes (incluyendo propiedad intelectual, limitaciones de responsabilidad e indemnizacion).',
      ],
    ),
    TermsSection(
      title: '12. Ley aplicable y jurisdiccion',
      paragraphs: [
        'Estos terminos se interpretaran conforme a la ley aplicable indicada en la Politica de Privacidad o en acuerdos comerciales especificos, sin perjuicio de derechos irrenunciables del consumidor cuando existan.',
        'Cuando la ley lo permita, las disputas se resolveran en la jurisdiccion competente designada por JobFriends, salvo disposicion obligatoria en contrario.',
      ],
    ),
    TermsSection(
      title: '13. Cambios a estos terminos',
      paragraphs: [
        'Podemos actualizar estos terminos por cambios legales, regulatorios o funcionales. Cuando el cambio sea material, solicitaremos nueva aceptacion antes de continuar usando la app.',
      ],
    ),
  ],
);

const TermsContent _termsEn = TermsContent(
  versionLabel: '2026-06-21-ai',
  intro:
      'These Terms and Conditions govern access to and use of JobFriends in the United States and Canada. By using the app, you agree to this agreement and the applicable Privacy Policy.',
  sections: [
    TermsSection(
      title: '1. Acceptance and eligibility',
      paragraphs: [
        'You must have legal capacity to enter into a binding contract in your jurisdiction. If you use the app on behalf of an organization, you represent that you are authorized to bind that organization.',
        'Using JobFriends requires your express consent to the data processing described in these terms and in the Privacy Policy.',
      ],
    ),
    TermsSection(
      title: '2. Services provided',
      paragraphs: [
        'JobFriends provides tools for job search, application tracking, CV preparation, and AI-assisted interview practice.',
        'CV creation or adaptation features and interview simulation features may operate through AI models made available via the DeepSeek API, integrated through backend services and Edge Functions controlled by JobFriends.',
        'We do not guarantee hiring outcomes, real interviews, offers, or any specific result.',
      ],
    ),
    TermsSection(
      title: '3. Account and security',
      paragraphs: [
        'You are responsible for the accuracy of your information, keeping credentials confidential, and all activities performed under your account.',
        'You must notify us promptly of any unauthorized access or security breach affecting your account.',
      ],
    ),
    TermsSection(
      title: '4. Personal data and privacy (US and Canada)',
      paragraphs: [
        'We process personal data under applicable laws, including US privacy frameworks (including applicable state laws such as CCPA/CPRA where applicable) and Canadian frameworks (including PIPEDA and applicable provincial laws, such as Quebec Law 25 where applicable).',
        'You may exercise access, correction, deletion, and other privacy rights according to your jurisdiction and our Privacy Policy.',
        'We may use technology providers to operate the service (for example, authentication, analytics, hosting, messaging, and AI processing) under contractual confidentiality and reasonable security obligations.',
        'When you use AI-assisted CV or interview features, certain prompts, instructions, and content provided by you may be sent in a controlled manner to DeepSeek or to the technical infrastructure required to generate responses.',
      ],
    ),
    TermsSection(
      title: '5. User content and CV documents',
      paragraphs: [
        'You retain ownership of and full responsibility for the information, files, and CV documents that you upload, generate, edit, or share through the app.',
        'You are solely responsible for ensuring your CV and any document complies with the law, does not infringe third-party rights, and does not include false, misleading, or unauthorized information.',
        'JobFriends acts as a tools provider and assumes no editorial or legal responsibility for CVs, cover letters, interview answers, or any user-created documents.',
      ],
    ),
    TermsSection(
      title: '6. Intellectual property',
      paragraphs: [
        'The app, software, brand, design, structure, interfaces, and original content are owned by JobFriends or its licensors and are protected by intellectual property laws.',
        'A limited, non-exclusive, revocable, non-transferable license is granted for personal or internal business use, as applicable, without rights to resale, sublicense, or reverse engineering unless expressly permitted by law.',
      ],
    ),
    TermsSection(
      title: '7. Acceptable use',
      paragraphs: [
        'You may not use the app for unlawful, discriminatory, fraudulent, unauthorized scraping activities, malware distribution, or service disruption.',
        'We reserve the right to suspend accounts or limit access where legal, technical, or security risk exists.',
      ],
    ),
    TermsSection(
      title: '8. AI output and disclaimers',
      paragraphs: [
        'AI suggestions are informational and may include errors, bias, or inaccuracies. You must review and validate any generated content before professional use.',
        'Unless expressly stated otherwise in a future version of the service, JobFriends uses the DeepSeek API as the AI engine for certain CV and interview features, without guaranteeing continuous availability, accuracy, job-specific fitness, or the absence of biased or incomplete results.',
        'JobFriends does not provide legal, immigration, employment, financial, or licensed professional advice.',
      ],
    ),
    TermsSection(
      title: '9. Limitation of liability',
      paragraphs: [
        'To the maximum extent permitted by law, JobFriends is not liable for indirect, incidental, special, punitive, or consequential damages, or for loss of revenue, data, or opportunities.',
        'Where legally applicable, JobFriends total cumulative liability will be limited to the greater of the amount you paid in the prior 12 months (if any) and the minimum required by applicable law.',
      ],
    ),
    TermsSection(
      title: '10. Indemnification',
      paragraphs: [
        'You agree to defend, indemnify, and hold JobFriends harmless from third-party claims arising out of your content, misuse of the service, or breach of these terms.',
      ],
    ),
    TermsSection(
      title: '11. Termination',
      paragraphs: [
        'You may stop using the app at any time. We may suspend or terminate access for legal or contractual breaches or security risk.',
        'Clauses that should survive termination by nature will remain in effect, including intellectual property, limitations of liability, and indemnification.',
      ],
    ),
    TermsSection(
      title: '12. Governing law and venue',
      paragraphs: [
        'These terms will be interpreted under the applicable law identified in the Privacy Policy or in specific commercial agreements, without prejudice to non-waivable consumer rights where applicable.',
        'Where permitted by law, disputes will be resolved in the competent venue designated by JobFriends, unless mandatory law provides otherwise.',
      ],
    ),
    TermsSection(
      title: '13. Changes to these terms',
      paragraphs: [
        'We may update these terms due to legal, regulatory, or product changes. When changes are material, we will require renewed acceptance before continued app use.',
      ],
    ),
  ],
);
