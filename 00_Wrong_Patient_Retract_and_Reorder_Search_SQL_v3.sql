/*
;===============
;NAME:				Wrong Patient Retract and Reorder Search
;
;DESCRIPTION:		Identifies occurrences of a wrong patient retract and reorder event.
;					The general algorithm for a retract and reorder event is as follows:
;					- order is placed for patient A
;					- within 10 minutes, that order for patient A is canceled
;					- within 10 minutes of the cancelation, the same provider places an identical order for a different patient (presumably the correct one)
;					- no orders were placed for a different patient between the cancelation and re-order
;https://datahandbook.epic.com/Reports/Details/4290569?rank=1&queryid=74493745&docid=122667
;REVISION HISTORY:
; * RLC 03/19 - Created
; * RLC 11/19 - Finalize
; * Derek Harford - Modified to dump into a temp table to explore/expand upon final output
;===============

This script is intended to pull Wrong Patient Error (WPE) events specific to the occurrence of Retract and Reorder (RAR) events.


*/
USE CLARITY
DECLARE @StartDate DATE = '1/1/2021', -- Start Date
	    @EndDate   DATE = '1/1/2023' -- End Date (Not inclusive...add a day)

 -- ***** Add a custom date range here *****
--SET @StartDate = <custom start date>;
--SET @EndDate = <custom end date>;
 IF OBJECT_ID('tempdb..#RAR_ORDERS') IS NOT NULL
	DROP TABLE #RAR_ORDERS

 -- Default to previous month's data
IF @StartDate IS NULL SET @StartDate = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE())-1, 0);
IF @EndDate IS NULL SET @EndDate = EOMONTH(@StartDate);

 -- temp table containing background users
WITH BKGRD_USERS AS 
( SELECT USER_ID
  FROM CLARITY_EMP
  WHERE EMP_RECORD_TYPE_C = 6) -- Background user
,
ORD_DATA AS
 ( SELECT ORDER_METRICS.ORDER_ID,
          ORDER_METRICS.ORDER_DTTM,
		  CANCELATION.ORD_LST_ED_INST_TM,
		  CANCELATION.ORD_LST_ED_ACTION_C,
		  ORDER_METRICS.PAT_ID,
		  ORDER_METRICS.ORDERING_USER_ID,
		  MED.DISPENSABLE_MED_ID,
          ORDER_PROC.PROC_ID,
		  ZC_PAT_SERVICE.TITLE AS HOSP_SERVICE,
		  CLARITY_SER.PROV_TYPE AS USER_ROLE,
		  ORDER_METRICS.SESSION_KEY
	FROM ORDER_METRICS AS ORDER_METRICS
	LEFT JOIN PAT_ENC AS PE ON ORDER_METRICS.PAT_ENC_CSN_ID = PE.PAT_ENC_CSN_ID
	LEFT JOIN PAT_ENC_HSP AS PEH ON ORDER_METRICS.PAT_ENC_CSN_ID = PEH.PAT_ENC_CSN_ID
	LEFT JOIN ZC_PAT_SERVICE ON PEH.HOSP_SERV_C = ZC_PAT_SERVICE.HOSP_SERV_C
	LEFT JOIN ORDER_MEDINFO AS MED ON ORDER_METRICS.ORDER_ID = MED.ORDER_MED_ID
	LEFT JOIN ORDER_PROC AS ORDER_PROC ON ORDER_METRICS.ORDER_ID = ORDER_PROC.ORDER_PROC_ID
	LEFT JOIN ORDER_MED ON ORDER_METRICS.ORDER_ID = ORDER_MED.ORDER_MED_ID
	INNER JOIN VALID_PATIENT valid ON ORDER_METRICS.PAT_ID = valid.PAT_ID
	LEFT JOIN CLARITY_SER ON ORDER_METRICS.ORDERING_PROV_ID = CLARITY_SER.PROV_ID
	OUTER APPLY (	SELECT TOP 1 *
					FROM ORDER_LAST_EDIT AS CANCELATION
					WHERE ORDER_METRICS.ORDER_ID = CANCELATION.ORDER_ID  AND CANCELATION.ORD_LST_ED_ACTION_C = 4 -- Last Edit Action = Canceled 
					ORDER BY CANCELATION.LINE DESC	) AS CANCELATION
	WHERE ORDER_METRICS.ORDER_DTTM >= @StartDate
	AND ORDER_METRICS.ORDER_DTTM < @EndDate
	AND ( COALESCE ( ORDER_MED.ORD_CREATR_USER_ID,ORDER_PROC.ORD_CREATR_USER_ID, NULL )
			NOT IN ( SELECT USER_ID FROM BKGRD_USERS ) ) -- exclude interface and other background user orders
	AND ORDER_METRICS.ORDERING_USER_ID IS NOT NULL
	AND ORDER_METRICS.ORDER_MODE = 'Standard' -- Standard orders
	AND ORDER_METRICS.ORDER_DESC <> 'NURSING COMMUNICATION' -- Excluded because it is a commonly-used free-text order
	)
