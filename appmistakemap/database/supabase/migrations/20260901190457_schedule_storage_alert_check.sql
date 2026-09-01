select cron.schedule(
  'check-storage-usage',
  '*/15 * * * *',
  $$select public.check_storage_and_alert();$$
);