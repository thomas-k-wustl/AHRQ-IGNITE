/*
	Cursor that iteratively pulls Epic access log data per event in event interval table

*/


Declare 
       @ID int 
,      @User_ID varchar(16)
,      @Log_Start datetime
,      @Log_Stop datetime
;
---- Declare the Cursor Object and assign the query
Declare [LogUsr] Cursor Local Forward_only Static Read_Only for
       Select 
              [ID]
       ,      [ORDERING_USER_ID]
       ,      [New_Log_Start]
       ,      [New_Log_Stop]
       From [WU_I2].[dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]
	   WHERE [Status] = 0
       Order by ID
;
---- Open the Cursor and fetch first row
Open [LogUsr]
Fetch Next From [LogUsr] into @ID,@User_ID,@Log_Start,@Log_Stop
---- Begin the Loop 
While @@FETCH_STATUS=0 --
Begin
	-- Execute Query to pull the base data using Variables
	-- Need this to kill cursor at 9pm CST prior to research Clarity refresh
    IF DATEPART(HOUR, GETDATE()) > 20
    BEGIN
        -- Exit the cursor loop if the current hour is past 8pm
        BREAK;
    END
	
	--- Update Status to show it is being processed
	Update [WU_I2].[dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]
	Set Status = 2
	Where ID=@ID

	/*
	Execute Query to pull the base data using Variables
	*/
	BEGIN TRY
		Insert[WU_I2].[dbo].[AHRQ_WPE_ACCESS_LOG]
		([ACCESS_INSTANT]
		  ,[PROCESS_ID]
		  ,[ACCESS_TIME]
		  ,[METRIC_ID]
		  ,[USER_ID]
		  ,[PAT_ID]
		  ,[CSN]
		  ,[ACCESS_ACTION_C])
	
		Select
			[ACCESS_INSTANT]
			,[PROCESS_ID]
			,[ACCESS_TIME]
			,[METRIC_ID]
			,[USER_ID]
			,[PAT_ID]
			,[CSN]
			,[ACCESS_ACTION_C]
		From [CLARITY]..[ACCESS_LOG] alg
		Where
			  (      [ACCESS_TIME]>=@Log_Start
			  And    [ACCESS_TIME]<@Log_Stop)
			  And [USER_ID]=@User_ID
			  And [PROCESS_ID] Like 'prd%'
		;      
		--- Update Status to show it is completed
		Update [WU_I2].[dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]
		Set Status = 1
		Where ID=@ID
;
	END TRY
	BEGIN CATCH
		IF @@TranCount>0
       		ROLLBACK;
		
		--- Update Status to show that it errored
		Update [WU_I2].[dbo].[AHRQ_WPE_ACCESS_LOG_INTERVAL]
			SET ErrorNumber = ERROR_NUMBER(),
				 ErrorMessage = ERROR_MESSAGE(),
				 Status = 4
		Where ID=@ID

		-- SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
	END CATCH;
	---- Load the next row from the cursor
	Fetch Next From [LogUsr] into @ID,@User_ID,@Log_Start,@Log_Stop
;
End
---- Cleanup Cursor: Close and Deallocate 
Close[LogUsr]
Deallocate[LogUsr]
;