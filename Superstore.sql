rename table superstore_orders to orders

rename table superstore_returns to orders_returns

alter table orders rename column `Ship Mode` to ship_mode

alter table orders rename column `Ship _Date` to ship_date

create table o1 as 
select 
	row_id
	,order_id
	,cast(date_format(str_to_date(order_date, '%d.%m.%Y'), '%Y-%m-%d') as date)	as order_date
	,cast(date_format(str_to_date(ship_date, '%d.%m.%Y'), '%Y-%m-%d') as date)	as ship_date
	,ship_mode
	,customer_id
	,customer_name
	,segment
	,country
	,city
	,state
	,cast(replace(postal_code, ',', '' ) as char(50)) as postal_code
	,region
	,product_id
	,category
	,sub_category
	,product_name
	,cast(replace(replace(sales, ',', '.'), ' ', '') as decimal(10, 2)) as sales
	,cast(quantity as signed) as quantity
	,cast(replace(replace(discount, ',', '.'), ' ', '') as decimal(10, 2)) as discount
	,cast(replace(replace(profit, ',', '.'), ' ', '') as decimal(10, 2)) as profit
from orders 

/* What are the 5 most profitable products and what features do they have in common? */

with ranking as
(
select 
	product_name
	,sum(sum(profit)) over (partition by product_name) 	as total_profit_per_product
	,dense_rank () over (order by sum(profit) desc) 	as ranking
from o1
group by 1
order by 2 desc
)
select	
	r.ranking
	,r.total_profit_per_product
	,sum(o.profit)  					as profit
	,o.product_name  
	,o.segment 
	,o.category 
	,o.sub_category 
from o1	o
inner join ranking r on o.product_name = r.product_name
group by 4, 5, 6, 7
order by 2 desc 
limit 12

/* How do sales and profits change across product categories and subcategories in different regions? */

select 
	region
	,category
	,sub_category 
	,dense_rank () over (order by sum(sales) desc) 							as ranking
	,sum(sum(sales)) over (partition by region) 							as sales_per_region
	,sum(sum(sales)) over (partition by category) 							as sales_per_category
	,sum(sum(sales)) over (partition by sub_category) 						as sales_per_sub_category
	,sum(sum(sales)) over (partition by category, sub_category, region) 				as total_sales_per_category
	,sum(sum(profit)) over (partition by category) 							as profit_per_category
	,sum(sum(profit)) over (partition by sub_category) 						as profit_per_sub_category
	,sum(sum(profit)) over (partition by region) 							as profit_per_region 
from o1	
group by 1, 2, 3
order by 4

/* Which customer demonstrated the greatest growth purchase over time? */

-- 1st way: last order vs first order

with 
latest_order as 
	(
    select 
        customer_name
        ,max(order_date) 		as latest_order_date
    from o1
    group by 1
	),
sales_per_latest_order as
	(
	select 
   		o.customer_name
 	   ,lo.latest_order_date
  	   ,sum(o.sales) 		as total_sales_for_latest_date
	from o1 o 
	join latest_order lo
	    on o.customer_name = lo.customer_name
	    and o.order_date = lo.latest_order_date
	group by 1
	order by 1
	),
first_order as
	(
	select
		customer_name
		,min(order_date)  	as first_order_day
	from o1
	group by 1
	),
sales_per_first_order as
	(
	select 
   		o.customer_name
 	   ,fo.first_order_day
  	   ,sum(o.sales) 		as total_sales_for_first_date
	from o1 o 
	join first_order fo
    on o.customer_name = fo.customer_name
    and o.order_date = fo.first_order_day
	group by 1
	order by 1
	)
select
	splo.customer_name
	,splo.total_sales_for_latest_date
	,spfo.total_sales_for_first_date
	,round((splo.total_sales_for_latest_date / spfo.total_sales_for_first_date -1) * 100, 0)	as sales_growth_in_percent
from sales_per_latest_order			splo
inner join sales_per_first_order	spfo on splo.customer_name = spfo.customer_name
order by 1 

								/* 2nd way - YoY growth */

