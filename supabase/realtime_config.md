# Supabase Realtime Configuration

Enable real-time change events on `transactions` and `budgets` tables so the Flutter dashboard auto-updates.

## Step 1 — Run `schema.sql` first

The last two lines of `schema.sql` already add both tables to the `supabase_realtime` publication:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.budgets;
```

## Step 2 — Enable Realtime in the Supabase Dashboard

1. Go to **Supabase Dashboard → Database → Replication**
2. Under **"Tables in public schema receiving realtime changes"**:
   - Toggle **ON** for `transactions`
   - Toggle **ON** for `budgets`

## Step 3 — Verify via Dashboard

In **Supabase → Table Editor**, open `transactions` and insert a test row.
You should see the event fire in **Database → Replication → Inspect**.

## Step 4 — Flutter Client Subscription

The Flutter app subscribes like this:

```dart
// transactions — live feed
supabase
  .from('transactions')
  .stream(primaryKey: ['id'])
  .eq('household_id', householdId)
  .order('created_at', ascending: false)
  .listen((data) { /* update UI */ });

// budgets — live balance updates
supabase
  .from('budgets')
  .stream(primaryKey: ['id'])
  .eq('household_id', householdId)
  .listen((data) { /* update progress bars */ });
```

## Notes

- Realtime uses **Postgres logical replication** under the hood — `wal_level` must be `logical` (Supabase sets this by default).
- If the Flutter `.stream()` call returns empty results, double-check your **RLS policies** — a policy must allow SELECT for the authenticated user.
- The Python service uses the **service role key** which bypasses RLS, so its inserts will always propagate to Realtime subscribers.
