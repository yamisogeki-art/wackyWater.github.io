-- Columns written by the kyc-verify Edge Function
alter table public.kyc_submissions
  add column if not exists face_match_score numeric,
  add column if not exists review_note text;

-- Stop clients from approving themselves.
-- Any insert/update that is NOT made with the service role is forced back to
-- "pending" with no score, so only the Edge Function (service role) or an
-- admin using the service role can set a final status.
create or replace function public.kyc_protect_status()
returns trigger
language plpgsql
as $$
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
