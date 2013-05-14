ALTER  PROCEDURE [dbo].[Service_ScheduledTaskLogSel]
	@ScheduledTaskLogId INT
AS
BEGIN	
/*
Created: 20120611@Jacob Phan
Task : Get task log by id
DB: DB052.[bodb_Licensee]

Revisions:
	
   

*/
	SET NOCOUNT ON
	SELECT  [ScheduledTaskLogId],
			[ScheduledTaskId],
			[Description], 
			[Status], 
			[Data], 
			[LogMessage],
			[StartDate], 
			[FinishDate] 				
	FROM dbo.[Service_ScheduledTaskLog] WITH(NOLOCK)
	WHERE [ScheduledTaskLogId] = @ScheduledTaskLogId
	SET NOCOUNT OFF
END
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogSel] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogSel] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskLogSel] TO [vnteam]  