with main_cte as
(
select ordernumber,orderdate,customernumber,sum(sales_value) as sales_value
from
(
SELECT t1.ordernumber,orderdate,customernumber,productcode,t2.quantityOrdered*t2.priceeach as sales_value
FROM classicmodels.orders t1
inner join classicmodels.orderdetails t2
on t1.ordernumber=t2.ordernumber) main
group by ordernumber,orderdate,customernumber
),
sales_query as
(
select t1.*,lag(sales_value) over (partition by t1.customernumber order by t1.orderdate) as previous_salesvalue,customerName,row_number() over (partition by customernumber order by orderdate) as purchase_number
from main_cte t1
inner join classicmodels.customers t2
on t1.customernumber=t2.customernumber
)
select *, sales_value-previous_salesvalue as purchase_valuechange
from sales_query
where previous_salesvalue is not null

with cte as 
(
SELECT customerNumber,customerName,addressLine1,addressLine2,city,state,country,postalCode,salesRepEmployeeNumber as employeeNumber
FROM classicmodels.customers 
),
offices_query as
(
select customerNumber,customerName,addressLine1,addressLine2,city,state,country,postalCode,officeCode
from cte t1
inner join employees t2
on t1.employeeNumber=t2. employeeNumber)
select t2.officeCode,customerNumber,customerName,t1.addressLine1,t2.addressLine2,t1.city,t1.state,t1.country,t1.postalCode
from offices_query t1
right join offices t2
on t1.officeCode=t2.officeCode

SELECT *,
date_add(shippedDate,interval 3 day) as latest_shipping_date,
case when date_add(shippedDate,interval 3 day) > requiredDate 
then 1 
else 0 
end as late_flag,
case when date_add(shippedDate,interval 3 day) > requiredDate
then datediff(date_add(shippedDate,interval 3 day), requiredDate)
else 0
end as order_delayed_by 
FROM classicmodels.orders
where (date_add(shippedDate,interval 3 day) > requiredDate) = 1

with sales as
(
SELECT orderdate,t1.orderNumber,t1.customernumber,customerName,productCode,creditLimit,quantityOrdered*priceEach as sales_value
FROM classicmodels.orders t1
inner join classicmodels.orderdetails t2
on t1.orderNumber=t2.orderNumber
inner join classicmodels.customers t3
on t1.customerNumber=t3.customerNumber
) ,
sales_aggregate as
(
select orderdate,orderNumber,customernumber,customerName,creditLimit,sum(sales_value) as sales_value
from sales
group by orderdate,orderNumber,customernumber,customerName,creditlimit
)
select *,
sum(sales_value) over(partition by customernumber order by orderdate) as sales_aggregate
from sales_aggregate

SELECT
    -- Product information
    p.productCode,
    p.productName,
    p.productLine,

    -- Customer location information
    c.country,
    c.city,

    -- Total quantity sold
    SUM(od.quantityOrdered) AS total_quantity_sold,

    -- Sales Value = Quantity × Selling Price
    ROUND(SUM(od.quantityOrdered * od.priceEach), 2) AS sales_value,

    -- Cost of Sales = Quantity × Product Buy Price
    ROUND(SUM(od.quantityOrdered * p.buyPrice), 2) AS cost_of_sales,

    -- Net Profit = Sales Value - Cost of Sales
    ROUND(
        SUM((od.quantityOrdered * od.priceEach) -
            (od.quantityOrdered * p.buyPrice)
        ), 2
    ) AS net_profit

FROM orders o

-- Join order details to get product sales information
INNER JOIN orderdetails od
    ON o.orderNumber = od.orderNumber

-- Join products table to get product details and cost price
INNER JOIN products p
    ON od.productCode = p.productCode

-- Join customers table to get country and city information
INNER JOIN customers c
    ON o.customerNumber = c.customerNumber

-- Filter only orders from the year 2004
WHERE YEAR(o.orderDate) = 2004

-- Group data by product and customer location
GROUP BY
    p.productCode,
    p.productName,
    p.productLine,
    c.country,
    c.city

-- Sort by highest sales value
ORDER BY sales_value DESC;

