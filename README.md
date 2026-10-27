# I-CAR Gold Class Certificates

Official Gold Class® and Gold Class® – Aluminum recognition certificates for I-CAR Canada stores, each with the official confirmation letter signed by Scott Sinclair, Director, I-CAR Canada. A stopgap until the new i-car.ca.

**How it works:** each month Tanja's team uploads the *Active Gold Stores* export from the I-CAR system, as it comes. The app tidies the shop names, flags Aluminum stores and expiry dates, and shows which stores are new or renewed. The team emails or phones each store with a personal link and logs the contact. The store opens the link, confirms with its **store number** and **business postal code**, chooses English or French, and downloads one PDF: page 1 is the certificate, page 2 is the letter. Every contact and every download is tracked.

| Page | Address |
|---|---|
| Customer page | `https://certificate.aiacanada.com/`. Personal links pre-fill the store number: `?id=36950` (add `&lang=fr` for French) |
| Staff back end | `https://certificate.aiacanada.com/#/admin` |

The front end is one file, `index.html`, hosted on GitHub Pages, with brand assets in `assets/`. The back end is the Supabase project **I-CAR Recognition Letters** (`fwtzwkdcxkcnscqkyxhf`, Canada Central).

## For stores

1. Open the link the team sent (or the page itself).
2. Enter the store number (already filled in from a personal link) and the business postal code. Common typos such as the letter O for zero are forgiven.
3. Enter your name and email, choose English or French (any store, including Quebec, can choose either), with an optional opt-in to I-CAR Canada emails. The PDF downloads.

Stores whose Gold Class has expired are told so and asked to contact collisiontraining@aiacanada.com. Ten failed attempts on one store number lock it for an hour. Each letter carries a reference number in its footer.

## For Tanja's team (`#/admin`)

- **Overview**: stores on the list (and how many are Aluminum), new or renewed since the last upload, not yet contacted, certificates issued, expired.
- **Gold Class list**: upload the monthly *ICAR – Active Gold Stores* Excel file unchanged. The upload **never wipes the database**: it is checked against the stores already on file to see who is on and who is off the list. The app:
  - reads the **Current** sheet and recognises its columns (Gold Class, Number, Name, Phone, Address, City, Province, Postal Code, Expiration) automatically;
  - removes anything in brackets from shop names, except **(CarrXpert)**, which stays on; *(CarrXpert NA)* is removed. Every change is listed before you confirm;
  - marks *Gold Class – Aluminum* stores, which get the Aluminum certificate and letter;
  - brings in each store's latest expiry date; expiry is always checked against the database, and downloads stop once it has passed;
  - marks stores that are missing from the file as **off the list**. They stay on file with their history, can't download, and come back automatically if a later list includes them;
  - after the upload, shows how many stores are **new**, **renewed**, **back on the list**, **changed level** and **went off the list**, with buttons to notify them and to build the St. Joseph order.
- **St. Joseph orders**: each upload queues a **plaque** for every new store or change of level (Gold Class ↔ Aluminum) and a **year plate** for every renewal. Quebec stores get French. The team can change plaque/plate or language, remove a line, or add a store by hand from its Notify window. **Download order files** builds a zip with the same files the team used to make by hand:
  - *Mail Merge Document.xlsx*: one sheet per type (GC / GCA × Plaque / Plate × ENG / FR) with shop name, status, renewal date, system name, address, city, province, postal code;
  - *Plaque Order Gold.xlsx*: the plaques for St. Joseph to engrave (GC English/French, GC Aluminum English/French);
  - the merged letters as one PDF per type (e.g. *GC Plate Letter ENG.pdf*), one letter per page, signed by Scott Sinclair.
  Then **Mark as sent to St. Joseph** files the order under *Past orders*, where it can be downloaded again. The renewal date is the expiry date minus one year, because the export has no payment date.
