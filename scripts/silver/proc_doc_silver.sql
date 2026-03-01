/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    CALL silver.load_silver();
===============================================================================
*/
CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    start_time        TIMESTAMP;
    end_time          TIMESTAMP;
    batch_start_time  TIMESTAMP;
    batch_end_time    TIMESTAMP;
BEGIN

    batch_start_time := clock_timestamp();

    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Silver Layer';
    RAISE NOTICE '================================================';

    ----------------------------------------------------------------
    -- Loading CRM Tables
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- silver.crm_cust_info
    ----------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_cust_info';
    TRUNCATE TABLE silver.crm_cust_info;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_cust_info';

    INSERT INTO silver.crm_cust_info (
        cst_id, 
        cst_key, 
        cst_firstname, 
        cst_lastname, 
        cst_marital_status, 
        cst_gndr,
        cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname),
        TRIM(cst_lastname),
        CASE 
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            ELSE 'n/a'
        END,
        CASE 
            WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
            WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
            ELSE 'n/a'
        END,
        cst_create_date
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
    ) t
    WHERE flag_last = 1;

    end_time := clock_timestamp();
    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    ----------------------------------------------------------------
    -- silver.crm_prd_info
    ----------------------------------------------------------------
    start_time := clock_timestamp();

    TRUNCATE TABLE silver.crm_prd_info;

    INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key FROM 1 FOR 5), '-', '_'),
        SUBSTRING(prd_key FROM 7),
        prd_nm,
        COALESCE(prd_cost, 0),
        CASE 
            WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
            WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
            WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
            WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
            ELSE 'n/a'
        END,
        prd_start_dt::date,
        (
            LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)
            - INTERVAL '1 day'
        )::date
    FROM bronze.crm_prd_info;

    end_time := clock_timestamp();
    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    ----------------------------------------------------------------
    -- silver.crm_sales_details
    ----------------------------------------------------------------
    start_time := clock_timestamp();

    TRUNCATE TABLE silver.crm_sales_details;

    INSERT INTO silver.crm_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )
    SELECT 
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE 
            WHEN sls_order_dt = 0 OR length(sls_order_dt::text) != 8 THEN NULL
            ELSE to_date(sls_order_dt::text, 'YYYYMMDD')
        END,
        CASE 
            WHEN sls_ship_dt = 0 OR length(sls_ship_dt::text) != 8 THEN NULL
            ELSE to_date(sls_ship_dt::text, 'YYYYMMDD')
        END,
        CASE 
            WHEN sls_due_dt = 0 OR length(sls_due_dt::text) != 8 THEN NULL
            ELSE to_date(sls_due_dt::text, 'YYYYMMDD')
        END,
        CASE 
            WHEN sls_sales IS NULL OR sls_sales <= 0 
                 OR sls_sales != sls_quantity * ABS(sls_price)
            THEN sls_quantity * ABS(sls_price)
            ELSE sls_sales
        END,
        sls_quantity,
        CASE 
            WHEN sls_price IS NULL OR sls_price <= 0 
            THEN sls_sales / NULLIF(sls_quantity, 0)
            ELSE sls_price
        END
    FROM bronze.crm_sales_details;

    end_time := clock_timestamp();
    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    ----------------------------------------------------------------
    -- erp_cust_az12
    ----------------------------------------------------------------
    start_time := clock_timestamp();

    TRUNCATE TABLE silver.erp_cust_az12;

    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT
        CASE
            WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid FROM 4)
            ELSE cid
        END,
        CASE
            WHEN bdate > CURRENT_DATE THEN NULL
            ELSE bdate
        END,
        CASE
            WHEN UPPER(TRIM(gen)) IN ('F','FEMALE') THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M','MALE') THEN 'Male'
            ELSE 'n/a'
        END
    FROM bronze.erp_cust_az12;

    ----------------------------------------------------------------
    batch_end_time := clock_timestamp();

    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Loading Silver Layer Completed';
    RAISE NOTICE 'Total Duration: % seconds',
        EXTRACT(EPOCH FROM (batch_end_time - batch_start_time));
    RAISE NOTICE '==========================================';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERROR OCCURRED: %', SQLERRM;
        RAISE;
END;
$$;
