USE [WU_I2]
GO

/****** Object:  Table [dbo].[AHRQ_WPE_RAR_EVENT]    Script Date: 5/4/2023 12:51:34 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[AHRQ_WPE_RAR_EVENT](
	[ORDER_ID] [numeric](18, 0) NOT NULL,
	[Original_Order_Enc_Type] [varchar](254) NULL,
	[ORDERING_USER_ID] [varchar](18) NULL,
	[PAT_ID] [varchar](18) NULL,
	[PAT_ENC_CSN_ID] [numeric](18, 0) NULL,
	[ORDER_DTTM] [datetime] NULL,
	[RETRACT_DTTM] [datetime] NULL,
	[RETRACT_PERIOD] [int] NULL,
	[REORDER_ID] [numeric](18, 0) NULL,
	[ReOrder_Enc_Type] [varchar](254) NULL,
	[REORDER_DTTM] [datetime] NULL,
	[REORDER_PERIOD] [int] NULL,
	[USER_ROLE] [varchar](66) NULL,
	[CLASSIFCTN_NAME] [varchar](80) NULL,
	[Default_Linkable_Template] [varchar](160) NULL,
	[PROV_TYPE] [varchar](66) NULL,
	[HOSP_SERVICE] [varchar](254) NULL,
	[SESSION_KEY] [varchar](254) NULL,
	[Procedure_Or_Medication] [varchar](16) NOT NULL,
	[WEEK_BEGIN_DT] [datetime] NULL,
	[WEEK_BEGIN_DT_STR] [varchar](10) NULL,
	[DAY_OF_WEEK] [varchar](18) NULL,
	[log_window_start] [datetime] NULL,
	[log_window_stop] [datetime] NULL,
	[ORIGINAL_ORDER_DEPT_NAME] [varchar](254) NULL,
	[ORIGINAL_ORDER_DEPT_SPECIALTY] [varchar](254) NULL,
	[ORIGINAL_ORDER_POS_TYPE] [varchar](254) NULL,
	[REORDER_DEPT_NAME] [varchar](254) NULL,
	[REORDER_DEPT_SPECIALTY] [varchar](254) NULL,
	[REORDER_POS_TYPE] [varchar](254) NULL,
	[ORDERING_DEPT_MATCH_YN] [varchar](1) NOT NULL
) ON [PRIMARY]
GO