,
-- Wrong Patient Retract and Reorder Query
RAR_WP_CTE AS
( SELECT RAR_WP.ORDER_ID,
       ORDERING_USER_ID,
	   ORDER_DTTM,
	   ORD_LST_ED_INST_TM AS RETRACT_DTTM,
	   RETRACT_PERIOD,
	   CASE WHEN NXT_UNIQ_REORDER_DISP_MED_ID IS NOT NULL THEN NXT_UNIQ_REORDER_DISP_MED_ID
	    ELSE NXT_UNIQ_REORDER_PROC_ID END AS REORDER_ID,
	   CASE WHEN NXT_UNIQ_REORDER_DISP_MED_DTTM IS NOT NULL THEN NXT_UNIQ_REORDER_DISP_MED_DTTM
	    ELSE NXT_UNIQ_REORDER_PROC_DTTM END AS REORDER_DTTM,
	   CASE WHEN REORDER_PERIOD_DISP_MED IS NOT NULL THEN REORDER_PERIOD_DISP_MED
	    ELSE REORDER_PERIOD_PROC END AS REORDER_PERIOD,
	   USER_ROLE,
	   HOSP_SERVICE,
	   SESSION_KEY,
	   CURRENT_TIMESTAMP AS RAR_TRIGGER_TIMESTAMP
		-- ***** Add more columns here if you need more information about the order or user *****
 FROM ( SELECT RAR.ORDER_ID,
			   ORDERING_USER_ID,
	           USER_ROLE,
			   ORDER_DTTM,
			   ORD_LST_ED_INST_TM,
			   HOSP_SERVICE,
			   SESSION_KEY,
			   RETRACT_PERIOD,
			   NXT_UNIQ_REORDER_DISP_MED_DTTM,
			   DATEDIFF ( MINUTE, ORD_LST_ED_INST_TM, NXT_UNIQ_REORDER_DISP_MED_DTTM ) 'REORDER_PERIOD_DISP_MED',
			   NXT_UNIQ_REORDER_DISP_MED_ID,
			   NXT_UNIQ_REORDER_PROC_DTTM,
			   DATEDIFF ( MINUTE, ORD_LST_ED_INST_TM, NXT_UNIQ_REORDER_PROC_DTTM ) 'REORDER_PERIOD_PROC',
			   NXT_UNIQ_REORDER_PROC_ID,
			   CASE WHEN NXT_ORD_PAT_ID = NXT_UNIQ_REORDER_DISP_MED_PAT_ID 
					 AND NXT_ORD_PAT_ID <> PAT_ID 
					 AND RETRACT_PERIOD IS NOT NULL THEN CASE WHEN NXT_UNIQ_REORDER_DISP_MED_DTTM IS NULL THEN NULL
															  WHEN NXT_UNIQ_REORDER_DISP_MED_DTTM = ORDER_DTTM
															   OR DATEDIFF ( MINUTE, ORD_LST_ED_INST_TM, NXT_UNIQ_REORDER_DISP_MED_DTTM ) > 10 THEN NULL
															  WHEN ORD_LST_ED_INST_TM >= NXT_UNIQ_REORDER_DISP_MED_DTTM THEN NULL	-- if the original order was retracted after the reorder, then this wasn't a wp-rar
															  ELSE NXT_UNIQ_REORDER_DISP_MED_ID END
					ELSE NULL END AS MATCH_DISP_MED_RAR_ID,
			   CASE WHEN NXT_ORD_PAT_ID = NXT_UNIQ_REORDER_PROC_PAT_ID                                     -- make sure an order wasn't prescribed for a different patient in between a re-order of the same procedure
					 AND NXT_ORD_PAT_ID <> PAT_ID                                                      -- make sure the re-order wasn't for the same patient
					 AND RETRACT_PERIOD IS NOT NULL THEN CASE WHEN NXT_UNIQ_REORDER_PROC_DTTM IS NULL THEN NULL
															  WHEN NXT_UNIQ_REORDER_PROC_DTTM = ORDER_DTTM
															   OR DATEDIFF ( MINUTE, ORD_LST_ED_INST_TM, NXT_UNIQ_REORDER_PROC_DTTM ) > 10 THEN NULL  -- was the re-order within 10 minutes?
															  WHEN ORD_LST_ED_INST_TM >= NXT_UNIQ_REORDER_PROC_DTTM THEN NULL   -- if the original order was retracted after the reorder, then this wasn't a wp-rar
															  ELSE NXT_UNIQ_REORDER_PROC_ID END
					ELSE NULL END AS MATCH_PROC_RAR_ID
		 FROM ( SELECT ORDERING_USER_ID,
					   USER_ROLE,
					   ORDER_ID,
					   ORDER_DTTM,
					   ORD_LST_ED_INST_TM,
					   ORD_LST_ED_ACTION_C,
					   HOSP_SERVICE,
					   SESSION_KEY,
					   CASE WHEN DATEDIFF ( MINUTE, ORDER_DTTM, ORD_LST_ED_INST_TM ) <= 10         --only count retractions (cancellations) within 10 minutes
							 AND ORD_LST_ED_ACTION_C = 4 THEN FLOOR ( DATEDIFF ( MINUTE, ORDER_DTTM, ORD_LST_ED_INST_TM ) )
							ELSE NULL END AS RETRACT_PERIOD,
					   PAT_ID,
					   NXT_ORD_PAT_ID,
					   FIRST_VALUE ( NXT_REORDER_DISP_MED_DTTM ) OVER ( PARTITION BY ORDERING_USER_ID, DISPENSABLE_MED_ID, ORDER_DTTM ORDER BY ORDER_DTTM, ORDER_ID DESC ) AS NXT_UNIQ_REORDER_DISP_MED_DTTM,  --find the next order with the same dispensable med prescribed by this provider
					   FIRST_VALUE ( NXT_REORDER_DISP_MED_ID ) OVER ( PARTITION BY ORDERING_USER_ID, DISPENSABLE_MED_ID, ORDER_DTTM ORDER BY ORDER_DTTM, ORDER_ID DESC ) AS NXT_UNIQ_REORDER_DISP_MED_ID,
					   FIRST_VALUE ( NXT_REORDER_DISP_MED_PAT_ID ) OVER ( PARTITION BY ORDERING_USER_ID, DISPENSABLE_MED_ID, ORDER_DTTM ORDER BY ORDER_DTTM, ORDER_ID DESC ) AS NXT_UNIQ_REORDER_DISP_MED_PAT_ID,
					   FIRST_VALUE ( NXT_REORDER_PROC_DTTM ) OVER ( PARTITION BY ORDERING_USER_ID, PROC_ID, ORDER_DTTM ORDER BY ORDER_DTTM, ORDER_ID DESC ) AS NXT_UNIQ_REORDER_PROC_DTTM,                      --find the next order with the same procedure ID prescribed by this provider
					   FIRST_VALUE ( NXT_REORDER_PROC_ID ) OVER ( PARTITION BY ORDERING_USER_ID, PROC_ID, ORDER_DTTM ORDER BY ORDER_DTTM, ORDER_ID DESC ) AS NXT_UNIQ_REORDER_PROC_ID,
					   FIRST_VALUE ( NXT_REORDER_PROC_PAT_ID ) OVER ( PARTITION BY ORDERING_USER_ID, PROC_ID, ORDER_DTTM ORDER BY ORDER_DTTM, ORDER_ID DESC ) AS NXT_UNIQ_REORDER_PROC_PAT_ID
				 FROM ( SELECT ORDER_ID,
							   ORDER_DTTM,
							   ORD_LST_ED_INST_TM,
							   ORD_LST_ED_ACTION_C,
							   DISPENSABLE_MED_ID,
							   PROC_ID,
							   ORDERING_USER_ID,
							   USER_ROLE,
							   SESSION_KEY,
							   CASE WHEN DISPENSABLE_MED_ID IS NOT NULL 
									 AND ORD_LST_ED_ACTION_C = 4 THEN LEAD ( ORDER_DTTM ) OVER ( PARTITION BY ORDERING_USER_ID, DISPENSABLE_MED_ID ORDER BY ORDER_ID )
									ELSE NULL END AS NXT_REORDER_DISP_MED_DTTM,
							   CASE WHEN DISPENSABLE_MED_ID IS NOT NULL
							         AND ORD_LST_ED_ACTION_C = 4 THEN LEAD ( ORDER_ID ) OVER ( PARTITION BY ORDERING_USER_ID, DISPENSABLE_MED_ID ORDER BY ORDER_ID )
									ELSE NULL END AS NXT_REORDER_DISP_MED_ID,
							   CASE WHEN DISPENSABLE_MED_ID IS NOT NULL 
									 AND ORD_LST_ED_ACTION_C = 4 THEN LEAD ( PAT_ID ) OVER ( PARTITION BY ORDERING_USER_ID, DISPENSABLE_MED_ID ORDER BY ORDER_ID )
									ELSE NULL END AS NXT_REORDER_DISP_MED_PAT_ID,
							   CASE WHEN PROC_ID IS NOT NULL 
									 AND ORD_LST_ED_ACTION_C = 4 THEN LEAD ( ORDER_DTTM ) OVER ( PARTITION BY ORDERING_USER_ID, PROC_ID ORDER BY ORDER_ID )
									ELSE NULL END AS NXT_REORDER_PROC_DTTM,
							   CASE WHEN PROC_ID IS NOT NULL 
									 AND ORD_LST_ED_ACTION_C = 4 THEN LEAD ( ORDER_ID ) OVER ( PARTITION BY ORDERING_USER_ID, PROC_ID ORDER BY ORDER_ID )
									ELSE NULL END AS NXT_REORDER_PROC_ID,
							   CASE WHEN PROC_ID IS NOT NULL 
									 AND ORD_LST_ED_ACTION_C = 4 THEN LEAD ( PAT_ID ) OVER ( PARTITION BY ORDERING_USER_ID, PROC_ID ORDER BY ORDER_ID )
									ELSE NULL END AS NXT_REORDER_PROC_PAT_ID,
							   PAT_ID,
							   LEAD ( PAT_ID ) OVER ( PARTITION BY ORDERING_USER_ID ORDER BY ORDER_DTTM,ORDER_ID ) AS NXT_ORD_PAT_ID,                                    --next patient with any order from this provider
							   HOSP_SERVICE,
							   LAG ( ORDERING_USER_ID, 1 ) OVER ( ORDER BY ORD_DATA.ORDER_ID ) AS PREV_ORDERING_USER_ID,
							   LAG ( ORD_DATA.PAT_ID, 1 ) OVER ( ORDER BY ORD_DATA.ORDER_ID	) AS PREV_PAT_ID,
							   LAG ( ORDER_DTTM ) OVER ( ORDER BY ORD_DATA.ORDER_ID	) AS PREV_ORDER_DTTM
						 FROM ORD_DATA
						 ) ORD_DATA_AGG
				 WHERE ORD_DATA_AGG.NXT_ORD_PAT_ID IS NOT NULL
				  AND (ORD_DATA_AGG.NXT_REORDER_DISP_MED_PAT_ID IS NOT NULL 
					   OR ORD_DATA_AGG.NXT_REORDER_PROC_PAT_ID IS NOT NULL ) 
				 ) RAR
		 ) RAR_WP         
 WHERE ( MATCH_DISP_MED_RAR_ID IS NOT NULL OR MATCH_PROC_RAR_ID IS NOT NULL ) )

 
 SELECT ORDER_ID,
        ORDERING_USER_ID,
	    ORDER_DTTM,
	    RETRACT_DTTM,
	    RETRACT_PERIOD,
	    REORDER_ID,
	    REORDER_DTTM,
	    REORDER_PERIOD,
	    USER_ROLE,
	    HOSP_SERVICE,
		SESSION_KEY
		-- ***** Add more columns here if you need more information about the order or user *****
 INTO #RAR_ORDERS 
 FROM RAR_WP_CTE rar

 -- *********************************************************************************************************
 
 -- base RAR orders set
 SELECT 
	rar.*
	-- consolidated encounter type
	, COALESCE(pe.ENC_TYPE_C, pe2.ENC_TYPE_C) 			[Enc_Type_C]
	, COALESCE(zcEncType.NAME, zcEncType2.NAME) 		[Encounter_Type]
	-- consolidated proc/medication name
	, CASE 
		WHEN op1.ORDER_PROC_ID IS NOT NULL THEN 'Procedure'
		WHEN om.ORDER_MED_ID IS NOT NULL THEN 'Medication'
		ELSE '???' END AS [Order_Type]
	, COALESCE(eap1.PROC_NAME, med1.NAME) [Order_Name]
	, COALESCE(dep1.DEPARTMENT_NAME, dep2.DEPARTMENT_NAME) [Patient_Contact_Dept]
	--, op1.PAT_ENC_CSN_ID
	--, pe.ENC_TYPE_C
	--, zcEncType.NAME
	--, eap1.PROC_NAME
	--, med1.NAME
	--, pe2.ENC_TYPE_C
	--, zcEncType2.NAME
	--, OP2.PAT_LOC_ID
	--, om.PAT_LOC_ID
 FROM #RAR_ORDERS rar
	LEFT OUTER JOIN ORDER_PROC op1
		ON rar.ORDER_ID = op1.ORDER_PROC_ID
	LEFT OUTER JOIN CLARITY_EAP eap1
		ON op1.PROC_ID = eap1.PROC_ID
	LEFT OUTER JOIN ORDER_MED om
		ON rar.ORDER_ID = om.ORDER_MED_ID
	LEFT OUTER JOIN CLARITY_MEDICATION med1
		ON om.MEDICATION_ID = med1.MEDICATION_ID
	LEFT OUTER JOIN PAT_ENC pe
		ON op1.PAT_ENC_CSN_ID = pe.PAT_ENC_CSN_ID
	LEFT OUTER JOIN ZC_DISP_ENC_TYPE zcEncType
		ON pe.ENC_TYPE_C = zcEncType.DISP_ENC_TYPE_C
	LEFT OUTER JOIN PAT_ENC pe2
		ON om.PAT_ENC_CSN_ID = pe2.PAT_ENC_CSN_ID
	LEFT OUTER JOIN ZC_DISP_ENC_TYPE zcEncType2
		ON pe2.ENC_TYPE_C = zcEncType2.DISP_ENC_TYPE_C
	LEFT OUTER JOIN ORDER_PROC_2 op2
		ON op1.ORDER_PROC_ID = op2.ORDER_PROC_ID
	LEFT OUTER JOIN CLARITY_DEP dep1
		ON op2.PAT_LOC_ID = dep1.DEPARTMENT_ID
	LEFT OUTER JOIN CLARITY_DEP dep2
		ON om.PAT_LOC_ID = dep2.DEPARTMENT_ID

