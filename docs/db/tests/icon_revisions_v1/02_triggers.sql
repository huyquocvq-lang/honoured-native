-- Production's triggers on contracts and icon_days (catalog, 28 Oct 2026).
\set ON_ERROR_STOP on

create trigger contracts_icon_days after insert or update on public.contracts
  for each row execute function public.contracts_icon_days();
create trigger contracts_icon_guard before insert or update on public.contracts
  for each row execute function public.contracts_icon_guard();
create trigger contracts_icon_reserve before insert on public.contracts
  for each row execute function public.contracts_icon_reserve();
create trigger contracts_word_guard before insert or update on public.contracts
  for each row execute function public.contracts_word_guard();
create trigger update_contracts_updated_at before update on public.contracts
  for each row execute function public.update_updated_at_column();
create trigger update_icon_days_updated_at before update on public.icon_days
  for each row execute function public.update_updated_at_column();
