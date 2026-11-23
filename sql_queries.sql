-- =====================================================================
-- Customer Shopping Behavior Analysis : PostgreSQL queries
-- Table: customer  (loaded from the cleaned DataFrame in the notebook)
-- Columns: customer_id, age, gender, item_purchased, category,
--   purchase_amount, location, size, color, season, review_rating,
--   subscription_status, shipping_type, discount_applied,
--   previous_purchases, payment_method, frequency_of_purchases,
--   age_group, purchase_frequency_days, customer_segment
-- Note: customer_id is unique, so 1 row = 1 customer = 1 purchase.
-- Principle: every comparison shows rates / per-customer averages and
-- a baseline, not just raw totals.
-- =====================================================================

-- Q0. Headline KPIs
select count(*) as total_customers,
       sum(purchase_amount) as total_revenue,
       round(avg(purchase_amount), 2) as avg_purchase_amount,
       round(avg(review_rating)::numeric, 2) as avg_review_rating,
       round(100.0 * sum(case when discount_applied = 'Yes' then 1 else 0 end) / count(*), 1) as pct_discounted_purchases,
       round(100.0 * sum(case when subscription_status = 'Yes' then 1 else 0 end) / count(*), 1) as pct_subscribers
from customer;

-- Q1. Revenue by gender: totals AND per-customer spend AND customer mix.
select gender,
       count(*) as customers,
       round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_customers,
       sum(purchase_amount) as revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue,
       round(avg(purchase_amount), 2) as avg_spend_per_customer
from customer
group by gender
order by revenue desc;

-- Q2. Do discounts change spend? (replaces the "spent above average" query,
--     which returns ~50% of any group by definition)
select discount_applied,
       count(*) as customers,
       round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_purchases,
       round(avg(purchase_amount), 2) as avg_spend,
       sum(purchase_amount) as revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue
from customer
group by discount_applied
order by discount_applied desc;

-- Q3. Top 5 products by average review rating, with volume and baseline.
select item_purchased,
       count(*) as n_reviews,
       round(avg(review_rating)::numeric, 2) as avg_rating,
       (select round(avg(review_rating)::numeric, 2) from customer) as overall_avg_rating
from customer
group by item_purchased
having count(*) >= 100              -- only products with enough volume
order by avg(review_rating) desc
limit 5;

-- Q4. Shipping types (all 6): spend, volume, share, gap vs overall average.
select shipping_type,
       count(*) as orders,
       round(avg(purchase_amount), 2) as avg_spend,
       round(avg(purchase_amount) - (select avg(purchase_amount) from customer), 2) as diff_vs_overall_avg,
       sum(purchase_amount) as revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue
from customer
group by shipping_type
order by avg_spend desc;

-- Q4b. Offline proxy: Store Pickup vs delivery methods.
select case when shipping_type = 'Store Pickup' then 'Offline proxy (Store Pickup)' else 'Delivery' end as channel,
       count(*) as orders,
       round(avg(purchase_amount), 2) as avg_spend,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue
from customer
group by 1;

-- Q5. Subscribers vs non-subscribers: share of customers vs share of revenue.
select subscription_status,
       count(*) as total_customers,
       round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_customers,
       round(avg(purchase_amount), 2) as avg_spend,
       sum(purchase_amount) as total_revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue
from customer
group by subscription_status
order by subscription_status desc;

-- Q6. Discount-dependent products vs the overall baseline discount rate.
select item_purchased,
       count(*) as orders,
       round(100.0 * sum(case when discount_applied = 'Yes' then 1 else 0 end) / count(*), 2) as discount_rate,
       (select round(100.0 * sum(case when discount_applied = 'Yes' then 1 else 0 end) / count(*), 2) from customer) as baseline_discount_rate
from customer
group by item_purchased
order by discount_rate desc
limit 5;

-- Q7. Customer segments with balanced, quartile-based cut-offs
--     (previous_purchases quartiles = 13 / 25 / 38; same rule as the notebook).
--     New: 1-13 | Returning: 14-38 | Loyal: 39-50
with customer_type as (
    select customer_id, purchase_amount, previous_purchases,
           case when previous_purchases <= 13 then 'New'
                when previous_purchases <= 38 then 'Returning'
                else 'Loyal'
           end as customer_segment
    from customer
)
select customer_segment,
       count(*) as customers,
       round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_customers,
       round(avg(purchase_amount), 2) as avg_spend,
       sum(purchase_amount) as revenue,
       round(avg(previous_purchases), 1) as avg_previous_purchases
