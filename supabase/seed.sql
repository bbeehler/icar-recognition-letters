-- Default letter wording and branding (edit later in the app under Letter design)
insert into public.letter_settings (id, org_name, signatory_name, signatory_title_en, signatory_title_fr, footer_text)
values (1, $t$I-CAR Canada$t$, $t$Scott Sinclair$t$, $t$Director, I-CAR Canada$t$, $t$Directeur, I-CAR Canada$t$, $t$I-CAR Canada  |  i-car.ca$t$);

insert into public.letter_templates (program, language, heading, body) values
('gold_class', 'en', $t$Confirmation of I-CAR Gold Class® Recognition$t$,
$t$To whom it may concern,

This letter confirms that {{name}} (I-CAR ID: {{icar_id}}) is recognized as an I-CAR Gold Class® business as of the date of this letter.

Gold Class is the collision repair industry's highest role-relevant training recognition for businesses. It is earned by shops whose technicians have completed role-relevant training in current repair information, technologies and techniques, and it is maintained through ongoing annual training.

By achieving Gold Class, {{name}} has demonstrated its commitment to complete, safe and quality repairs for every customer.

This letter reflects recognition status on its date of issue. Current status can be confirmed at any time using the verification code or QR code below.

Sincerely,$t$),
('gold_class', 'fr', $t$Confirmation de la reconnaissance Gold Class® d'I-CAR$t$,
$t$À qui de droit,

La présente confirme que {{name}} (numéro I-CAR : {{icar_id}}) est reconnue comme entreprise Gold Class® d'I-CAR en date de la présente lettre.

La reconnaissance Gold Class est la plus haute reconnaissance de formation axée sur les rôles accordée aux entreprises de l'industrie de la réparation de carrosserie. Elle est obtenue par les ateliers dont les techniciens ont suivi une formation axée sur leurs rôles portant sur l'information, les technologies et les techniques de réparation actuelles, et elle est maintenue grâce à une formation annuelle continue.

En obtenant la reconnaissance Gold Class, {{name}} démontre son engagement envers des réparations complètes, sécuritaires et de qualité pour chaque client.

Cette lettre reflète le statut de reconnaissance à sa date d'émission. Le statut actuel peut être confirmé en tout temps à l'aide du code de vérification ou du code QR ci-dessous.

Veuillez agréer nos salutations distinguées,$t$),
('platinum', 'en', $t$Confirmation of I-CAR Platinum™ Recognition$t$,
$t$To whom it may concern,

This letter confirms that {{name}} (I-CAR ID: {{icar_id}}) holds I-CAR Platinum™ recognition as of the date of this letter.

Platinum is I-CAR's recognition for individuals who have completed the role-relevant training required for their position in the collision repair industry and who maintain it through ongoing annual training.

By achieving Platinum, {{name}} has demonstrated a commitment to the knowledge and skills needed for complete, safe and quality repairs.

This letter reflects recognition status on its date of issue. Current status can be confirmed at any time using the verification code or QR code below.

Sincerely,$t$),
('platinum', 'fr', $t$Confirmation de la reconnaissance Platinum™ d'I-CAR$t$,
$t$À qui de droit,

La présente confirme que {{name}} (numéro I-CAR : {{icar_id}}) détient la reconnaissance Platinum™ d'I-CAR en date de la présente lettre.

La reconnaissance Platinum est accordée par I-CAR aux personnes qui ont suivi la formation axée sur les rôles requise pour leur poste dans l'industrie de la réparation de carrosserie et qui la maintiennent grâce à une formation annuelle continue.

En obtenant la reconnaissance Platinum, {{name}} démontre son engagement à acquérir les connaissances et les compétences nécessaires à des réparations complètes, sécuritaires et de qualité.

Cette lettre reflète le statut de reconnaissance à sa date d'émission. Le statut actuel peut être confirmé en tout temps à l'aide du code de vérification ou du code QR ci-dessous.

Veuillez agréer nos salutations distinguées,$t$);
