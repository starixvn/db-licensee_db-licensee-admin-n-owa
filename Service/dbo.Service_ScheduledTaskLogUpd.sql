ALTER  PROCEDURE [dbo].[Service_ScheduledTaskLogUpd]
	@ScheduledTaskLogId INT,
	@Description NVARCHAR(MAX) ='',
	@Data NVARCHAR(MAX)='',
	@Status TINYINT = 0,
	@LogMessage NVARCHAR(MAX)='',
	@StartDate DATETIME = NULL,
	@FinishDate DATETIME = NULL
AS
BEGIN	
/*
Created: 20120611@Jacob Phan
Task : Update scheduled task log
DB: DB052.[bodb_Licensee]

Revisions:
   

*/
	SET NOCOUNT ON
	
	UPDATE dbo.[Service_ScheduledTaskLog]
	SET [Description] = @Description,
	 [Status] = @Status,
	 [Data] = @Data,
	 [LogMessage] = @LogMessage,
	 [StartDate] = @StartDate,
	 [FinishDate] = @FinishDate	
	WHERE [ScheduledTaskLogId] = @ScheduledTaskLogId
	
	SET NOCOUNT OFF
END 
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogUpd] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogUpd] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskLogUpd] TO [vnteam]  