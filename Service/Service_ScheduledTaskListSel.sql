ALTER  PROCEDURE [dbo].[Service_ScheduledTaskListSel]
AS
BEGIN	
/*
Created: 20120611@Jacob Phan
Task : Get all scheduled tasks
DB: DB052.[bodb_Licensee]

Revisions:
   

*/
	SET NOCOUNT ON
	SELECT [ScheduledTaskId],
		[Description],
		[CronExpression],
		[Implementation],
		[Configuration],
		[NextRun],
		[LastRun],
		[LastFinish],
		[Active]
		FROM dbo.[Service_ScheduledTask] WITH(NOLOCK)
	SET NOCOUNT OFF
END
/*
EXEC dbo.[S_ScheduledTaskListSel]
*/


GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskListSel] TO [bodbAdminNet] 
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskListSel] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskListSel] TO [vnteam] 