from customer_type
group by customer_segment
order by min(previous_purchases);

-- Q8. Top 3 products per category. DENSE_RANK keeps tied products
--     (ROW_NUMBER broke ties arbitrarily, e.g. Blouse vs Pants at 171).
with item_counts as (
    select category, item_purchased,
           count(customer_id) as total_orders,
           dense_rank() over (partition by category order by count(customer_id) desc) as item_rank
    from customer
    group by category, item_purchased
)
select item_rank, category, item_purchased, total_orders
from item_counts
where item_rank <= 3
order by category, item_rank, item_purchased;

-- Q9. Are repeat buyers (>5 previous purchases) more likely to subscribe?
--     Reported as a RATE within each group, not raw counts.
select subscription_status,
       count(*) as customers,
       sum(case when previous_purchases > 5 then 1 else 0 end) as repeat_buyers,
       round(100.0 * sum(case when previous_purchases > 5 then 1 else 0 end) / count(*), 1) as repeat_buyer_rate
from customer
group by subscription_status
order by subscription_status desc;

-- Q10. Revenue contribution by age group (ordered youngest to oldest).
select age_group,
       min(age) || '-' || max(age)as age_range,
       count(*)as customers,
       sum(purchase_amount)as total_revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue,
       round(avg(purchase_amount), 2)as avg_spend_per_customer
from customer
group by age_group
order by min(age);

-- =====================================================================
-- NEW QUERIES covering the remaining business drivers
-- =====================================================================

-- Q11. Season: revenue and average spend.
select season,
       count(*)as orders,
       sum(purchase_amount)as revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue,
       round(avg(purchase_amount), 2)as avg_spend
from customer
group by season
order by case season when 'Spring' then 1 when 'Summer' then 2 when 'Fall' then 3 else 4 end;

-- Q12. Payment method: popularity and spend.
select payment_method,
       count(*)as orders,
       round(100.0 * count(*) / sum(count(*)) over (), 1)as pct_of_orders,
       sum(purchase_amount)as revenue,
       round(avg(purchase_amount), 2)as avg_spend
from customer
group by payment_method
order by revenue desc;

-- Q13. Location: top 10 and bottom 10 states by revenue.
(select 'Top 10' as grp, location, count(*) as customers, sum(purchase_amount) as revenue,
        round(avg(purchase_amount), 2) as avg_spend
 from customer group by location order by sum(purchase_amount) desc limit 10)
union all
(select 'Bottom 10' as grp, location, count(*) as customers, sum(purchase_amount) as revenue,
        round(avg(purchase_amount), 2) as avg_spend
 from customer group by location order by sum(purchase_amount) asc limit 10);

-- Q14. Review rating vs spend, using rating bands.
select case when review_rating < 3.0  then '1) <3.0'
            when review_rating < 3.5  then '2) 3.0-3.49'
            when review_rating < 4.0  then '3) 3.5-3.99'
            when review_rating < 4.5  then '4) 4.0-4.49'
            else                           '5) 4.5-5.0' end as rating_band,
       count(*)as customers,
       round(avg(purchase_amount), 2)as avg_spend
from customer
group by 1
order by 1;

-- Q15. Category x season: revenue, plus each category's seasonal share.
select category,
       sum(purchase_amount) filter (where season = 'Spring') as spring,
       sum(purchase_amount) filter (where season = 'Summer') as summer,
       sum(purchase_amount) filter (where season = 'Fall')   as fall,
       sum(purchase_amount) filter (where season = 'Winter') as winter,
       round(100.0 * sum(purchase_amount) filter (where season = 'Fall') / sum(purchase_amount), 1) as pct_in_fall,
       sum(purchase_amount)as total
from customer
group by category
order by total desc;

-- Q16. Purchase frequency vs average spend.
select purchase_frequency_days,
       count(*)as customers,
       round(avg(purchase_amount), 2)as avg_spend,
       sum(purchase_amount)as revenue
from customer
group by purchase_frequency_days
order by purchase_frequency_days;

-- Q17. Category share of revenue.
select category,
       count(*)as orders,
       sum(purchase_amount)as revenue,
       round(100.0 * sum(purchase_amount) / sum(sum(purchase_amount)) over (), 1) as pct_of_revenue,
       round(avg(purchase_amount), 2)as avg_spend
from customer
group by category
order by revenue desc;