- **Notify customers**: filter by *New or renewed*, *Not contacted*, *Contacted*, *Certificate issued* or *Expired*. **Notify** opens the store's personal link, a ready-to-send email (English or French) and a phone script. Log each email or call. **Download list** exports the stores shown, with phone numbers and personal links.
- **Email these stores** (Notify customers): emails every store matching the current filters (status, expiry month, search) in one go, with a level filter (Gold Class / Aluminum), language (French for Quebec, English elsewhere, or one language for all) and an option to skip stores emailed recently. It shows how many stores will be emailed and how many have no email on file, sends a test to you first, then sends each store its own email with its personal link and logs it in that store's history. Expired and off-the-list stores are never emailed. Sent through Resend by the `send-bulk-email` Edge Function.
- **Issue it now** (in any store's Notify window): **Email it with attachment** creates an Outlook email (`.eml`) with the certificate and letter attached; **Download only** saves the PDF.
- **Edit details** (any store): correct the name printed on the certificate. A corrected name is **remembered on every future upload**. Expiry date and Aluminum can also be changed until the next upload.
- **+ Add a store**: for a store not on the list yet. Admins can remove stores added by hand (this also deletes their certificates and contact history). If a later upload includes the same store number, the list version takes over.
- **Certificates issued**: search, export to CSV, or re-download any certificate.
- **Letter & email wording**: the four official letters (Gold Class EN/FR, Aluminum EN/FR), the notification email, the signatory, signature image and contact email.
- **Team** (admins only): add people, reset passwords, change roles, deactivate accounts.

The export has no email column, so the first contact is usually by phone. Add an email address with **Edit details** or type it in the Notify window.

## The certificate and letter

The certificate is modelled on the Gold Class plaque: a black frame around a brushed-silver face, the Gold Class (or Gold Class – Aluminum) logo, *Presented to / Présenté à*, the store name, *For their commitment to a high level of technical training / Attestant un engagement envers une formation technique de haut niveau*, a year plate and the I-CAR Canada logo. The year plate shows the year the current Gold Class period began (expiry date minus one year), matching "Renewal date = payment date" in the plaque instructions.

The letter follows the official templates (SharePoint › Plaques › Letter templates › Final Version): store name and address, date, "Dear …", the official text, and Scott Sinclair's sign-off, on I-CAR Canada letterhead.

**Missing artwork:** the design system only has the French *Catégorie Or Aluminium* logo. Add the English file at `assets/cert/gold-class-aluminum-en.png` (transparent PNG, about 640px tall). Until then, English Aluminum certificates use the French logo.

## Branding

Built to the **I-CAR Canada design system**: I-CAR Blue (`#006cb4`), Source Sans 3 for web type, Barlow Condensed on the certificate, the official I-CAR Canada logo always on white, language-matched Gold Class® logos. The letterhead uses the logo top left, the program logo top right, 1pt I-CAR Blue rules, 1in side margins and a 1.5in bottom margin. Never recolour or redraw the logos in `assets/`.

## Repository layout

```
index.html                                customer page and staff back end
CNAME                                     certificate.aiacanada.com
assets/                                   I-CAR Canada and Gold Class logos (EN/FR); fonts
assets/cert/                              high-resolution recognition logos for the certificate
supabase/migrations/001_schema.sql        tables, security rules, letter functions
supabase/seed.sql                         original letter wording and sign-off
supabase/migrations/002_customer_notifications.sql   outreach tracking, notification email
supabase/migrations/003_recognition_certificates.sql  Aluminum flag, certificate wording
supabase/migrations/004_manual_entries_and_staff_issue.sql  add stores by hand; staff-issued certificates
supabase/migrations/006_reconcile_list_and_plaque_orders.sql  monthly list checks on/off instead of replacing; St. Joseph orders
supabase/migrations/005_gold_class_system_export.sql  Gold Class only: system export, store number + postal code,
                                          expiry, new/renewed, name corrections, official letters, Scott Sinclair
supabase/functions/send-bulk-email/       bulk email to filtered stores (Resend)
supabase/functions/manage-staff/          team management (create users, reset passwords, deactivate)
samples/SAMPLE-Active-Gold-Stores.xlsx    made-up stores in the system export format, for practice uploads
```

## Bulk email setup (one time)

1. Create a Resend account (resend.com) and add the sending domain `aiacanada.com` (or a subdomain such as `mail.aiacanada.com`). Add the DNS records Resend shows (SPF/DKIM) and wait for it to show *Verified*.
2. Create an API key in Resend.
3. In Supabase → Edge Functions → Secrets, add `RESEND_API_KEY` (the key), `MAIL_FROM` (e.g. `I-CAR Canada <collisiontraining@aiacanada.com>`) and optionally `MAIL_REPLY_TO`.
4. In the app, open **Email these stores** and click **Send me a test**.

Store emails come from the monthly export's email column; the upload fills them in automatically.

## Setup still to finish

1. **DNS and HTTPS** for `certificate.aiacanada.com` (CNAME to `bbeehler.github.io`, then *Enforce HTTPS* in GitHub Pages).
2. **Supabase → Authentication → URL Configuration**: set the Site URL to `https://certificate.aiacanada.com`.
3. **Lock down sign-ups**: turn off *Allow new users to sign up* and turn on *Leaked password protection*. Add everyone else from the Team tab.
4. **Wording**: upload Scott's signature image.
5. **Upload the September list**, then start notifying stores.

## Rebuilding the back end

In an empty Supabase project, run `001_schema.sql`, `seed.sql`, then migrations `002` to `008` in order. Deploy the function with `supabase functions deploy manage-staff --no-verify-jwt`, and update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `index.html`. The anon key is public by design; all data access is enforced by row-level security and the database functions.
