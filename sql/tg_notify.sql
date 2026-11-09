-- Telegram notification for new website requests (trigger site_requests_tg on public.site_requests).
-- Sends only: request number, type, model / shape (configurator requests) and country.
-- No name, e-mail, phone or message text is sent to Telegram.
-- Token and chat_id are read from public.tg_config; they are not written here.
-- Run once in Supabase: Dashboard -> SQL Editor -> paste -> Run. The existing trigger keeps working with the new function.

create extension if not exists pg_net with schema extensions;

create or replace function public.tg_notify()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  cfg   record;
  d     jsonb := coalesce(new.data, '{}'::jsonb);
  kind  text  := coalesce(new.kind, '');
  typ   text;
  ref   text;
  model text;
  ctry  text;
  msg   text;
begin
  select token, chat_id into cfg from public.tg_config order by id limit 1;
  if cfg.token is null or cfg.chat_id is null then
    return new;
  end if;

  typ := case
    when kind = 'Hot tub request'              then 'Hot tub request'
    when kind = 'Website contact message'      then 'Contact message'
    when kind = 'Consultation booking request' then 'Consultation booking'
    when kind like 'Withdrawal notice%'        then 'Withdrawal notice'
    else 'Website form'
  end;
  ref   := coalesce(nullif(d #>> '{order,order_id}', ''), nullif(d ->> 'order_no', ''));
  model := nullif(concat_ws(' - ',
             nullif(d #>> '{order,configuration,model,name}', ''),
             coalesce(nullif(d #>> '{order,configuration,inner_shape}', ''), nullif(d #>> '{order,configuration,shape}', ''))), '');
  ctry  := coalesce(nullif(d ->> 'delivery_country', ''), nullif(d ->> 'country', ''), nullif(d #>> '{order,delivery,country}', ''));

  msg := concat_ws(E'\n',
    'New ' || typ || ' #' || new.id,
    case when ref   is not null then 'Ref: '     || left(ref, 40)   end,
    case when model is not null then 'Model: '   || left(model, 80) end,
    case when ctry  is not null then 'Country: ' || left(ctry, 60)  end,
    'Details: https://db.forestkings.com');

  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || cfg.token || '/sendMessage',
    body    := jsonb_build_object('chat_id', cfg.chat_id, 'text', msg),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 20000   -- 5000 was too short: Telegram notifications failed with a timeout
  );
  return new;
exception when others then
  return new;   -- a Telegram problem never blocks saving the request
end;
$$;
