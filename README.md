# I-CAR Recognition Certificates

Official Gold Class®, Gold Class® – Aluminum and Platinum™ recognition certificates, each with a confirmation letter from Scott Sinclair, for I-CAR Canada customers. A stopgap until the new i-car.ca.

**How it works:** Tanja's team uploads the current Gold Class and Platinum lists. They email or phone each customer with a personal link and log the contact in the app. The customer opens the link, confirms who they are, and downloads one PDF in English or French: page 1 is their recognition certificate, page 2 is Scott's letter. Every contact and every download is tracked.

| Page | Address |
|---|---|
| Customer page | `index.html`. Personal links pre-fill the I-CAR ID: `?program=gold_class&id=12345` (add `&lang=fr` for French) |
| Staff back end | `index.html#/admin` |

The front end is one file, `index.html`, hosted on GitHub Pages, with brand assets in `assets/`. The back end is the Supabase project **I-CAR Recognition Letters** (`fwtzwkdcxkcnscqkyxhf`, Canada Central).

## For customers

1. Open the link the team sent (or the page itself).
2. Choose Gold Class® or Platinum™. The I-CAR ID is already filled in from a personal link.
3. Confirm with one detail: the **business postal code** for Gold Class, or the **last name** for Platinum.
4. Enter your name and email, with an optional opt-in to I-CAR Canada emails, and the PDF downloads.

Ten failed attempts on one I-CAR ID lock it for an hour. Each letter carries a reference number in its footer, so a customer who calls can be matched to the log.

## For Tanja's team (`#/admin`)

- **Overview**: who hasn't been contacted yet, who has, and how many letters have been downloaded.
- **Notify customers**: pick Gold Class or Platinum and filter by *Not contacted*, *Contacted, no letter yet* or *Letter downloaded*. **Notify** opens the customer's personal link, a ready-to-send email (English or French) and a phone script. **Open in email app** starts the email in Outlook. Then **Log email sent** or **Log phone call**, with an optional note, and the full history for that customer is shown. **Download list** downloads the customers shown as a spreadsheet, with contact details and personal links (EN and FR).
- **Add one by hand** (Overview, Notify customers or Recognition lists): add a single Gold Class shop or Platinum technician without uploading a list. **Save and issue now** downloads their certificate and letter straight away, logged under your name. **Save and send them their link** opens the email and phone options. Manually added people are tagged in the list and can be edited by anyone on the team and removed by admins only. Removing a customer also deletes their issued certificates and contact history, so they drop out of the stats. If a later upload includes the same I-CAR ID, the list version takes over.
- **Issue it now** (in any customer's Notify window): **Email it with attachment** creates a ready-to-send Outlook email (an `.eml` file) to the address in **To**. It has the certificate and letter PDF attached, so open it, review and click Send, then click **I sent it. Log email sent**. **Download only** saves the PDF to email or print yourself. Both are in English or French and logged under your name.
- **Recognition lists**: upload the latest Excel or CSV export from the I-CAR system. Columns are auto-matched, with a preview. Include email and phone columns to make notifying easier. A new upload replaces the list; letters and the contact history are kept.
- **Letters issued**: search, filter, export to CSV, or re-download any letter.
- **Letter & email wording**: edit the letter text and the notification email (English and French), the signatory, the signature image and the customer contact email.
- **Team** (admins only): add people (with a temporary password), reset passwords, change roles, deactivate accounts. A person's name signs the notification emails they send.

## The certificate

Each certificate is modelled on the I-CAR recognition plaque for that level (from *ICAR-Recognition_Document_2025_ENFR*): a black frame around a brushed-silver face, with the recognition logo, *Presented to / Présenté à*, the name, *For their commitment to a high level of technical training / Attestant un engagement envers une formation technique de haut niveau*, a year plate and the I-CAR Canada logo.

| Level | Layout | Comes from the list |
|---|---|---|
| Gold Class® | Portrait, Gold Class logo, business name | Gold Class list |
| Gold Class® – Aluminum | Portrait, Aluminum logo, business name; the letter adds an Aluminum line | Gold Class list, **Aluminum** column = Yes / X / 1 |
| Platinum™ | Landscape, *Recognition / Reconnaissance*, Platinum logo, technician's name and role | Platinum list, optional **Role** column (standard roles are translated to French) |

The year plate shows the year the certificate was issued. The certificate type is set by the customer's language choice and the list. For example, an English request from an Aluminum shop gets the English Aluminum certificate and an English letter.

**Missing artwork:** the design system only has the French Gold Class Aluminium logo. Add the English file at `assets/cert/gold-class-aluminum-en.png` (transparent PNG, about 640px tall). Until then, English Aluminum certificates use the French logo.

## Branding

Built to the **I-CAR Canada design system**:
- I-CAR Blue (`#006cb4`) with navy hover and focus;
- Source Sans 3 for web type;
- the blue gradient headline box;
- the official I-CAR Canada logo, always on white;
- the language-matched Gold Class® and Platinum™ logos;
- I-CAR® / Gold Class® / Platinum™ marks as specified.

The PDF follows the letterhead rules: logo top left at 1.28in wide, the program logo top right, 1pt I-CAR Blue rules, 1in side margins and a 1.5in bottom margin. The logos and fonts in `assets/` come from the design system. Never recolour or redraw them.

## Repository layout

```
index.html                                customer page and staff back end
assets/                                   I-CAR Canada, Gold Class and Platinum logos (EN/FR); Source Sans 3 (web) and Barlow Condensed (certificate) fonts
assets/cert/                              high-resolution recognition logos for the certificates
supabase/migrations/001_schema.sql        tables, security rules, letter functions
supabase/seed.sql                         default letter wording and sign-off
supabase/migrations/002_customer_notifications.sql   outreach tracking, notification email wording, brand wording fixes
supabase/migrations/003_recognition_certificates.sql  Gold Class – Aluminum and Platinum role, certificate wording
supabase/migrations/004_manual_entries_and_staff_issue.sql  add people by hand; staff-issued certificates
supabase/functions/manage-staff/          team management (create users, reset passwords, deactivate)
samples/                                  sample Gold Class and Platinum lists for practice uploads
```

## Setup

1. **GitHub Pages**: Settings → Pages → Deploy from a branch → `main` / root. Before sending links to customers, settle on a permanent address (ideally a custom domain such as `letters.i-car.ca`), because those links will stop working if the address changes. If you use a custom domain, set `PUBLIC_URL` in the `CONFIG` block at the top of `index.html`.
2. **Supabase → Authentication → URL Configuration**: set the Site URL to the Pages address.
3. **First admin**: open `…/#/admin` and create the first account with an @aiacanada.com email (done for Brian).
4. **Lock down sign-ups**: Authentication → Sign In / Providers → turn off *Allow new users to sign up*; add everyone else from the Team tab. Turn on *Leaked password protection*.
5. **Wording**: upload Scott's signature, add the customer contact email, and get the letter wording approved.
6. **Upload the lists**, then start notifying customers.

## Rebuilding the back end

In an empty Supabase project, run these in order in the SQL editor:
1. `migrations/001_schema.sql`
2. `seed.sql`
3. `migrations/002_customer_notifications.sql`
4. `migrations/003_recognition_certificates.sql`
5. `migrations/004_manual_entries_and_staff_issue.sql`

Then deploy the function with `supabase functions deploy manage-staff --no-verify-jwt`, and update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `index.html`. The anon key is public by design; all data access is enforced by row-level security and the database functions.
