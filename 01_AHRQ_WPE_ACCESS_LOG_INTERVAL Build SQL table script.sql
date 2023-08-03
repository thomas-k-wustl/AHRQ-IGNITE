USE [WU_I2]
GO

/****** Object:  Table [dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]    Script Date: 7/18/2023 3:46:57 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'#EE_AHRQ_WPE_ACCESS_LOG_INTERVAL') AND type in (N'U'))
DROP TABLE #EE_AHRQ_WPE_ACCESS_LOG_INTERVAL
GO

/****** Object:  Table [dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]    Script Date: 7/18/2023 3:46:57 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE #EE_AHRQ_WPE_ACCESS_LOG_INTERVAL(
	[ID] [bigint] NULL,
	[ORDERING_USER_ID] [varchar](18) NULL,
	[Log_Ord] [bigint] NULL,
	[New_Log_Start] [datetime] NULL,
	[New_Log_Stop] [datetime] NULL,
	[Status] [int] NOT NULL,
	[ErrorNumber] [int] NULL,
	[ErrorMessage] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


