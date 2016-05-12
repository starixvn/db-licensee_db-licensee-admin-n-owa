ALTER  PROCEDURE [dbo].[Service_ScheduledTaskDateUpd]
	@ScheduledTaskId INT,
	@NextRun DATETIME = NULL,
	@LastRun DATETIME = NULL,
	@LastFinish DATETIME = NULL
AS
BEGIN	
/*
Created: 20120611@Jacob Phan
Task : Update scheduled task Next Run, Last Run, Last Finish
DB: DB052.[bodb_Licensee]

Revisions:
   

*/
	SET NOCOUNT ON
	
	IF @NextRun IS NOT NULL
	BEGIN
		UPDATE dbo.[Service_ScheduledTask]
		SET [NextRun] = @NextRun
		WHERE [ScheduledTaskId] = @ScheduledTaskId
	END
	
	
	IF @LastRun IS NOT NULL
	BEGIN
		UPDATE dbo.[Service_ScheduledTask]
		SET [LastRun] = @LastRun
		WHERE [ScheduledTaskId] = @ScheduledTaskId
	END
	
	
	IF @LastFinish IS NOT NULL
	BEGIN
		UPDATE dbo.[Service_ScheduledTask]
		SET [LastFinish] = @LastFinish
		WHERE [ScheduledTaskId] = @ScheduledTaskId
	END
	
	SET NOCOUNT OFF
END


GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskDateUpd] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskDateUpd] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskDateUpd] TO [vnteam]