WITH customer_sales AS (
    
    SELECT
        o.orderNumber,
        o.orderDate,
        o.customerNumber,
        c.customerName,

        -- Calculate total order sales
        ROUND(SUM(od.quantityOrdered * od.priceEach), 2) AS current_sale_value

    FROM orders o

    -- Join order details to calculate sales
    INNER JOIN orderdetails od
        ON o.orderNumber = od.orderNumber

    -- Join customers table for customer information
    INNER JOIN customers c
        ON o.customerNumber = c.customerNumber

    GROUP BY
        o.orderNumber,
        o.orderDate,
        o.customerNumber,
        c.customerName
)

-- Step 2: Use LAG() to get previous sale value
SELECT

    customerNumber,
    customerName,
    orderNumber,
    orderDate,

    -- Current order sales value
    current_sale_value,

    -- Previous order sales value for the same customer
    LAG(current_sale_value)
        OVER (
            PARTITION BY customerNumber
            ORDER BY orderDate
        ) AS previous_sale_value,

    -- Difference between current and previous sale
    ROUND(
        current_sale_value -
        LAG(current_sale_value)
            OVER (
                PARTITION BY customerNumber
                ORDER BY orderDate
            ),
        2
    ) AS sale_difference

FROM customer_sales

-- Sort output by customer and order date
ORDER BY
    customerNumber,
    orderDate;


WITH customer_sales AS (

    SELECT
        o.customerNumber,

        -- Total sales amount
        ROUND(SUM(od.quantityOrdered * od.priceEach), 2) AS total_sales

    FROM orders o

    INNER JOIN orderdetails od
        ON o.orderNumber = od.orderNumber

    GROUP BY o.customerNumber
),

-- Step 2: Calculate total payments made by each customer
customer_payments AS (

    SELECT
        customerNumber,

        -- Total amount paid
        ROUND(SUM(amount), 2) AS total_payments

    FROM payments

    GROUP BY customerNumber
)

-- Step 3: Combine customer details, sales, and payments
SELECT

    c.customerNumber,
    c.customerName,
    c.country,
    c.city,

    -- Customer credit limit
    c.creditLimit,

    -- Total sales value
    COALESCE(cs.total_sales, 0) AS total_sales,

    -- Total payments made
    COALESCE(cp.total_payments, 0) AS total_payments,

    -- Outstanding balance
    ROUND(
        COALESCE(cs.total_sales, 0) -
        COALESCE(cp.total_payments, 0),
        2
    ) AS money_owed,

    -- Remaining available credit
    ROUND(
        c.creditLimit -
        (
            COALESCE(cs.total_sales, 0) -
            COALESCE(cp.total_payments, 0)
        ),
        2
    ) AS remaining_credit,

    -- Check whether customer exceeded credit limit
    CASE
        WHEN (
            COALESCE(cs.total_sales, 0) -
            COALESCE(cp.total_payments, 0)
        ) > c.creditLimit
        THEN 'Exceeded Credit Limit'

        ELSE 'Within Credit Limit'
    END AS credit_status

FROM customers c

-- Join customer sales
LEFT JOIN customer_sales cs
    ON c.customerNumber = cs.customerNumber

-- Join customer payments
LEFT JOIN customer_payments cp
    ON c.customerNumber = cp.customerNumber

-- Show customers with highest owed amount first
ORDER BY money_owed DESC;

create or replace VIEW classic_models_dataset_for_Power_BI AS
select 
 orderdate,
 ord.ordernumber,
 productName,
 productline,
 cust.country as customer_country,
 ofs.country as office_country,
 prod.productCode,
 priceEach,
 quantityOrdered,
 buyPrice,
 quantityOrdered*priceEach as sales_value,
 quantityOrdered*buyprice as cost_of_sales
 
from classicmodels.orders ord
 inner join classicmodels.orderdetails ord_det
   on ord.orderNumber=ord_det.orderNumber
 inner join classicmodels.customers cust
   on ord.customerNumber= cust.customerNumber
 inner join classicmodels.employees emp
   on cust.salesRepEmployeeNumber= emp.employeeNumber
 inner join classicmodels.offices ofs
   on emp.officeCode=ofs.officeCode
 inner join classicmodels.products prod
   on ord_det.productcode= prod.productcode
   
   order by orderDate
