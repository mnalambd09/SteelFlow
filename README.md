# SteelFlow Supply

Industrial B2B sourcing storefront built with React, Vite, TypeScript, Supabase, React Router, TanStack Query, Zustand and Lucide.

## Local development

1. Install Node.js 20.19+ or 22.12+ and npm.
2. Copy `.env.example` to `.env.local` (optional for browsing the sample catalog; required for account, RFQ, private file upload and order submission).
3. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from your Supabase project. Never put the service role key in Vite variables.
4. Run `npm install`, `npm run dev` and open the local URL Vite prints.

The frontend uses the included realistic catalog sample without credentials. This mode keeps cart, wishlist and comparison in browser local storage. It does not submit RFQs, upload files, create user accounts or place orders. Those actions require a connected Supabase backend and a signed-in user. Orders start as **Pending payment** and are never presented as paid or complete based on a browser response.

## Supabase setup

1. Create a Supabase project and install the Supabase CLI (`npm install -g supabase`).
2. From this directory, run `supabase login`, `supabase link --project-ref YOUR_PROJECT_REF`, then `supabase db push` to apply `supabase/migrations/202611010001_marketplace.sql`.
3. Deploy the server-side order endpoint with `supabase functions deploy create-order`.
4. The Edge Function uses Supabase-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` secrets. Keep the service role key in Edge Function runtime only.
5. Add a user through Supabase Auth. To provision the first administrator, update that user's `profiles.role` to `admin` from the Supabase SQL editor (never expose role editing to the public frontend). Supplier accounts start pending and require admin review.
6. Enable email confirmation and configure SMTP under Supabase Auth before inviting real buyers. Configure `site_settings` row `key='checkout'` with a JSON `tax_rate` fraction only after tax rules are approved for your business.

The migration creates RLS on customer, supplier, sales and catalog tables; private `rfq-files` and `supplier-private` buckets; and a public `product-media` bucket. Product media uploads and admin operations require an authenticated admin role. Private documents are scoped to their owner and administrators. Test policies in a non-production Supabase project before inviting customers.

## Order and payment setup

The included `create-order` Edge Function calls a transaction-safe Postgres function that reads catalog prices and stock on the server, validates quantities and reserves stock atomically. Shipping is currently zero pending manual logistics review; the order stays `Pending payment`. No card charge, bank transfer confirmation, invoice PDF or payment webhook is represented as implemented. Before accepting production payments, add a payment-provider adapter and verified webhook (for example, Stripe Checkout with signature verification), then update the server order workflow and status transitions. Never mark payment successful from a return URL.

RFQs require authentication. They write the RFQ and line items to PostgreSQL and upload attached documents to the private storage bucket. Signed download links and outbound email notifications should be issued through a role-checked Edge Function when a sales workflow is added.

## Deployment

Build the static frontend with `npm run build`; deploy the `dist` directory to Vercel or another static host. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as deployment environment variables and redeploy. Deploy the database migration and Edge Function separately with the Supabase CLI. Configure the Vercel SPA rewrite so direct product and portal URLs resolve to `index.html`.

## Current scope

- Responsive home, category catalog, search, material/category/price/availability filters, sorting, pagination, product detail/specifications, compare, wishlist and recently viewed state.
- Persisted local cart and authenticated server-side order request with price/stock revalidation.
- Auth registration/sign-in, account portal, RFQ form, multiple line items, private document uploads and project details.
- Protected role-gated admin and supplier entry screens; product inventory read view and honest placeholders where workflow services still need implementation.
- Supabase schema includes companies, supplier approval, product variants, inventory, bulk tiers, orders, payments, shipments, RFQs, quotations, invoices, reviews, coupons, notifications, messages and site settings.

Payment processing, email dispatch, invoice/quotation PDF rendering, shipment integrations, supplier onboarding form, editable catalog CRUD, quotation acceptance and order conversion need additional server-side services before production use. Do not treat the current portal/dashboard preview as those workflows being live.

