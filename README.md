# I-CAR Recognition Letters

Self-serve recognition letters for I-CAR Canada. Gold Class businesses and Platinum individuals download an official, bilingual PDF letter with a QR verification code. Tanja's team manages the recognition lists, letter wording, team access and the log of every letter issued.

| Page | Address |
|---|---|
| Customer page | `index.html` (pre-fill with `?program=gold_class&id=12345&lang=fr`) |
| Letter verification | `index.html#/verify` (the QR code on each letter opens `#/verify/CODE`) |
| Staff back end | `index.html#/admin` |

The whole front end is one file, `index.html`, hosted on GitHub Pages. The back end is the Supabase project **I-CAR Recognition Letters** (`fwtzwkdcxkcnscqkyxhf`, Canada Central).

## How it works

**Customers** choose Gold Class or Platinum and enter their I-CAR ID plus one check detail: the business postal code for Gold Class, or their last name for Platinum. They also give their name and email, with an optional email opt-in. On a match, the PDF is generated in their browser and downloaded. Ten failed attempts on one I-CAR ID lock it for an hour.

**Every letter is logged** (who, when, which recognition, the requester's email, opt-in, language) with a unique verification code. Anyone can check a code on the verification page, which also shows whether the recognition is still on the current list.

**Staff** sign in at `#/admin`:
- **Recognition lists**: upload the latest Excel or CSV export from the I-CAR system. Columns are auto-matched, with a preview before you replace the list.
- **Letters issued**: search, filter, export to CSV, or re-download any letter.
- **Letter design**: edit the wording (English and French), logo, signature, signatory and contact email.
- **Customer launch kit**: links, an i-car.ca button and announcement copy.
- **Team** (admins only): add people with a temporary password, reset passwords, change roles, deactivate accounts.

## Repository layout

```
index.html                         the app (customer page, verification, staff back end)
supabase/schema.sql                complete database setup (tables, security rules, functions)
supabase/seed.sql                  default letter wording
supabase/functions/manage-staff/   team-management function (create users, reset passwords, deactivate)
samples/                           sample Gold Class and Platinum lists for practice uploads
```

## First-time setup

1. **GitHub Pages**: Settings → Pages → Deploy from branch → `main` / root. Use a permanent address (ideally a custom domain such as `letters.i-car.ca`). The address is printed in every QR code, so it shouldn't change after launch. If you use a custom domain, set `PUBLIC_URL` in the `CONFIG` block at the top of `index.html`.
2. **Supabase Auth → URL Configuration**: set the Site URL to the Pages address.
3. **First admin**: open `…/index.html#/admin` and create the first account with an @aiacanada.com email. Confirm the email, then sign in.
4. **Lock down sign-ups**: Supabase → Authentication → Sign In / Providers → turn off *Allow new users to sign up*. All further accounts are created from the Team tab. Also turn on *Leaked password protection*.
5. **Letter design**: upload the I-CAR logo and Scott's signature, add the customer contact email, and get the wording approved.
6. **Upload the lists**: Gold Class and Platinum exports from the I-CAR system.

## Rebuilding the back end

In a new Supabase project, run `supabase/schema.sql` then `supabase/seed.sql` in the SQL editor. Deploy the function with `supabase functions deploy manage-staff --no-verify-jwt`. Then update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `index.html`. The anon key is public by design; all data access is enforced by row-level security and the database functions.
