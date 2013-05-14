ALTER  PROCEDURE [dbo].[Service_ScheduledTaskLogCountSel]
	@Status TINYINT = NULL
AS
BEGIN	
/*
Created: 20120611@Jacob Phan
Task : Get task log count by status
DB: DB052.[bodb_Licensee]

Revisions:
	@Status:
		*0: 
		*1: Pending
		*2: Running
		*3: Success
		*4: Fail 
   

*/
	SET NOCOUNT ON
	
	IF @Status IS NULL
	BEGIN
		SELECT COUNT(1) 
		FROM dbo.[Service_ScheduledTaskLog] WITH(NOLOCK)
	END
	ELSE
	BEGIN
		SELECT COUNT(1) 
		FROM dbo.[Service_ScheduledTaskLog]
		WHERE [Status] = @Status
	END
	
	SET NOCOUNT OFF
END
/*

*/
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogCountSel] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogCountSel] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskLogCountSel] TO [vnteam] 