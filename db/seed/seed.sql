-- Seed hotel_bookings with 120 rows across multiple cities, orgs, statuses
INSERT INTO hotel_bookings (org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
SELECT
    (ARRAY[
        'a1111111-1111-1111-1111-111111111111',
        'a2222222-2222-2222-2222-222222222222',
        'a3333333-3333-3333-3333-333333333333',
        'a4444444-4444-4444-4444-444444444444',
        'a5555555-5555-5555-5555-555555555555'
    ]::uuid[])[floor(random() * 5 + 1)],
    'HTL' || LPAD((floor(random() * 50) + 1)::text, 3, '0'),
    (ARRAY['delhi', 'mumbai', 'bangalore', 'goa', 'jaipur', 'pune'])[floor(random() * 6 + 1)],
    (CURRENT_DATE - (floor(random() * 90) || ' days')::interval)::date AS checkin_date,
    (CURRENT_DATE - (floor(random() * 90) || ' days')::interval + '3 days'::interval)::date AS checkout_date,
    ROUND((random() * 20000 + 2000)::numeric, 2),
    (ARRAY['confirmed', 'cancelled', 'pending', 'completed'])[floor(random() * 4 + 1)],
    NOW() - (floor(random() * 60) || ' days')::interval
FROM generate_series(1, 120);

-- Seed booking_events for ~60% of bookings (1-3 events each)
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    b.id,
    (ARRAY['booking_created', 'payment_received', 'booking_cancelled', 'checkin_completed'])[floor(random() * 4 + 1)],
    jsonb_build_object('source', 'seed_script', 'amount', b.amount, 'status_at_event', b.status),
    b.created_at + (floor(random() * 5) || ' hours')::interval
FROM hotel_bookings b
CROSS JOIN generate_series(1, floor(random() * 3 + 1)::int)
WHERE random() < 0.6;