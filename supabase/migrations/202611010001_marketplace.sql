-- SteelFlow Supply marketplace schema. Apply in Supabase SQL editor or with `supabase db push`.
create extension if not exists pgcrypto;
create type public.account_role as enum ('customer','supplier','admin');
create type public.rfq_status as enum ('Draft','Submitted','Under Review','Quotation Prepared','Sent to Customer','Accepted','Rejected','Converted to Order');
create type public.order_status as enum ('Pending payment','Payment verification','Processing','Partially shipped','Shipped','Delivered','Cancelled','Refunded');
create type public.supplier_status as enum ('pending','approved','rejected','suspended');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', email text not null default '', phone text,
 account_type text not null default 'Individual Buyer' check(account_type in ('Individual Buyer','Contractor','Wholesale Buyer','Company / Procurement Team')),
 role public.account_role not null default 'customer', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.companies(id uuid primary key default gen_random_uuid(),name text not null,legal_name text,tax_id text,website text,account_type text,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table public.company_members(company_id uuid not null references public.companies(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,member_role text not null default 'buyer' check(member_role in ('owner','admin','buyer','approver')),created_at timestamptz not null default now(),primary key(company_id,user_id));
create table public.suppliers(id uuid primary key default gen_random_uuid(),user_id uuid not null unique references public.profiles(id),company_name text not null,legal_name text,website text,country text,status public.supplier_status not null default 'pending',reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,created_at timestamptz not null default now());
create table public.supplier_documents(id uuid primary key default gen_random_uuid(),supplier_id uuid not null references public.suppliers(id) on delete cascade,storage_path text not null,file_name text not null,document_type text,created_at timestamptz not null default now());
create table public.categories(id uuid primary key default gen_random_uuid(),name text not null unique,slug text not null unique,parent_id uuid references public.categories(id),description text,sort_order int not null default 0,active boolean not null default true);
create table public.brands(id uuid primary key default gen_random_uuid(),name text not null unique,slug text not null unique,website text,description text);
create table public.products(id uuid primary key default gen_random_uuid(),supplier_id uuid references public.suppliers(id),category_id uuid not null references public.categories(id),brand_id uuid references public.brands(id),name text not null,slug text not null unique,sku text not null unique,description text not null default '',material text,price numeric(14,2) not null check(price>=0),currency char(3) not null default 'USD',unit text not null default 'ea',moq integer not null default 1 check(moq>0),status text not null default 'draft' check(status in ('draft','active','archived')),origin_country text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index products_category_status_idx on public.products(category_id,status);create index products_material_idx on public.products(material);create index products_brand_idx on public.products(brand_id);create index products_name_trgm_idx on public.products using gin(to_tsvector('english',name||' '||sku||' '||coalesce(material,'')));
create table public.product_images(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,storage_path text not null,alt_text text,sort_order int not null default 0,is_primary boolean not null default false);
create table public.product_specifications(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,name text not null,value text not null,unit text,unique(product_id,name));
create table public.product_variants(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,sku text not null unique,attributes jsonb not null default '{}',price numeric(14,2) not null check(price>=0),moq integer not null default 1 check(moq>0),active boolean not null default true);
create table public.inventory(product_id uuid primary key references public.products(id) on delete cascade,quantity integer not null default 0 check(quantity>=0),reserved integer not null default 0 check(reserved>=0 and reserved<=quantity),reorder_point integer not null default 0 check(reorder_point>=0),updated_at timestamptz not null default now());
create table public.bulk_price_tiers(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,min_quantity integer not null check(min_quantity>0),unit_price numeric(14,2) not null check(unit_price>=0),currency char(3) not null default 'USD',unique(product_id,min_quantity));
create table public.carts(id uuid primary key default gen_random_uuid(),user_id uuid not null unique references public.profiles(id) on delete cascade,updated_at timestamptz not null default now());
create table public.cart_items(id uuid primary key default gen_random_uuid(),cart_id uuid not null references public.carts(id) on delete cascade,product_id uuid not null references public.products(id),variant_id uuid references public.product_variants(id),quantity integer not null check(quantity>0),created_at timestamptz not null default now(),unique(cart_id,product_id,variant_id));
create table public.wishlists(user_id uuid not null references public.profiles(id) on delete cascade,product_id uuid not null references public.products(id) on delete cascade,created_at timestamptz not null default now(),primary key(user_id,product_id));
create table public.orders(id uuid primary key default gen_random_uuid(),order_number bigint generated always as identity unique,user_id uuid not null references public.profiles(id),company_id uuid references public.companies(id),status public.order_status not null default 'Pending payment',currency char(3) not null default 'USD',subtotal numeric(14,2) not null check(subtotal>=0),shipping_total numeric(14,2) not null default 0 check(shipping_total>=0),tax_total numeric(14,2) not null default 0 check(tax_total>=0),total numeric(14,2) not null check(total>=0),shipping_address jsonb not null,billing_address jsonb,customer_note text,created_at timestamptz not null default now());
create index orders_user_created_idx on public.orders(user_id,created_at desc);
create table public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,product_id uuid not null references public.products(id),variant_id uuid references public.product_variants(id),sku_snapshot text not null,name_snapshot text not null,quantity integer not null check(quantity>0),unit_price numeric(14,2) not null check(unit_price>=0),line_total numeric(14,2) not null check(line_total>=0),specifications_snapshot jsonb not null default '{}');
create table public.payments(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),provider text not null,status text not null check(status in ('pending','requires_action','succeeded','failed','refunded')),provider_reference text,amount numeric(14,2) not null check(amount>=0),currency char(3) not null default 'USD',verified_at timestamptz,created_at timestamptz not null default now());
create table public.shipments(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),carrier text,tracking_number text,status text not null default 'pending',estimated_delivery date,shipped_at timestamptz,created_at timestamptz not null default now());
create table public.rfqs(id uuid primary key default gen_random_uuid(),rfq_number bigint generated always as identity unique,user_id uuid not null references public.profiles(id),company_id uuid references public.companies(id),status public.rfq_status not null default 'Submitted',project_name text,delivery_date date,delivery_city text,order_range text,contact_name text,email text not null,company text,phone text,notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index rfqs_user_created_idx on public.rfqs(user_id,created_at desc);
create table public.rfq_items(id uuid primary key default gen_random_uuid(),rfq_id uuid not null references public.rfqs(id) on delete cascade,product_id uuid references public.products(id),description text,quantity integer not null check(quantity>0),size text,grade text,specifications jsonb not null default '{}');
create table public.rfq_files(id uuid primary key default gen_random_uuid(),rfq_id uuid not null references public.rfqs(id) on delete cascade,storage_path text not null,file_name text not null,mime_type text,size_bytes bigint check(size_bytes between 0 and 20971520),created_at timestamptz not null default now());
create table public.quotations(id uuid primary key default gen_random_uuid(),rfq_id uuid not null references public.rfqs(id),version integer not null default 1,prepared_by uuid references public.profiles(id),status text not null default 'draft' check(status in ('draft','sent','accepted','rejected','expired')),currency char(3) not null default 'USD',shipping_total numeric(14,2) not null default 0,tax_total numeric(14,2) not null default 0,expires_at timestamptz,terms text,created_at timestamptz not null default now(),unique(rfq_id,version));
create table public.quotation_items(id uuid primary key default gen_random_uuid(),quotation_id uuid not null references public.quotations(id) on delete cascade,rfq_item_id uuid references public.rfq_items(id),product_id uuid references public.products(id),description text not null,quantity integer not null check(quantity>0),unit_price numeric(14,2) not null check(unit_price>=0),line_total numeric(14,2) generated always as (quantity*unit_price) stored);
create table public.invoices(id uuid primary key default gen_random_uuid(),order_id uuid not null unique references public.orders(id),invoice_number text not null unique,storage_path text,status text not null default 'issued',issued_at timestamptz not null default now(),due_at date);
create table public.reviews(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),user_id uuid not null references public.profiles(id),order_id uuid references public.orders(id),rating integer not null check(rating between 1 and 5),title text,body text,approved boolean not null default false,created_at timestamptz not null default now(),unique(product_id,user_id,order_id));
create table public.coupons(id uuid primary key default gen_random_uuid(),code text not null unique,discount_type text not null check(discount_type in ('percent','fixed')),discount_value numeric(12,2) not null check(discount_value>0),currency char(3) default 'USD',min_subtotal numeric(14,2) not null default 0,starts_at timestamptz,expires_at timestamptz,max_uses integer,uses integer not null default 0,active boolean not null default true);
create table public.notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,title text not null,body text not null,kind text not null,read_at timestamptz,created_at timestamptz not null default now());
create table public.messages(id uuid primary key default gen_random_uuid(),sender_id uuid not null references public.profiles(id),recipient_id uuid not null references public.profiles(id),rfq_id uuid references public.rfqs(id),order_id uuid references public.orders(id),body text not null,created_at timestamptz not null default now());
create table public.site_settings(key text primary key,value jsonb not null,updated_at timestamptz not null default now());