/*
-- SQL Snippets for exploration

SELECT COUNT(1) [Total RAR Orders]
FROM #RAR_ORDERS r

SELECT
	DATEPART(year,r.ORDER_DTTM) [Year]
	, COUNT(1)
FROM #RAR_ORDERS r
GROUP BY DATEPART(year,r.ORDER_DTTM)

SELECT
	DATEPART(MONTH,r.ORDER_DTTM) [Year]
	, COUNT(1)
FROM #RAR_ORDERS r
GROUP BY DATEPART(MONTH,r.ORDER_DTTM)
ORDER BY 1 ASC

-- for all ordering users in RAR, determine how many orders they made in timeframe

SELECT DISTINCT COUNT(USER_ROLE) [Distinct User Role]
FROM #RAR_ORDERS

*/

-- *********************************************************************************************************************

IF OBJECT_ID('tempdb..#rar_orders_final') IS NOT NULL 
    DROP TABLE #rar_orders_final
SELECT
    r.*
	, op1.PAT_ID
	, op1.PAT_ENC_CSN_ID
    , 'Procedure Order' [Procedure_Or_Medication]
    , op.PAT_LOC_ID
    , op1.ORD_CREATR_USER_ID
    , op1.BILLING_PROV_ID
    , op1.AUTHRZING_PROV_ID
    , dep.DEPARTMENT_NAME
    , dep2.ICU_DEPT_YN
    , dep.SPECIALTY
	, reorderOP.PAT_LOC_ID [REORDER_PAT_LOC_ID]
    --, CAST(r.ORDER_DTTM AS DATE) [order_date]
	, reorderOP.PAT_ENC_CSN_ID [REORDER_PAT_ENC_CSN_ID]
