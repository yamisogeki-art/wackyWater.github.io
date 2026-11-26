-- KYC setup: safe to run more than once.

-- 1. Private storage bucket (already exists? just make sure it is private)
insert into storage.buckets (id, name, public)
values ('kyc-documents', 'kyc-documents', false)
on conflict (id) do update set public = false;

-- 2. Storage policies (users can only write inside their own folder)
drop policy if exists "kyc upload own folder" on storage.objects;
create policy "kyc upload own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "kyc update own folder" on storage.objects;
create policy "kyc update own folder" on storage.objects
  for update to authenticated
  using (bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = auth.uid()::text);

-- Needed because uploads use upsert (INSERT ... ON CONFLICT DO UPDATE),
-- which also requires a SELECT policy. Users can only read their own folder.
drop policy if exists "kyc read own folder" on storage.objects;
create policy "kyc read own folder" on storage.objects
  for select to authenticated
  using (bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = auth.uid()::text);

-- 3. Table
create table if not exists public.kyc_submissions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  id_type text not null,
  id_image_path text not null,
  selfie_path text not null,
  selfie_smile_path text not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  face_match_score numeric,
  review_note text,
  reviewed_at timestamptz,
  created_at timestamptz default now()
);

-- In case the table was created earlier without the result columns
alter table public.kyc_submissions
  add column if not exists face_match_score numeric,
  add column if not exists review_note text,
  add column if not exists reviewed_at timestamptz;

alter table public.kyc_submissions enable row level security;

-- 4. Table policies
drop policy if exists "own kyc insert" on public.kyc_submissions;
create policy "own kyc insert" on public.kyc_submissions
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "own kyc update" on public.kyc_submissions;
create policy "own kyc update" on public.kyc_submissions
  for update to authenticated
  using (user_id = auth.uid() and status in ('pending','rejected'));

drop policy if exists "own kyc read" on public.kyc_submissions;
create policy "own kyc read" on public.kyc_submissions
  for select to authenticated using (user_id = auth.uid());

-- 5. Tamper protection: only the service role can set a final status
create or replace function public.kyc_protect_status()
returns trigger language plpgsql as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') in ('anon', 'authenticated') then
    new.status := 'pending';
    new.face_match_score := null;
    new.review_note := null;
    new.reviewed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists kyc_protect_status_trg on public.kyc_submissions;
create trigger kyc_protect_status_trg
before insert or update on public.kyc_submissions
for each row execute function public.kyc_protect_status();