-- Invoked only by the authenticated create-order Edge Function; all price/stock values are read server-side.
create or replace function public.create_order_secure(p_user_id uuid,p_items jsonb,p_shipping_address jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_order uuid:=gen_random_uuid();v_subtotal numeric(14,2):=0;v_line record;v_unit numeric(14,2);v_available integer;v_qty integer;v_rate numeric(8,5):=0;v_tax numeric(14,2):=0;v_currency char(3):='USD';v_sku text;v_name text;
begin
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Order must include at least one item'; end if;
 for v_line in select value from jsonb_array_elements(p_items) loop
  v_qty:=(v_line.value->>'quantity')::integer;
  if v_qty<1 or v_qty>100000 then raise exception 'Invalid quantity'; end if;
  select p.price,p.currency,coalesce(i.quantity-i.reserved,0) into v_unit,v_currency,v_available from products p join inventory i on i.product_id=p.id where p.id=(v_line.value->>'product_id')::uuid and p.status='active' for update of p,i;
  if not found then raise exception 'Product is unavailable'; end if;
  -- Re-read the requested quantity separately; never accept a unit price from the browser.
  v_qty:=(v_line.value->>'quantity')::integer;
  if v_qty<(select moq from products where id=(v_line.value->>'product_id')::uuid) then raise exception 'Quantity is below minimum order quantity'; end if;
  if v_available<v_qty then raise exception 'Insufficient available stock'; end if;
  v_subtotal:=v_subtotal+(v_unit*v_qty);
 end loop;
 if jsonb_typeof(p_shipping_address)<>'object' or p_shipping_address='{}'::jsonb then raise exception 'A shipping address is required'; end if;
 select coalesce((select (value->>'tax_rate')::numeric from site_settings where key='checkout'),0) into v_rate;
 v_tax:=round(v_subtotal*v_rate,2);
 insert into orders(id,user_id,status,currency,subtotal,shipping_total,tax_total,total,shipping_address) values(v_order,p_user_id,'Pending payment',v_currency,v_subtotal,0,v_tax,v_subtotal+v_tax,p_shipping_address);
 for v_line in select value from jsonb_array_elements(p_items) loop
  v_qty:=(v_line.value->>'quantity')::integer;
  select p.price,p.sku,p.name into v_unit,v_sku,v_name from products p where p.id=(v_line.value->>'product_id')::uuid;
  insert into order_items(order_id,product_id,sku_snapshot,name_snapshot,quantity,unit_price,line_total) values(v_order,(v_line.value->>'product_id')::uuid,v_sku,v_name,v_qty,v_unit,v_unit*v_qty);
  update inventory set reserved=reserved+v_qty,updated_at=now() where product_id=(v_line.value->>'product_id')::uuid;
 end loop;
 return v_order;
end $$;
revoke all on function public.create_order_secure(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.create_order_secure(uuid,jsonb,jsonb) to service_role;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;
create or replace function public.is_approved_supplier() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from suppliers where user_id=auth.uid() and status='approved') $$;
create or replace function public.prevent_role_escalation() returns trigger language plpgsql security definer set search_path=public as $$ begin if new.role is distinct from old.role and not public.is_admin() then raise exception 'Only an administrator may change account roles'; end if; return new; end $$;
create trigger profiles_role_guard before update of role on public.profiles for each row execute function public.prevent_role_escalation();
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,email,full_name,account_type) values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.raw_user_meta_data->>'account_type','Individual Buyer')); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;alter table public.companies enable row level security;alter table public.company_members enable row level security;alter table public.suppliers enable row level security;alter table public.supplier_documents enable row level security;alter table public.categories enable row level security;alter table public.brands enable row level security;alter table public.products enable row level security;alter table public.product_images enable row level security;alter table public.product_specifications enable row level security;alter table public.product_variants enable row level security;alter table public.inventory enable row level security;alter table public.bulk_price_tiers enable row level security;alter table public.carts enable row level security;alter table public.cart_items enable row level security;alter table public.wishlists enable row level security;alter table public.orders enable row level security;alter table public.order_items enable row level security;alter table public.payments enable row level security;alter table public.shipments enable row level security;alter table public.rfqs enable row level security;alter table public.rfq_items enable row level security;alter table public.rfq_files enable row level security;alter table public.quotations enable row level security;alter table public.quotation_items enable row level security;alter table public.invoices enable row level security;alter table public.reviews enable row level security;alter table public.coupons enable row level security;alter table public.notifications enable row level security;alter table public.messages enable row level security;alter table public.site_settings enable row level security;