INTO #rar_orders_final
FROM #RAR_ORDERS r
    INNER JOIN ORDER_PROC_2 op 
        ON r.ORDER_ID = op.ORDER_PROC_ID
    INNER JOIN ORDER_PROC op1
        ON op.ORDER_PROC_ID = op1.ORDER_PROC_ID
    INNER JOIN CLARITY_DEP dep 
        ON op.PAT_LOC_ID = dep.DEPARTMENT_ID
    INNER JOIN CLARITY_DEP_2 dep2
        ON dep.DEPARTMENT_ID = dep2.DEPARTMENT_ID
	INNER JOIN ORDER_PROC_2 reorderOP
		ON r.REORDER_ID = reorderOP.ORDER_PROC_ID
UNION
SELECT
    r.*
	, op.PAT_ID
	, op.PAT_ENC_CSN_ID
    ,'Medication Order'
    , op.PAT_LOC_ID
    , op.ORD_CREATR_USER_ID
    , NULL
    , op.AUTHRZING_PROV_ID
    -- , op1.ORD_CREATR_USER_ID
    -- , op1.BILLING_PROV_ID
    -- , op1.AUTHRZING_PROV_ID
    , dep.DEPARTMENT_NAME
    , dep2.ICU_DEPT_YN
    , dep.SPECIALTY
    --, CAST(r.ORDER_DTTM AS DATE) [order_date]
	, reorderOM.PAT_LOC_ID
	, reorderOM.PAT_ENC_CSN_ID [REORDER_PAT_ENC_CSN_ID]
