/*
Access Logs
       - Remove Overlapping dates and consolidate

*/
-- create table statement?
-- update insert method from lazy to professional

use [WU_I2]

Select
       ROW_NUMBER()Over(Order By[ORDERING_USER_ID],[Log_Ord])[ID]
,      [ORDERING_USER_ID]
,      [Log_Ord]
,      [1][New_Log_Start]
,      [2][New_Log_Stop]
INTO [WU_I2].[dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]
From(
       Select 
              [ORDERING_USER_ID]
       ,      DENSE_RANK()Over(Partition By[ORDERING_USER_ID],[StrStp]Order By[log_window_dtm])[Log_Ord]
       ,      [StrStp]
       ,      [log_window_dtm]
       From (
              Select
                     [ORDER_ID]
              ,      [ORDERING_USER_ID]
              ,      [log_window_start]
              ,      [log_window_stop]
              ,      DateDiff(HH,ISNULL(LAG([log_window_stop])Over(Partition By[ORDERING_USER_ID]Order By[log_window_start],[log_window_stop],[ORDER_ID]),[log_window_start]),[log_window_start])[Prv_Dif]
              ,      DateDiff(HH,[log_window_stop],ISNULL(LEAD([log_window_start])Over(Partition By[ORDERING_USER_ID]Order By[log_window_start],[log_window_stop],[ORDER_ID]),[log_window_stop]))[Nxt_Dif]
              From[WU_I2].[dbo].[AHRQ_WPE_RAR_EVENT]
       ) o
       Cross Apply(
              Values(
                     Case When[Prv_Dif]<0Then 0 --<< There is overlap: Remove Row
                     Else 1 End
              +      Case When[Nxt_Dif]<0Then 0 --<< there is overlap: Remove Row
                     Else 2 End
              )
       )t([StrStpBtw])
       Cross Apply(
              Values
                     (1     ,[log_window_start])
              ,      (2     ,[log_window_stop])
       )c([StrStp],[log_window_dtm])
       Where[StrStpBtw]=3OR[StrStpBtw]=[StrStp]
       --[StrStpBtw]>0      --<< Exclude these
)s
Pivot(
       MIN([log_window_dtm])For[StrStp]in([1],[2])
)p