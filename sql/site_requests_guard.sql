-- Spam guard for website forms (table site_requests).
-- Run once in Supabase: Dashboard -> SQL Editor -> paste -> Run.
-- Rejects a new website request when
--   * more than 20 requests arrived in the last 10 minutes (stops floods of fake orders and Telegram messages),
--   * the request is larger than 100 KB, or the form name is longer than 80 characters.
-- A rejected request is not saved, so no order and no Telegram message is created.
-- Real customers are not affected: the website still e-mails every form to info@forestkings.com.

create or replace function public.site_requests_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if length(coalesce(new.kind, '')) > 80 then
    raise exception 'site_requests: form name too long';
  end if;
  if octet_length(coalesce(new.data::text, '')) > 100000 then
    raise exception 'site_requests: request too large';
  end if;
  if (select count(*) from public.site_requests
      where created_at > now() - interval '10 minutes') >= 20 then
    raise exception 'site_requests: too many requests, try again later';
  end if;
  return new;
end;
$$;

drop trigger if exists site_requests_guard on public.site_requests;
create trigger site_requests_guard
  before insert on public.site_requests
  for each row execute function public.site_requests_guard();