FROM #RAR_ORDERS r
    INNER JOIN ORDER_MED op 
        ON r.ORDER_ID = op.ORDER_MED_ID
    INNER JOIN CLARITY_DEP dep 
        ON op.PAT_LOC_ID = dep.DEPARTMENT_ID
    INNER JOIN CLARITY_DEP_2 dep2
        ON dep.DEPARTMENT_ID = dep2.DEPARTMENT_ID
	INNER JOIN ORDER_MED reorderOM
		ON r.REORDER_ID = reorderOM.ORDER_MED_ID



select 'final output to be saved'
INSERT [WU_I2].[dbo].[AHRQ_WPE_RAR_EVENT]
SELECT
	f.ORDER_ID
	, zcEncType.NAME [Original_Order_Enc_Type]
	, f.ORDERING_USER_ID
	, f.PAT_ID
	, f.PAT_ENC_CSN_ID
	, f.ORDER_DTTM
	, f.RETRACT_DTTM
	, f.RETRACT_PERIOD
	, f.REORDER_ID
	, zcEncType2.NAME [ReOrder_Enc_Type]
	, f.REORDER_DTTM
	, f.REORDER_PERIOD
	, f.USER_ROLE
	, ecl.CLASSIFCTN_NAME
	, dflt_template.NAME [Default_Linkable_Template]-- what was this user's template?
	, ser.PROV_TYPE
	, f.HOSP_SERVICE
	, f.SESSION_KEY
	, f.Procedure_Or_Medication
	-- , vUser.*
	, dd.WEEK_BEGIN_DT
    , dd.WEEK_BEGIN_DT_STR
	, dd.DAY_OF_WEEK
	-- , CASE 
    --     WHEN f.SPECIALTY = 'Emergency Medicine' THEN 'ED'
    --     WHEN f.ICU_DEPT_YN = 'Y' THEN 'ICU'
    --     ELSE '???' END AS [Department Type]
	, wpe_accessLog_window.log_window_start
	, wpe_accessLog_window.log_window_stop
	, original_order_location.DEPARTMENT_NAME			[ORIGINAL_ORDER_DEPT_NAME]
	, original_order_location.DEPARTMENT_SPECIALTY		[ORIGINAL_ORDER_DEPT_SPECIALTY]
	, original_order_location.POS_TYPE					[ORIGINAL_ORDER_POS_TYPE]
	, reorder_location.DEPARTMENT_NAME					[REORDER_DEPT_NAME]
	, reorder_location.DEPARTMENT_SPECIALTY				[REORDER_DEPT_SPECIALTY]
	, reorder_location.POS_TYPE							[REORDER_POS_TYPE]
	, CASE
		WHEN original_order_location.DEPARTMENT_NAME = reorder_location.DEPARTMENT_NAME THEN 'Y'
		ELSE 'N' END [ORDERING_DEPT_MATCH_YN] 
	--, reorder_location.*
	--, f.*