with 
first_and_last_order as 
	(
    select 
        customer_name
        ,cast(max(year(order_date))	as year) as last_order_year
        ,cast(min(year(order_date))	as year) as first_order_year
    from o1
    group by 1
	),
sales_for_last_year as
	(
	select 
   		o.customer_name
 	   ,flo.last_order_year
  	   ,sum(o.sales) 			as sales_for_last_year
	from o1 o 
	join first_and_last_order flo
	    on o.customer_name = flo.customer_name
	    and year(o.order_date) = flo.last_order_year
	group by 1
	order by 1
	),
sales_for_first_year as
	(
	select 
   		o.customer_name
 	   ,flo.first_order_year
  	   ,sum(o.sales) 				as sales_for_first_year
	from o1 o 
	join first_and_last_order flo
	    on o.customer_name = flo.customer_name
	    and year(o.order_date) = flo.first_order_year
	group by 1
	order by 1
	)
select
	sly.customer_name
	,sly.sales_for_last_year
	,flo.last_order_year
	,sfy.sales_for_first_year
    ,flo.first_order_year
	,round((sly.sales_for_last_year / sfy.sales_for_first_year -1) * 100, 0)	as sales_growth_in_percent
from sales_for_last_year			sly
inner join sales_for_first_year		sfy on sly.customer_name = sfy.customer_name
inner join first_and_last_order		flo on sly.customer_name = flo.customer_name
order by 6 desc

/* Can we divide the customers into segmnetss based on their purchasing patterns and indetify the most valuable segments? */
	
select 
	segment 
	,year(order_date)
	,count(distinct customer_name) 	as unique_customers
	,round(sum(sales), 0) 			as sales_per_segment_and_year
from o1
group by 1, 2
order by 4 desc

/* How do seasonal trends affect sales in different categories? */

select 
	category
	,date_format(order_date, '%m-%Y')	as period_of_time
	,round(sum(sales), 0)			as sales
from o1
group by 1, 2
order by 3 desc

/* Is there a correlation between discount levels and sales volume over time? */

select 
	round(sum((sales - avg_sales) * (discount - avg_discount)) / 
	sqrt(sum(pow(sales - avg_sales, 2)) * sum(pow(discount - avg_discount, 2))), 4) as correlation
from 
	(
	select
		sales
		,discount
		,(select avg(sales) from o1 ) 	 as avg_sales
		,(select avg(discount) from o1 ) as avg_discount
	from o1
	) data
	
/* Wich cities and state are the most profitable for different product categories? */
	
select 
	distinct state 
	,city 
	,category 
	,sum(profit) over (partition by state) 				as profit_per_state
	,sum(profit) over (partition by city) 				as profit_per_city
	,sum(profit) over (partition by category) 			as profit_per_category	
	,sum(profit) over (partition by state, city, category) 		as profit_per_state_city_category
from o1
order by 4 desc, 5 desc, 6 desc

/* How does delivery method effect on sales and customer satisfaction in different regions? */

select 
	o.ship_mode 
	,round(sum(o.sales))						as sales
	,count(o.order_id)						as total_orders
	,count(ore.returned)						as returned_orders
	,round(count(ore.returned) / count(o.order_id) * 100, 2) 	as return_rate
from o1 o
left join orders_returns ore on o.order_id = ore.order_id
group by 1
order by 2 desc

/* Which products have the highest and lowest return rates? How does the product mix differ across stores and how does this impact overall profitability?*/

select
	category 
	,sub_category
	,sales
	,return_rate
	,avg(return_rate) over ()		/* avg = 7,94 */		as avg_return_rate
	,profitability_in_percent
from
	(
	select
		o.category
		,o.sub_category
		,round(sum(o.sales))						as sales
		,round(count(ore.returned) / count(o.order_id) *100 , 2) 	as return_rate
		,round(sum(o.profit) / sum(o.sales) * 100, 1)			as profitability_in_percent
	from o1 o	
	left join orders_returns ore on o.order_id = ore.order_id
	group by 1, 2
	) stats
order by 4 desc