create policy "Profiles readable by owner or admin" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy "Profiles update by owner or admin" on public.profiles for update to authenticated using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());
create policy "Supplier reads own application" on public.suppliers for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "Buyer applies as supplier" on public.suppliers for insert to authenticated with check(user_id=auth.uid() and status='pending');
create policy "Admin reviews suppliers" on public.suppliers for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Supplier documents owner access" on public.supplier_documents for select to authenticated using(supplier_id in(select id from suppliers where user_id=auth.uid()) or public.is_admin());
create policy "Supplier uploads own documents" on public.supplier_documents for insert to authenticated with check(supplier_id in(select id from suppliers where user_id=auth.uid()));
create policy "Admin manages supplier documents" on public.supplier_documents for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public active categories" on public.categories for select to anon,authenticated using(active or public.is_admin());
create policy "Admin manages categories" on public.categories for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public brands" on public.brands for select to anon,authenticated using(true);
create policy "Admin manages brands" on public.brands for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public active products" on public.products for select to anon,authenticated using(status='active' and (supplier_id is null or exists(select 1 from suppliers s where s.id=supplier_id and s.status='approved')) or public.is_admin() or supplier_id in(select id from suppliers where user_id=auth.uid()));
create policy "Approved suppliers manage own products" on public.products for all to authenticated using(supplier_id in(select id from suppliers where user_id=auth.uid() and status='approved')) with check(supplier_id in(select id from suppliers where user_id=auth.uid() and status='approved'));
create policy "Admin manages products" on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public product images" on public.product_images for select to anon,authenticated using(exists(select 1 from products p where p.id=product_id and p.status='active') or public.is_admin());
create policy "Admin manages product images" on public.product_images for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public product specs" on public.product_specifications for select to anon,authenticated using(exists(select 1 from products p where p.id=product_id and p.status='active') or public.is_admin());
create policy "Admin manages product specs" on public.product_specifications for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public active variants" on public.product_variants for select to anon,authenticated using(active and exists(select 1 from products p where p.id=product_id and p.status='active') or public.is_admin());
create policy "Admin manages variants" on public.product_variants for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public stock availability" on public.inventory for select to anon,authenticated using(true);
create policy "Admin manages inventory" on public.inventory for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Public quantity price tiers" on public.bulk_price_tiers for select to anon,authenticated using(true);
create policy "Admin manages tiers" on public.bulk_price_tiers for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Own cart" on public.carts for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy "Own cart items" on public.cart_items for all to authenticated using(cart_id in(select id from carts where user_id=auth.uid()) or public.is_admin()) with check(cart_id in(select id from carts where user_id=auth.uid()) or public.is_admin());
create policy "Own wishlist" on public.wishlists for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy "Company members view company" on public.companies for select to authenticated using(created_by=auth.uid() or id in(select company_id from company_members where user_id=auth.uid()) or public.is_admin());
create policy "Company owner manages company" on public.companies for all to authenticated using(created_by=auth.uid() or public.is_admin()) with check(created_by=auth.uid() or public.is_admin());
create policy "Members see company membership" on public.company_members for select to authenticated using(user_id=auth.uid() or company_id in(select company_id from company_members where user_id=auth.uid()) or public.is_admin());
create policy "Company admins manage members" on public.company_members for all to authenticated using(company_id in(select company_id from company_members where user_id=auth.uid() and member_role in('owner','admin')) or public.is_admin()) with check(company_id in(select company_id from company_members where user_id=auth.uid() and member_role in('owner','admin')) or public.is_admin());
create policy "Customer own RFQs" on public.rfqs for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "Customer creates own RFQ" on public.rfqs for insert to authenticated with check(user_id=auth.uid() and status='Submitted');
create policy "Admin manages RFQs" on public.rfqs for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Own RFQ line items" on public.rfq_items for select to authenticated using(rfq_id in(select id from rfqs where user_id=auth.uid()) or public.is_admin());
create policy "Customer adds RFQ line items" on public.rfq_items for insert to authenticated with check(rfq_id in(select id from rfqs where user_id=auth.uid()));
create policy "Admin manages RFQ line items" on public.rfq_items for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Own RFQ files" on public.rfq_files for select to authenticated using(rfq_id in(select id from rfqs where user_id=auth.uid()) or public.is_admin());
create policy "Customer adds RFQ file records" on public.rfq_files for insert to authenticated with check(rfq_id in(select id from rfqs where user_id=auth.uid()));
create policy "Admin manages RFQ file records" on public.rfq_files for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Customer sees quotes for own RFQ" on public.quotations for select to authenticated using(rfq_id in(select id from rfqs where user_id=auth.uid()) or public.is_admin());
create policy "Admin manages quotes" on public.quotations for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Customer sees quote lines" on public.quotation_items for select to authenticated using(quotation_id in(select q.id from quotations q join rfqs r on r.id=q.rfq_id where r.user_id=auth.uid()) or public.is_admin());
create policy "Admin manages quote lines" on public.quotation_items for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Customer own orders" on public.orders for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "Admin manages orders" on public.orders for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Customer sees own order lines" on public.order_items for select to authenticated using(order_id in(select id from orders where user_id=auth.uid()) or public.is_admin());
create policy "Admin manages order lines" on public.order_items for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Customer sees own payments" on public.payments for select to authenticated using(order_id in(select id from orders where user_id=auth.uid()) or public.is_admin());
create policy "Customer sees own shipments" on public.shipments for select to authenticated using(order_id in(select id from orders where user_id=auth.uid()) or public.is_admin());
create policy "Admin manages payments" on public.payments for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Admin manages shipments" on public.shipments for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Customer own invoices" on public.invoices for select to authenticated using(order_id in(select id from orders where user_id=auth.uid()) or public.is_admin());
create policy "Admin manages invoices" on public.invoices for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Approved review visibility" on public.reviews for select to anon,authenticated using(approved or user_id=auth.uid() or public.is_admin());
create policy "Buyer creates own review" on public.reviews for insert to authenticated with check(user_id=auth.uid());
create policy "Admin manages reviews" on public.reviews for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Active coupons readable" on public.coupons for select to authenticated using(active and (starts_at is null or starts_at<=now()) and (expires_at is null or expires_at>now()));
create policy "Admin manages coupons" on public.coupons for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Own notifications" on public.notifications for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "Own notification updates" on public.notifications for update to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy "Message participants" on public.messages for select to authenticated using(sender_id=auth.uid() or recipient_id=auth.uid() or public.is_admin());
create policy "Send messages as self" on public.messages for insert to authenticated with check(sender_id=auth.uid());
create policy "Admin manages site settings" on public.site_settings for all to authenticated using(public.is_admin()) with check(public.is_admin());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('product-media','product-media',true,20971520,array['image/jpeg','image/png','image/webp','application/pdf']) on conflict(id) do nothing;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('rfq-files','rfq-files',false,20971520,array['application/pdf','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','image/jpeg','image/png','image/webp','application/acad','application/octet-stream']) on conflict(id) do nothing;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('supplier-private','supplier-private',false,20971520,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
create policy "Public reads product media" on storage.objects for select to anon,authenticated using(bucket_id='product-media');
create policy "Admin uploads product media" on storage.objects for insert to authenticated with check(bucket_id='product-media' and public.is_admin());
create policy "Admin updates product media" on storage.objects for update to authenticated using(bucket_id='product-media' and public.is_admin()) with check(bucket_id='product-media' and public.is_admin());
create policy "Owner and admin access RFQ files" on storage.objects for select to authenticated using(bucket_id='rfq-files' and (public.is_admin() or (storage.foldername(name))[1]=auth.uid()::text));
create policy "Owner uploads RFQ files" on storage.objects for insert to authenticated with check(bucket_id='rfq-files' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "Supplier owns private files" on storage.objects for select to authenticated using(bucket_id='supplier-private' and (public.is_admin() or (storage.foldername(name))[1]=auth.uid()::text));
create policy "Supplier uploads private files" on storage.objects for insert to authenticated with check(bucket_id='supplier-private' and (storage.foldername(name))[1]=auth.uid()::text);

insert into public.categories(name,slug,sort_order) values
 ('Pipes and Tubes','pipes-tubes',1),('Pipe Fittings','pipe-fittings',2),('Industrial Valves','industrial-valves',3),('Flanges','flanges',4),('Gaskets and Seals','gaskets-seals',5),('Fasteners','fasteners',6),('Steel Materials','steel-materials',7)
on conflict(slug) do nothing;
insert into public.brands(name,slug) values('Northline Metals','northline-metals'),('ForgeWorks','forgeworks'),('Apex Flow Controls','apex-flow-controls'),('SealCore','sealcore'),('Bolt & Bar','bolt-bar'),('MetroSteel','metrosteel') on conflict(slug) do nothing;

-- Catalog examples use fixed IDs so the local catalog and RFQ selections map to seeded rows.
insert into public.products(id,category_id,brand_id,name,slug,sku,description,material,price,unit,moq,status,origin_country) values
('00000000-0000-4000-8000-000000000001',(select id from categories where slug='pipes-tubes'),(select id from brands where slug='northline-metals'),'Seamless Stainless Steel Pipe, Sch 40','seamless-stainless-steel-pipe-sch-40','SSP-304-040-020','Precision seamless pipe for process, water and structural applications.','304 Stainless Steel',42.80,'ft',1,'active','South Korea'),
('00000000-0000-4000-8000-000000000002',(select id from categories where slug='pipe-fittings'),(select id from brands where slug='forgeworks'),'90° Long Radius Butt-Weld Elbow','90-long-radius-butt-weld-elbow','BW-EL-316-04-90','Butt-weld elbow with long-radius geometry for smooth flow transitions.','316 Stainless Steel',36.50,'ea',1,'active','Taiwan'),
('00000000-0000-4000-8000-000000000003',(select id from categories where slug='industrial-valves'),(select id from brands where slug='apex-flow-controls'),'Trunnion-Mounted Ball Valve, Full Port','trunnion-mounted-ball-valve-full-port','BV-150-304-03-FP','Two-piece full-port ball valve for dependable industrial isolation.','CF8M / 316 SS',684.00,'ea',1,'active','United States'),
('00000000-0000-4000-8000-000000000004',(select id from categories where slug='flanges'),(select id from brands where slug='northline-metals'),'Weld Neck Flange, Raised Face','weld-neck-flange-raised-face','WN-150-316-04','Weld neck flange with raised face for process piping.','316 Stainless Steel',78.25,'ea',1,'active','India'),
('00000000-0000-4000-8000-000000000005',(select id from categories where slug='gaskets-seals'),(select id from brands where slug='sealcore'),'Spiral Wound Gasket, 316 / Graphite','spiral-wound-gasket-316-graphite','SWG-150-316-04','Spiral wound gasket for ASME raised-face flange joints.','316 SS / Graphite',19.90,'ea',1,'active','Germany'),
('00000000-0000-4000-8000-000000000006',(select id from categories where slug='fasteners'),(select id from brands where slug='bolt-bar'),'Hex Head Cap Screw, Heavy Pattern','hex-head-cap-screw-heavy-pattern','FST-B8M-075-3','Corrosion-resistant heavy-pattern hex cap screw.','316 Stainless Steel',2.45,'ea',1,'active','United States'),
('00000000-0000-4000-8000-000000000007',(select id from categories where slug='steel-materials'),(select id from brands where slug='metrosteel'),'Carbon Steel Plate, Hot Rolled','carbon-steel-plate-hot-rolled','PL-A36-048-096','Hot-rolled structural carbon steel plate.','ASTM A36 Carbon Steel',318.00,'sheet',1,'active','United States'),
('00000000-0000-4000-8000-000000000008',(select id from categories where slug='pipe-fittings'),(select id from brands where slug='forgeworks'),'Concentric Pipe Reducer, Butt-Weld','concentric-pipe-reducer-butt-weld','BW-RD-304-06X04','Concentric butt-weld reducer for stainless process piping.','304 Stainless Steel',54.30,'ea',1,'active','Taiwan'),
('00000000-0000-4000-8000-000000000009',(select id from categories where slug='industrial-valves'),(select id from brands where slug='apex-flow-controls'),'Gate Valve, Bolted Bonnet, Flanged','gate-valve-bolted-bonnet-flanged','GV-300-CS-04','Bolted-bonnet gate valve for industrial and utility service.','WCB Carbon Steel',912.00,'ea',1,'active','South Korea'),
('00000000-0000-4000-8000-000000000010',(select id from categories where slug='pipes-tubes'),(select id from brands where slug='metrosteel'),'Seamless Carbon Steel Pipe, Sch 80','seamless-carbon-steel-pipe-sch-80','CSP-A106B-080-030','Seamless carbon steel pipe for high-temperature service.','A106 Grade B',51.40,'ft',1,'active','South Korea'),
('00000000-0000-4000-8000-000000000011',(select id from categories where slug='flanges'),(select id from brands where slug='northline-metals'),'Blind Flange, Raised Face','blind-flange-raised-face','BL-300-CS-06','Forged carbon steel blind flange for piping systems.','A105 Carbon Steel',97.00,'ea',1,'active','India'),
('00000000-0000-4000-8000-000000000012',(select id from categories where slug='fasteners'),(select id from brands where slug='bolt-bar'),'Stud Bolt Set, B7 / 2H, PTFE Coated','stud-bolt-set-b7-2h-ptfe-coated','ST-B7-062-4','Stud bolt and heavy hex nut set for flange connections.','ASTM A193 B7 / A194 2H',8.75,'set',1,'active','United States')
on conflict(id) do nothing;
insert into public.product_specifications(product_id,name,value)
select p.id,s.name,s.value from (values
('SSP-304-040-020','Grade','ASTM A312 TP304'),('SSP-304-040-020','NPS','2 in / DN50'),('SSP-304-040-020','Schedule','40S'),('SSP-304-040-020','Wall','0.154 in / 3.91 mm'),('SSP-304-040-020','Length','20 ft random'),('SSP-304-040-020','Standard','ASTM A312 / ASME B36.19M'),
('BW-EL-316-04-90','Grade','ASTM A403 WP316/L'),('BW-EL-316-04-90','NPS','4 in / DN100'),('BW-EL-316-04-90','Schedule','40S'),('BW-EL-316-04-90','Radius','1.5D long radius'),('BW-EL-316-04-90','Ends','Beveled, ASME B16.25'),('BW-EL-316-04-90','Standard','ASME B16.9'),
('BV-150-304-03-FP','Body','ASTM A351 CF8M'),('BV-150-304-03-FP','Size','3 in / DN80'),('BV-150-304-03-FP','Class','ASME Class 150'),('BV-150-304-03-FP','Ends','Flanged, ASME B16.5'),('BV-150-304-03-FP','Seat','PTFE'),('BV-150-304-03-FP','Standard','API 608 / ASME B16.34'),
('WN-150-316-04','Grade','ASTM A182 F316/316L'),('WN-150-316-04','NPS','4 in / DN100'),('WN-150-316-04','Class','150 lb'),('WN-150-316-04','Face','Raised face, 1/16 in'),('WN-150-316-04','Bore','Schedule 40S'),('WN-150-316-04','Standard','ASME B16.5'),
('SWG-150-316-04','Winding','316 stainless steel'),('SWG-150-316-04','Filler','Flexible graphite'),('SWG-150-316-04','NPS','4 in / DN100'),('SWG-150-316-04','Class','150 lb'),('SWG-150-316-04','Standard','ASME B16.20'),
('FST-B8M-075-3','Grade','ASTM A193 B8M'),('FST-B8M-075-3','Diameter','3/4 in'),('FST-B8M-075-3','Length','3 in'),('FST-B8M-075-3','Thread','UNC'),('FST-B8M-075-3','Standard','ASME B18.2.1'),
('PL-A36-048-096','Grade','ASTM A36'),('PL-A36-048-096','Thickness','1/2 in / 12.7 mm'),('PL-A36-048-096','Size','48 × 96 in'),('PL-A36-048-096','Finish','Hot rolled, mill scale'),('PL-A36-048-096','Standard','ASTM A36/A36M'),
('BW-RD-304-06X04','Grade','ASTM A403 WP304/L'),('BW-RD-304-06X04','Size','6 × 4 in'),('BW-RD-304-06X04','Schedule','40S × 40S'),('BW-RD-304-06X04','Ends','Beveled'),('BW-RD-304-06X04','Standard','ASME B16.9'),
('GV-300-CS-04','Body','ASTM A216 WCB'),('GV-300-CS-04','Size','4 in / DN100'),('GV-300-CS-04','Class','ASME Class 300'),('GV-300-CS-04','Trim','13Cr / 13Cr'),('GV-300-CS-04','Ends','Flanged, ASME B16.5'),('GV-300-CS-04','Standard','API 600'),
('CSP-A106B-080-030','Grade','ASTM A106 Grade B'),('CSP-A106B-080-030','NPS','3 in / DN80'),('CSP-A106B-080-030','Schedule','80'),('CSP-A106B-080-030','Wall','0.300 in / 7.62 mm'),('CSP-A106B-080-030','Standard','ASTM A106 / ASME B36.10M'),
('BL-300-CS-06','Grade','ASTM A105N'),('BL-300-CS-06','NPS','6 in / DN150'),('BL-300-CS-06','Class','300 lb'),('BL-300-CS-06','Face','Raised face'),('BL-300-CS-06','Standard','ASME B16.5'),
('ST-B7-062-4','Stud','ASTM A193 Grade B7'),('ST-B7-062-4','Nuts','ASTM A194 Grade 2H'),('ST-B7-062-4','Diameter','5/8 in'),('ST-B7-062-4','Length','4 in'),('ST-B7-062-4','Finish','PTFE coated'),('ST-B7-062-4','Standard','ASME B18.2.2')
) s(sku,name,value) join public.products p on p.sku=s.sku
on conflict(product_id,name) do nothing;
insert into public.inventory(product_id,quantity,reorder_point) select id,case sku when 'SSP-304-040-020' then 248 when 'BW-EL-316-04-90' then 86 when 'BV-150-304-03-FP' then 24 when 'WN-150-316-04' then 113 when 'SWG-150-316-04' then 420 when 'FST-B8M-075-3' then 2400 when 'PL-A36-048-096' then 42 when 'BW-RD-304-06X04' then 69 when 'GV-300-CS-04' then 17 when 'CSP-A106B-080-030' then 184 when 'BL-300-CS-06' then 56 else 760 end,10 from public.products where sku in ('SSP-304-040-020','BW-EL-316-04-90','BV-150-304-03-FP','WN-150-316-04','SWG-150-316-04','FST-B8M-075-3','PL-A36-048-096','BW-RD-304-06X04','GV-300-CS-04','CSP-A106B-080-030','BL-300-CS-06','ST-B7-062-4') on conflict(product_id) do nothing;
insert into public.bulk_price_tiers(product_id,min_quantity,unit_price) select id,10,round(price*0.97,2) from public.products where sku in ('SSP-304-040-020','BW-EL-316-04-90','BV-150-304-03-FP','WN-150-316-04','SWG-150-316-04','FST-B8M-075-3','PL-A36-048-096','BW-RD-304-06X04','GV-300-CS-04','CSP-A106B-080-030','BL-300-CS-06','ST-B7-062-4') on conflict(product_id,min_quantity) do nothing;