FROM #rar_orders_final f
	LEFT OUTER JOIN CLARITY_EMP emp
		ON emp.USER_ID = f.ORD_CREATR_USER_ID
	LEFT OUTER JOIN CLARITY_EMP_2 emp2
        ON emp.USER_ID = emp2.USER_ID
    LEFT OUTER JOIN CLARITY_EMP dflt_template
        ON emp2.DFLT_LNK_TEMPLT_ID = dflt_template.USER_ID
	LEFT OUTER JOIN CLARITY_ECL ecl
		ON emp.MR_CLASS_C = ecl.ECL_ID
	LEFT OUTER JOIN CLARITY_SER ser
		ON emp.USER_ID = ser.USER_ID
	-- LEFT OUTER JOIN V_REPORT_USER_FACT vUser 
    --     ON f.ORDERING_USER_ID = vUser.USER_ID
	LEFT OUTER JOIN DATE_DIMENSION dd 
        ON CAST(f.ORDER_DTTM AS DATE) = dd.CALENDAR_DT
	OUTER APPLY ( -- Adds timewindow start/stop for access log pulls later on.  discussed with Thomas over Teams
		VALUES (DATEADD(DAY, -30, f.REORDER_DTTM),
				DATEADD(HOUR, 12, f.REORDER_DTTM)
				)
	) wpe_accessLog_window ([log_window_start], [log_window_stop])
	LEFT OUTER JOIN V_CUBE_D_DEP_LOC original_order_location
		ON f.PAT_LOC_ID = original_order_location.DEPARTMENT_ID
	LEFT OUTER JOIN V_CUBE_D_DEP_LOC reorder_location
		ON f.REORDER_PAT_LOC_ID = reorder_location.DEPARTMENT_ID
	LEFT OUTER JOIN PAT_ENC pe
		ON pe.PAT_ENC_CSN_ID = f.PAT_ENC_CSN_ID
	LEFT OUTER JOIN ZC_DISP_ENC_TYPE zcEncType
		ON pe.ENC_TYPE_C = zcEncType.DISP_ENC_TYPE_C
	LEFT OUTER JOIN PAT_ENC pe2
		ON pe2.PAT_ENC_CSN_ID = f.REORDER_PAT_ENC_CSN_ID
	LEFT OUTER JOIN ZC_DISP_ENC_TYPE zcEncType2
		ON pe2.ENC_TYPE_C = zcEncType2.DISP_ENC_TYPE_C


/*

-- other SQL exploration


SELECT
	COUNT(1) [TOTAL ROWS IN RAR_ORDERS]
	, COUNT(DISTINCT r.ORDER_ID) [Unique Order IDs]
	, COUNT(DISTINCT r.REORDER_ID) [Unique ReOrder IDs]
FROM #RAR_ORDERS r 

SELECT
	COUNT(1) [TOTAL ROWS IN RAR_ORDERS_FINAL]
	, COUNT(DISTINCT r.ORDER_ID) [Unique Order IDs]
	, COUNT(DISTINCT r.REORDER_ID) [Unique ReOrder IDs]
	, COUNT(DISTINCT r.PAT_ENC_CSN_ID) [Unique PAT_ENC_CSN_IDs]
	, COUNT(DISTINCT r.REORDER_PAT_ENC_CSN_ID) [Unique Reorder PAT_ENC_CSN_IDs]
FROM #rar_orders_final r



-- select distinct pat_id's and ordering_user_id's

SELECT 
	DISTINCT(f.ORDERING_USER_ID) [ORDERING_USER_ID]
	, NEWID() [Masked_Ordering_User_ID]
FROM #rar_orders_final f

SELECT 
	DISTINCT(f.ORD_CREATR_USER_ID) [ORDERING_USER_ID]
	, NEWID() [Masked_Ordering_User_ID]
FROM #rar_orders_final f




SELECT
	MIN(CAST(T.ORDER_DTTM AS DATE))
	, MAX(CAST(T.ORDER_DTTM AS DATE))
FROM [WU_I2].[dbo].[AHRQ_WPE_RAR_EVENT] T 


SELECT
	YEAR(t.ORDER_DTTM) [Year], COUNT(1) [Count]
FROM [WU_I2].[dbo].[AHRQ_WPE_RAR_EVENT] T
GROUP BY YEAR(t.ORDER_DTTM)
ORDER BY 1

SELECT
	YEAR(t.ORDER_DTTM) [Year]
    , COUNT(1) [Count]
    , COUNT(1) * 15000 [Est. Count of Access Logs]
FROM [WU_I2].[dbo].[AHRQ_WPE_RAR_EVENT] T
GROUP BY YEAR(t.ORDER_DTTM)
ORDER BY 1

SELECT TOP 1 * FROM ACCESS_LOG
*/

